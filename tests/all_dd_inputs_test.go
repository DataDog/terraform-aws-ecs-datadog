// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"encoding/json"
	"log"

	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// Test for the "all-dd-inputs" task definition
func (s *ECSFargateSuite) TestAllDDInputs() {
	log.Println("TestAllDDInputs: Running test...")

	// Retrieve the task output for the "all-dd-inputs" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "all-dd-inputs")

	s.Equal(s.testPrefix+"-all-dd-inputs", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(6, len(containers), "Expected 6 containers in the task definition")

	// Test Agent Container
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.Equal("public.ecr.aws/datadog/agent:latest", *agentContainer.Image, "Unexpected image for datadog-agent")
	s.True(*agentContainer.Essential, "datadog-agent should be essential")
	s.Equal(types.LogDriverAwsfirelens, (*agentContainer.LogConfiguration).LogDriver, "Unexpected log driver for datadog-agent")

	AssertPortMapping(s.T(), agentContainer, PortUDP)
	AssertPortMapping(s.T(), agentContainer, PortTCP)
	AssertMountPoint(s.T(), agentContainer, MountDdSocket)
	AssertContainerDependency(s.T(), agentContainer, DependencyLogRouter)

	expectedAgentEnvvars := map[string]string{
		"DD_DOGSTATSD_ORIGIN_DETECTION_CLIENT":        "true",
		"DD_INSTALL_INFO_TOOL_VERSION":                "terraform-aws-ecs-datadog",
		"DD_DOGSTATSD_ORIGIN_DETECTION":               "true",
		"DD_RUNTIME_SECURITY_CONFIG_ENABLED":          "true",
		"DD_DOGSTATSD_TAG_CARDINALITY":                "high",
		"DD_TAGS":                                     "team:cont-p, owner:container-monitoring",
		"DD_CUSTOM_FEATURE":                           "true",
		"DD_ECS_TASK_COLLECTION_ENABLED":              "true",
		"DD_API_KEY":                                  "test-api-key",
		"DD_SITE":                                     "datadoghq.com",
		"ECS_FARGATE":                                 "true",
		"DD_SERVICE":                                  "test-service",
		"DD_RUNTIME_SECURITY_CONFIG_EBPFLESS_ENABLED": "true",
		"DD_INSTALL_INFO_TOOL":                        "terraform",
		// "DD_INSTALL_INFO_INSTALLER_VERSION":        "0.0.0",
	}
	AssertEnvVars(s.T(), agentContainer, expectedAgentEnvvars)

	expectedLogOptions := map[string]string{
		"apikey":      "test-api-key",
		"provider":    "ecs",
		"dd_service":  "dd-test",
		"Host":        "http-intake.logs.datadoghq.com",
		"TLS":         "on",
		"dd_source":   "dd-test",
		"dd_tags":     "team:cont-p, owner:container-monitoring",
		"Name":        "datadog",
		"retry_limit": "2",
	}
	for key, expectedValue := range expectedLogOptions {
		value, exists := agentContainer.LogConfiguration.Options[key]
		s.True(exists, "Log option %s not found in datadog-agent", key)
		s.Equal(expectedValue, value, "Log option %s value does not match expected in datadog-agent", key)
	}

	// Test Log Router Container
	logRouterContainer, found := GetContainer(containers, "datadog-log-router")
	s.True(found, "Container datadog-log-router not found in definitions")
	s.Equal("public.ecr.aws/aws-observability/aws-for-fluent-bit:stable", *logRouterContainer.Image)
	s.False(*logRouterContainer.Essential, "datadog-log-router should not be essential")
	s.Equal("0", *logRouterContainer.User, "Unexpected user for datadog-log-router")
	s.Equal(types.FirelensConfigurationTypeFluentbit, logRouterContainer.FirelensConfiguration.Type, "Unexpected firelens type")
	s.Equal("true", logRouterContainer.FirelensConfiguration.Options["enable-ecs-log-metadata"], "Unexpected firelens option value")

	// Test CWS init container
	cwsInitContainer, found := GetContainer(containers, "cws-instrumentation-init")
	s.True(found, "Container cws-instrumentation-init not found in definitions")
	s.Equal("datadog/cws-instrumentation:latest", *cwsInitContainer.Image)
	s.False(*cwsInitContainer.Essential, "cws-instrumentation-init should not be essential")
	s.Equal("0", *cwsInitContainer.User, "Unexpected user for cws-instrumentation-init")
	s.Equal([]string{"/cws-instrumentation", "setup", "--cws-volume-mount", "/cws-instrumentation-volume"}, cwsInitContainer.Command, "Unexpected command for cws-instrumentation-init")
	AssertMountPoint(s.T(), cwsInitContainer, MountCWS)

	// Test the datadog-cws-app container
	cwsAppContainer, found := GetContainer(containers, "datadog-cws-app")
	s.True(found, "Container datadog-cws-app not found in definitions")
	AssertMountPoint(s.T(), cwsAppContainer, MountCWS)
	AssertContainerDependency(s.T(), cwsAppContainer, DependencyCWS)
	AssertContainerDependency(s.T(), cwsAppContainer, DependencyAgent)
	s.NotNil(cwsAppContainer.LinuxParameters, "LinuxParameters should not be nil for datadog-cws-app")
	s.Contains(cwsAppContainer.LinuxParameters.Capabilities.Add, "SYS_PTRACE",
		"SYS_PTRACE capability should be added for datadog-cws-app")
	expectedEntryPoint := []string{
		"/cws-instrumentation-volume/cws-instrumentation",
		"trace",
		"--",
		"/usr/bin/bash",
		"-c",
		"cp /usr/bin/bash /tmp/malware; chmod u+s /tmp/malware; apt update;apt install -y curl wget; /tmp/malware -c 'while true; do wget https://google.com; sleep 60; done'",
	}
	s.Equal(expectedEntryPoint, cwsAppContainer.EntryPoint, "CWS app entrypoint should be prefixed with the CWS tracer")

	// Test datadog-apm-app container
	apmAppContainer, found := GetContainer(containers, "datadog-apm-app")
	s.True(found, "Container datadog-apm-app not found in definitions")
	s.Equal("ghcr.io/datadog/apps-tracegen:main", *apmAppContainer.Image)
	expectedApmDsdEnvVars := map[string]string{
		"DD_SERVICE":           "test-service",
		"DD_TRACE_AGENT_URL":   "unix:///var/run/datadog/apm.socket",
		"DD_AGENT_HOST":        "127.0.0.1",
		"DD_PROFILING_ENABLED": "true",
		"DD_TRACE_INFERRED_PROXY_SERVICES_ENABLED": "true",
	}
	AssertEnvVars(s.T(), apmAppContainer, expectedApmDsdEnvVars)
	AssertMountPoint(s.T(), apmAppContainer, MountDdSocket)
	s.Nil(apmAppContainer.LinuxParameters, "LinuxParameters should be nil for datadog-apm-app")

	// Test datadog-dogstatsd-app container
	dogstatsdAppContainer, found := GetContainer(containers, "datadog-dogstatsd-app")
	s.True(found, "Container datadog-dogstatsd-app not found in definitions")
	s.Equal("ghcr.io/datadog/apps-dogstatsd:main", *dogstatsdAppContainer.Image)
	AssertEnvVars(s.T(), dogstatsdAppContainer, expectedApmDsdEnvVars)
	s.Nil(dogstatsdAppContainer.LinuxParameters, "LinuxParameters should be nil for datadog-dogstatsd-app")
}
