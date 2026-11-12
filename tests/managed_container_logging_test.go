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

// TestManagedContainerLogging verifies that every container the module creates
// carries a log configuration when `dd_log_configuration` is set. With log
// collection disabled and a read-only root filesystem, the Agent and the
// `init-volume` container would otherwise be registered with no log driver,
// which fails AWS FSBP control ECS.9.
func (s *ECSFargateSuite) TestManagedContainerLogging() {
	log.Println("TestManagedContainerLogging: Running test...")

	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "managed-container-logging")
	s.Equal(s.testPrefix+"-managed-container-logging", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(3, len(containers), "Expected app, datadog-agent and init-volume containers")

	expectedOptions := map[string]string{
		"awslogs-group":         "/ecs/" + s.testPrefix + "-managed-container-logging",
		"awslogs-region":        "us-east-1",
		"awslogs-stream-prefix": "datadog",
	}

	// Every container the module owns must have a log driver — this is the
	// condition ECS.9 evaluates.
	for _, name := range []string{"datadog-agent", "init-volume"} {
		container, found := GetContainer(containers, name)
		s.True(found, "Container %s not found in definitions", name)
		s.NotNil(container.LogConfiguration, "%s log configuration should be defined", name)
		s.Equal(types.LogDriverAwslogs, container.LogConfiguration.LogDriver, "%s should use the awslogs log driver", name)

		for k, v := range expectedOptions {
			actual, exists := container.LogConfiguration.Options[k]
			s.True(exists, "%s log option %s should be set", name, k)
			s.Equal(v, actual, "Unexpected value for %s log option %s", name, k)
		}
	}

	// The caller's own container keeps the log configuration it was given.
	appContainer, found := GetContainer(containers, "app")
	s.True(found, "Container app not found in definitions")
	s.NotNil(appContainer.LogConfiguration, "app log configuration should be defined")
	s.Equal("app", appContainer.LogConfiguration.Options["awslogs-stream-prefix"], "app log configuration should not be overridden")
}
