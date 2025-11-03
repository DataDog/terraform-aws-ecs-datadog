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

// TestLoggingOnly tests the task definition with only logging functionality enabled
func (s *ECSFargateSuite) TestLoggingOnly() {
	log.Println("TestLoggingOnly: Running test...")

	// Retrieve the task output for the "logging-only" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "logging-only")
	s.Equal(s.testPrefix+"-logging-only", task["family"], "Unexpected task family name")
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

	// Verify port mappings
	AssertPortMapping(s.T(), agentContainer, PortUDP)
	AssertPortMapping(s.T(), agentContainer, PortTCP)

	// Verify agent environment variables
	expectedAgentEnvVars := map[string]string{
		"DD_API_KEY":                     "test-api-key",
		"DD_SITE":                        "datadoghq.com",
		"DD_DOGSTATSD_TAG_CARDINALITY":   "orchestrator",
		"DD_ECS_TASK_COLLECTION_ENABLED": "true",
		"ECS_FARGATE":                    "true",
		"DD_INSTALL_INFO_TOOL":           "terraform",
		"DD_INSTALL_INFO_TOOL_VERSION":   "terraform-aws-ecs-datadog",
	}
	AssertEnvVars(s.T(), agentContainer, expectedAgentEnvVars)

	// Verify agent log configuration
	s.NotNil(agentContainer.LogConfiguration, "Agent log configuration should be defined")
	s.Equal(types.LogDriverAwsfirelens, agentContainer.LogConfiguration.LogDriver, "Agent should use awsfirelens log driver")

	expectedLogOptions := map[string]string{
		"Host":        "http-intake.logs.datadoghq.com",
		"apikey":      "test-api-key",
		"provider":    "ecs",
		"Name":        "datadog",
		"retry_limit": "2",
	}

	for k, v := range expectedLogOptions {
		actualValue, exists := agentContainer.LogConfiguration.Options[k]
		s.True(exists, "Log configuration option %s should exist", k)
		s.Equal(v, actualValue, "Log configuration option %s should have value %s", k, v)
	}

	// Verify agent has dependency on log router
	s.Equal(1, len(agentContainer.DependsOn), "Agent should depend on log router")
	s.Equal("datadog-log-router", *agentContainer.DependsOn[0].ContainerName, "Agent should depend on datadog-log-router")
	s.Equal(types.ContainerConditionHealthy, agentContainer.DependsOn[0].Condition, "Agent should depend on log router being healthy")

	// Verify no mount points
	s.Equal(0, len(agentContainer.MountPoints), "Expected no mount points for datadog-agent")

	// Test Log Router Container
	logRouterContainer, found := GetContainer(containers, "datadog-log-router")
	s.True(found, "Container datadog-log-router not found in definitions")
	s.Equal("public.ecr.aws/aws-observability/aws-for-fluent-bit:stable", *logRouterContainer.Image,
		"Unexpected image for log router")
	s.False(*logRouterContainer.Essential, "Log router should not be essential")
	s.Equal("0", *logRouterContainer.User, "Log router should run as root user")

	// Verify log router environment variables
	expectedLogRouterEnvVars := map[string]string{
		"DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL": "true",
	}
	AssertEnvVars(s.T(), logRouterContainer, expectedLogRouterEnvVars)

	// Verify log router health check
	s.NotNil(logRouterContainer.HealthCheck, "Log router health check should be defined")
	s.Contains(logRouterContainer.HealthCheck.Command, "exit 0", "Log router health check command should be 'exit 0'")
	s.Equal(int32(5), *logRouterContainer.HealthCheck.Interval, "Log router health check interval should be 5")
	s.Equal(int32(5), *logRouterContainer.HealthCheck.Timeout, "Log router health check timeout should be 5")
	s.Equal(int32(3), *logRouterContainer.HealthCheck.Retries, "Log router health check retries should be 3")
	s.Equal(int32(15), *logRouterContainer.HealthCheck.StartPeriod, "Log router health check start period should be 15")

	// Verify log router FireLens configuration
	s.NotNil(logRouterContainer.FirelensConfiguration, "Log router FireLens configuration should be defined")
	s.Equal(types.FirelensConfigurationTypeFluentbit, logRouterContainer.FirelensConfiguration.Type, "Log router FireLens type should be fluentbit")
	s.Equal("true", logRouterContainer.FirelensConfiguration.Options["enable-ecs-log-metadata"],
		"Log router FireLens should have ECS log metadata enabled")
	s.Equal("file", logRouterContainer.FirelensConfiguration.Options["config-file-type"],
		"Log router FireLens should have config_file_type")
	s.Equal("file:///fluent-bit/etc/fluent-bit.conf", logRouterContainer.FirelensConfiguration.Options["config-file-value"],
		"Log router FireLens should have config_file_value")

	// Verify no optional containers are present
	_, found = GetContainer(containers, "cws-instrumentation-init")
	s.False(found, "Container cws-instrumentation-init should not be present when CWS is disabled")

	// Verify no volumes at task definition level
	s.Equal(0, len(task["volumes"]), "Expected no volumes")
}
