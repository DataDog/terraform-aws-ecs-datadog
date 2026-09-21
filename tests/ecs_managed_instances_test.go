// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"encoding/json"
	"log"
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/suite"
)

// ECSManagedInstancesSuite defines the test suite for ecs_managed_instances.
// Every fixture in smoke_tests/ecs_managed_instances sets create_daemon =
// false, so this suite only ever creates a daemon task definition (plus its
// IAM roles) - never a real aws_ecs_daemon, which would require a live ECS
// Managed Instances capacity provider ARN. That path is exercised separately,
// manually, against real Managed Instances infrastructure.
type ECSManagedInstancesSuite struct {
	suite.Suite
	terraformOptions *terraform.Options
	testPrefix       string
}

// TestECSManagedInstancesSuite is the entry point for the test suite
func TestECSManagedInstancesSuite(t *testing.T) {
	suite.Run(t, new(ECSManagedInstancesSuite))
}

// SetupSuite is run once at the beginning of the test suite
func (s *ECSManagedInstancesSuite) SetupSuite() {
	log.Println("Setting up ECS Managed Instances test suite resources...")

	s.testPrefix = "terraform-test"
	ciJobID := os.Getenv("CI_JOB_ID")
	if ciJobID != "" {
		s.testPrefix = s.testPrefix + "-" + ciJobID
	}

	s.terraformOptions = &terraform.Options{
		TerraformDir: "../smoke_tests/ecs_managed_instances",
		Vars: map[string]any{
			"dd_api_key":  "test-api-key",
			"dd_site":     "datadoghq.com",
			"test_prefix": s.testPrefix,
		},
		RetryableTerraformErrors: map[string]string{
			"couldn't find resource": "terratest could not find the resource. check for access denied errors in cloudtrail",
		},
	}

	terraform.InitAndApply(s.T(), s.terraformOptions)
}

// TearDownSuite is run once at the end of the test suite
func (s *ECSManagedInstancesSuite) TearDownSuite() {
	log.Println("Tearing down ECS Managed Instances test suite resources...")
	terraform.Destroy(s.T(), s.terraformOptions)
}

// unmarshalMIContainer decodes the module's container_definition output
// (a single JSON object, not an array) for the given fixture output name.
func (s *ECSManagedInstancesSuite) unmarshalMIContainer(outputName string) MIContainerDefinition {
	raw := terraform.Output(s.T(), s.terraformOptions, outputName)
	var container MIContainerDefinition
	err := json.Unmarshal([]byte(raw), &container)
	s.Require().NoError(err, "Failed to parse container_definition output %s", outputName)
	return container
}

// TestDefaultConfiguration verifies the base env vars, UDS socket
// volume/mount, and containerd/proc/cgroup host mounts are all present with
// the correct host and container paths under default settings.
func (s *ECSManagedInstancesSuite) TestDefaultConfiguration() {
	log.Println("TestDefaultConfiguration: Running test...")

	s.Equal(s.testPrefix+"-default", terraform.Output(s.T(), s.terraformOptions, "default_family"))

	container := s.unmarshalMIContainer("default_container_definition")

	s.Equal("datadog-agent", container.Name)
	s.True(container.Essential)

	expectedEnvVars := map[string]string{
		"ECS_MANAGED_INSTANCES":         "true",
		"DD_INSTALL_INFO_TOOL":          "terraform",
		"DD_INSTALL_INFO_TOOL_VERSION":  "terraform-aws-ecs-datadog",
		"DD_API_KEY":                    "test-api-key",
		"DD_SITE":                       "datadoghq.com",
		"DD_CRI_SOCKET_PATH":            "/var/run/containerd/containerd.sock",
		"DD_DOGSTATSD_ORIGIN_DETECTION": "true",
		"DD_APM_ENABLED":                "true",
	}
	AssertMIEnvVars(s.T(), container, expectedEnvVars)

	// UDS socket mount (default transport)
	AssertMIMountPoint(s.T(), container, MIMountPoint{SourceVolume: "dd-sockets", ContainerPath: "/var/run/datadog", ReadOnly: false})

	// containerd/proc/cgroup host mounts - ECS Managed Instances runs
	// containerd, not Docker, so these replace ecs_ec2's docker.sock mount.
	AssertMIMountPoint(s.T(), container, MIMountPoint{SourceVolume: "containerd_sock", ContainerPath: "/var/run/containerd/containerd.sock", ReadOnly: true})
	AssertMIMountPoint(s.T(), container, MIMountPoint{SourceVolume: "proc", ContainerPath: "/host/proc", ReadOnly: true})
	AssertMIMountPoint(s.T(), container, MIMountPoint{SourceVolume: "cgroup", ContainerPath: "/host/sys/fs/cgroup", ReadOnly: true})

	// Default health check matches Datadog's documented command for ECS
	// Managed Instances daemon mode, not ecs_ec2/ecs_fargate's /probe.sh.
	s.Require().NotNil(container.HealthCheck, "Agent health check should be defined")
	s.Equal([]string{"CMD-SHELL", "agent health"}, container.HealthCheck.Command)
	s.Equal(30, container.HealthCheck.Interval)
	s.Equal(3, container.HealthCheck.Retries)
	s.Equal(15, container.HealthCheck.StartPeriod)
	s.Equal(5, container.HealthCheck.Timeout)

	// Network monitoring and process collection are off by default.
	s.Nil(container.LinuxParameters, "LinuxParameters should be nil when network monitoring is disabled")
	AssertMINotEnvVars(s.T(), container, []string{
		"DD_SYSTEM_PROBE_NETWORK_ENABLED",
		"DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED",
	})
}

