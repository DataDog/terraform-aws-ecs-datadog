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

// TestAllDDDisabled tests the task definition with all Datadog features disabled
func (s *ECSFargateSuite) TestAllDDDisabled() {
	log.Println("TestAllDDDisabled: Running test...")

	// Retrieve the task output for the "all-dd-disabled" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "all-dd-disabled")
	s.Equal(s.testPrefix+"-all-dd-disabled", task["family"], "Unexpected task family name")
	s.Equal(string(types.NetworkModeAwsvpc), task["network_mode"], "Unexpected network mode")
	s.Equal(string(types.PidModeTask), task["pid_mode"], "Unexpected PID mode")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(2, len(containers), "Expected 2 containers in the task definition")

	// Test Agent Container
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.Equal("public.ecr.aws/datadog/agent:latest", *agentContainer.Image, "Unexpected image for datadog-agent")
	s.True(*agentContainer.Essential, "datadog-agent should be essential")

	// Verify port mappings (these should still be present even with features disabled)
	AssertPortMapping(s.T(), agentContainer, PortUDP)
	AssertPortMapping(s.T(), agentContainer, PortTCP)

	// Verify agent environment variables
	expectedAgentEnvVars := map[string]string{
		"DD_API_KEY":                     "test-api-key",
		"DD_SITE":                        "datadoghq.com",
		"DD_TAGS":                        "team:cont-p, owner:container-monitoring",
		"DD_DOGSTATSD_TAG_CARDINALITY":   "orchestrator",
		"DD_ECS_TASK_COLLECTION_ENABLED": "true",
		"ECS_FARGATE":                    "true",
		"DD_INSTALL_INFO_TOOL":           "terraform",
		"DD_INSTALL_INFO_TOOL_VERSION":   "terraform-aws-ecs-datadog",
	}
	AssertEnvVars(s.T(), agentContainer, expectedAgentEnvVars)

	// Verify agent health check
	s.NotNil(agentContainer.HealthCheck, "Agent health check should be defined")
	s.Contains(agentContainer.HealthCheck.Command, "/probe.sh", "Agent health check command should include probe.sh")
	s.Equal(int32(15), *agentContainer.HealthCheck.Interval, "Agent health check interval should be 15")
	s.Equal(int32(5), *agentContainer.HealthCheck.Timeout, "Agent health check timeout should be 5")
	s.Equal(int32(3), *agentContainer.HealthCheck.Retries, "Agent health check retries should be 3")
	s.Equal(int32(60), *agentContainer.HealthCheck.StartPeriod, "Agent health check start period should be 60")

	// Verify no mount points (apm/dsd volumes should not be present)
	s.Equal(0, len(agentContainer.MountPoints), "Expected no mount points for datadog-agent when features are disabled")

	// Test dummy container
	dummyContainer, found := GetContainer(containers, "dummy-container")
	s.True(found, "Container dummy-container not found in definitions")
	s.Equal("ubuntu:latest", *dummyContainer.Image, "Unexpected image for dummy-container")
	s.True(*dummyContainer.Essential, "dummy-container should be essential")
	s.Equal([]string{"sleep", "infinity"}, dummyContainer.Command, "Unexpected command for dummy-container")

	// Verify dummy container environment variables
	expectedDummyEnvVars := map[string]string{
		"DD_SERVICE": "test-service",
	}
	AssertEnvVars(s.T(), dummyContainer, expectedDummyEnvVars)

	unexpectedDummyEnvVars := []string{
		"DD_API_KEY",
		"DD_SITE",
		"DD_TAGS",
		"DD_DOGSTATSD_TAG_CARDINALITY",
		"DD_TRACE_AGENT_URL",
		"DD_DOGSTATSD_URL",
		"DD_AGENT_HOST",
	}
	AssertNotEnvVars(s.T(), dummyContainer, unexpectedDummyEnvVars)

	// Verify no optional containers are present
	_, found = GetContainer(containers, "datadog-log-router")
	s.False(found, "Container datadog-log-router should not be present when log collection is disabled")

	_, found = GetContainer(containers, "cws-instrumentation-init")
	s.False(found, "Container cws-instrumentation-init should not be present when CWS is disabled")
}
