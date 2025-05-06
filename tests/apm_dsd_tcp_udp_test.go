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

// TestApmDsdTcpUdp tests the task definition with APM and DogStatsD enabled via TCP and UDP (no socket)
func (s *ECSFargateSuite) TestApmDsdTcpUdp() {
	log.Println("TestApmDsdTcpUdp: Running test...")

	// Retrieve the task output for the "apm-dsd-tcp-udp" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "apm-dsd-tcp-udp")
	s.Equal("terraform-test-apm-dsd-tcp-udp", task["family"], "Unexpected task family name")
	s.Equal(string(types.NetworkModeAwsvpc), task["network_mode"], "Unexpected network mode")
	s.Equal(string(types.PidModeTask), task["pid_mode"], "Unexpected PID mode")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(3, len(containers), "Expected 3 containers in the task definition")

	// Test Agent Container
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.Equal("public.ecr.aws/datadog/agent:latest", *agentContainer.Image, "Unexpected image for datadog-agent")
	s.True(*agentContainer.Essential, "datadog-agent should be essential")

	// Verify port mappings for TCP and UDP communication
	AssertPortMapping(s.T(), agentContainer, PortUDP)
	AssertPortMapping(s.T(), agentContainer, PortTCP)

	// Verify agent environment variables
	expectedAgentEnvVars := map[string]string{
		"DD_API_KEY":                           "test-api-key",
		"DD_SITE":                              "datadoghq.com",
		"DD_SERVICE":                           "test-service",
		"DD_TAGS":                              "team:cont-p, owner:container-monitoring",
		"DD_DOGSTATSD_TAG_CARDINALITY":         "orchestrator",
		"DD_ECS_TASK_COLLECTION_ENABLED":       "true",
		"ECS_FARGATE":                          "true",
		"DD_INSTALL_INFO_TOOL":                 "terraform",
		"DD_INSTALL_INFO_TOOL_VERSION":         "terraform-aws-ecs-datadog",
		"DD_DOGSTATSD_ORIGIN_DETECTION":        "true",
		"DD_DOGSTATSD_ORIGIN_DETECTION_CLIENT": "true",
	}
	AssertEnvVars(s.T(), agentContainer, expectedAgentEnvVars)

	// Verify agent doesn't have socket-related env vars
	disabledSocketEnvVars := []string{
		"DD_DOGSTATSD_SOCKET",
		"DD_APM_RECEIVER_SOCKET",
	}
	AssertNotEnvVars(s.T(), agentContainer, disabledSocketEnvVars)

	// Verify no mount points (as sockets are not used)
	s.Equal(0, len(agentContainer.MountPoints), "Expected no mount points for datadog-agent when socket is disabled")

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
	dsdapmDisabledEnvVars := []string{
		"DD_DOGSTATSD_SOCKET",
		"DD_DOGSTATSD_URL",
		"DD_TRACE_AGENT_URL",
	}
	AssertNotEnvVars(s.T(), dogstatsdContainer, dsdapmDisabledEnvVars)

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
	AssertNotEnvVars(s.T(), apmContainer, dsdapmDisabledEnvVars)

	// Verify no mount points for application containers
	s.Equal(0, len(dogstatsdContainer.MountPoints), "Expected no mount points for dogstatsd-app when socket is disabled")
	s.Equal(0, len(apmContainer.MountPoints), "Expected no mount points for apm-app when socket is disabled")

	// Verify no volumes at task definition level
	s.Equal(0, len(task["volumes"]), "Expected no volumes when sockets are disabled")

	// Verify no optional containers are present
	_, found = GetContainer(containers, "datadog-log-router")
	s.False(found, "Container datadog-log-router should not be present when log collection is disabled")

	_, found = GetContainer(containers, "cws-instrumentation-init")
	s.False(found, "Container cws-instrumentation-init should not be present when CWS is disabled")
}