// TestCreateDaemonDisabled verifies create_daemon = false skips creating the
// aws_ecs_daemon resource while still creating the task definition.
func (s *ECSManagedInstancesSuite) TestCreateDaemonDisabled() {
	log.Println("TestCreateDaemonDisabled: Running test...")

	// Terraform omits root module outputs from state entirely when their
	// value is null, so terraform.Output (which errors on a missing key)
	// can't be used directly here - a "not found" error IS the confirmation
	// that daemon_arn is null.
	daemonArn, err := terraform.OutputE(s.T(), s.terraformOptions, "default_daemon_arn")
	if err != nil {
		s.Contains(err.Error(), "not found", "expected only a 'not found' error for a null output, got: %v", err)
		return
	}
	s.Empty(daemonArn, "daemon_arn should be empty/null when create_daemon = false")
}

// TestEnvironmentOverride verifies dd_environment overrides a module-set
// variable by name. environment is a Terraform Set block on
// aws_ecs_daemon_task_definition, so naive concatenation (as used by the
// other two submodules) would produce a duplicate Set member instead of an
// override - this proves the dedupe-by-name logic in datadog.tf works.
func (s *ECSManagedInstancesSuite) TestEnvironmentOverride() {
	log.Println("TestEnvironmentOverride: Running test...")

	container := s.unmarshalMIContainer("environment_override_container_definition")

	value, found := GetMIEnvVar(container, "DD_SITE")
	s.True(found, "DD_SITE should be present")
	s.Equal("datadoghq.eu", value, "dd_environment override should replace the module-set DD_SITE value, not duplicate it")

	// Confirm there is exactly one DD_SITE entry (no duplicate Set member).
	count := 0
	for _, env := range container.Environment {
		if env.Name == "DD_SITE" {
			count++
		}
	}
	s.Equal(1, count, "DD_SITE should appear exactly once in the environment")
}

// TestNetworkMonitoring verifies Cloud Network Monitoring wires up the env
// var, the exact documented capability list, and the /sys/kernel/debug mount.
func (s *ECSManagedInstancesSuite) TestNetworkMonitoring() {
	log.Println("TestNetworkMonitoring: Running test...")

	container := s.unmarshalMIContainer("network_monitoring_container_definition")

	AssertMIEnvVars(s.T(), container, map[string]string{
		"DD_SYSTEM_PROBE_NETWORK_ENABLED": "true",
	})

	s.Require().NotNil(container.LinuxParameters, "LinuxParameters should be set when network monitoring is enabled")
	expectedCapabilities := []string{
		"SYS_ADMIN", "SYS_RESOURCE", "SYS_PTRACE", "NET_ADMIN",
		"NET_BROADCAST", "NET_RAW", "IPC_LOCK", "CHOWN",
	}
	s.ElementsMatch(expectedCapabilities, container.LinuxParameters.Capabilities.Add)

	AssertMIMountPoint(s.T(), container, MIMountPoint{SourceVolume: "debug", ContainerPath: "/sys/kernel/debug", ReadOnly: false})
}

// TestProcessCollection verifies the process-collection env var is set.
func (s *ECSManagedInstancesSuite) TestProcessCollection() {
	log.Println("TestProcessCollection: Running test...")

	container := s.unmarshalMIContainer("process_collection_container_definition")

	AssertMIEnvVars(s.T(), container, map[string]string{
		"DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED": "true",
	})
}

// TestInvalidConfigurations verifies the module fails fast (at plan time,
// before touching AWS) on configurations that ECS Managed Instances daemon
// mode cannot support: agent-based log collection, and DogStatsD enabled
// with neither UDS nor TCP transport configured. This uses a separate root
// module (smoke_tests/ecs_managed_instances_invalid) so a failing
// precondition here cannot break the main suite's apply/destroy lifecycle.
// It is intentionally not part of ECSManagedInstancesSuite: plan alone
// evaluates preconditions without creating any real resources, so no
// TearDown/Destroy is needed.
func TestInvalidConfigurations(t *testing.T) {
	terraformOptions := &terraform.Options{
		TerraformDir: "../smoke_tests/ecs_managed_instances_invalid",
		Vars: map[string]any{
			"dd_api_key": "test-api-key",
		},
		// Terraform's default colorized output injects ANSI escape codes
		// mid-word at line-wrap boundaries, which breaks substring matching
		// on the diagnostic text below even after whitespace normalization.
		NoColor: true,
	}

	terraform.Init(t, terraformOptions)
	_, err := terraform.PlanE(t, terraformOptions)

	if err == nil {
		t.Fatal("expected terraform plan to fail due to precondition violations, but it succeeded")
	}

	// Terraform's CLI line-wraps long diagnostic messages at an
	// implementation-defined width, which can insert a newline in the
	// middle of the substrings we're checking for. Collapse all whitespace
	// before matching so the assertion doesn't depend on wrap points.
	normalizedErr := strings.Join(strings.Fields(err.Error()), " ")

	assertContains := func(substr string) {
		if !strings.Contains(normalizedErr, substr) {
			t.Errorf("expected plan error to contain %q, got: %s", substr, err.Error())
		}
	}

	assertContains("Container log collection through the Datadog Agent is not supported in daemon mode")
	assertContains("neither UDS (socket_enabled) nor TCP (tcp_enabled) transport is configured")
}
