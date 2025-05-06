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

// TestAllWindows tests the task definition for Windows with APM and DogStatsD enabled
func (s *ECSFargateSuite) TestAllWindows() {
	log.Println("TestAllWindows: Running test...")

	// Retrieve the task output for the "all-windows" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "all-windows")
	s.Equal("terraform-test-all-windows", task["family"], "Unexpected task family name")
	s.Equal(string(types.NetworkModeAwsvpc), task["network_mode"], "Unexpected network mode")
	s.Equal(string(types.PidModeTask), task["pid_mode"], "Unexpected PID mode")

	// Verify runtime platform specifics for Windows
	var taskDefinition types.TaskDefinition
	err := json.Unmarshal([]byte(task["task_definition"]), &taskDefinition)
	s.NoError(err, "Failed to parse task definition")
	s.NotNil(taskDefinition.RuntimePlatform, "RuntimePlatform should be defined")
	s.Equal(types.CPUArchitectureArm64, taskDefinition.RuntimePlatform.CpuArchitecture, "Unexpected CPU architecture")
	s.Equal(types.OSFamilyWindowsServer2022Core, taskDefinition.RuntimePlatform.OperatingSystemFamily, "Unexpected OS family")
	s.Equal("1024", task["cpu"], "Unexpected CPU value")
	s.Equal("2048", task["memory"], "Unexpected memory value")

	err = json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(3, len(containers), "Expected 3 containers in the task definition")

	// Test Agent Container
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.Equal("public.ecr.aws/datadog/agent:latest", *agentContainer.Image, "Unexpected image for datadog-agent")
	s.False(*agentContainer.Essential, "datadog-agent should not be essential for Windows tasks")

	// Verify port mappings
	AssertPortMapping(s.T(), agentContainer, PortUDP)
	AssertPortMapping(s.T(), agentContainer, PortTCP)

	// Verify agent environment variables
	expectedAgentEnvVars := map[string]string{
		"DD_API_KEY":                           "test-api-key",
		"DD_SITE":                              "datadoghq.com",
		"DD_SERVICE":                           "test-service",
		"DD_DOGSTATSD_TAG_CARDINALITY":         "orchestrator",
		"DD_ECS_TASK_COLLECTION_ENABLED":       "true",
		"ECS_FARGATE":                          "true",
		"DD_INSTALL_INFO_TOOL":                 "terraform",
		"DD_INSTALL_INFO_TOOL_VERSION":         "terraform-aws-ecs-datadog",
		"DD_DOGSTATSD_ORIGIN_DETECTION":        "true",
		"DD_DOGSTATSD_ORIGIN_DETECTION_CLIENT": "true",
	}
	AssertEnvVars(s.T(), agentContainer, expectedAgentEnvVars)

	// Verify no mount points (Windows doesn't support sockets)
	s.Equal(0, len(agentContainer.MountPoints), "Expected no mount points for datadog-agent in Windows")

	// Test DogStatsD App Container
	dogstatsdContainer, found := GetContainer(containers, "datadog-dogstatsd-app")
	s.True(found, "Container datadog-dogstatsd-app not found in definitions")
	s.Equal("ghcr.io/datadog/apps-dogstatsd:main", *dogstatsdContainer.Image, "Unexpected image for dogstatsd app")
	s.False(*dogstatsdContainer.Essential, "dogstatsd-app should not be essential")

	// Verify DogStatsD app environment variables
	expectedDogstatsdEnvVars := map[string]string{
		"DD_SERVICE":    "test-service",
		"DD_AGENT_HOST": "127.0.0.1",
	}
	AssertEnvVars(s.T(), dogstatsdContainer, expectedDogstatsdEnvVars)

	// Verify DogStatsD app doesn't have socket-related env vars
	apmDsdDisabledEnvVars := []string{
		"DD_DOGSTATSD_SOCKET",
		"DD_DOGSTATSD_URL",
		"DD_TRACE_AGENT_URL",
	}
	AssertNotEnvVars(s.T(), dogstatsdContainer, apmDsdDisabledEnvVars)

	// Test APM App Container
	apmContainer, found := GetContainer(containers, "datadog-apm-app")
	s.True(found, "Container datadog-apm-app not found in definitions")
	s.Equal("ghcr.io/datadog/apps-tracegen:main", *apmContainer.Image, "Unexpected image for apm app")
	s.True(*apmContainer.Essential, "apm-app should be essential")

	// Verify APM app environment variables
	expectedApmEnvVars := map[string]string{
		"DD_SERVICE":    "test-service",
		"DD_AGENT_HOST": "127.0.0.1",
	}
	AssertEnvVars(s.T(), apmContainer, expectedApmEnvVars)

	// Verify APM app doesn't have socket-related env vars
	AssertNotEnvVars(s.T(), apmContainer, apmDsdDisabledEnvVars)

	// Verify no mount points for application containers
	s.Equal(0, len(dogstatsdContainer.MountPoints), "Expected no mount points for dogstatsd-app in Windows")
	s.Equal(0, len(apmContainer.MountPoints), "Expected no mount points for apm-app in Windows")

	// Verify no volumes at task definition level
	s.Equal(0, len(task["volumes"]), "Expected no volumes in Windows tasks")

	// Verify no Windows-unsupported containers are present
	_, found = GetContainer(containers, "datadog-log-router")
	s.False(found, "Container datadog-log-router should not be present in Windows tasks")

	_, found = GetContainer(containers, "cws-instrumentation-init")
	s.False(found, "Container cws-instrumentation-init should not be present in Windows tasks")
}
