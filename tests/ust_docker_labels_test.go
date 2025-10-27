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

// TestUSTDockerLabels tests that UST docker labels are propagated to all container definitions
// when dd_service, dd_env, and dd_version are set
func (s *ECSFargateSuite) TestUSTDockerLabels() {
	log.Println("TestUSTDockerLabels: Running test...")

	// Retrieve the task output for the "ust-docker-labels" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "ust-docker-labels")
	s.Equal(s.testPrefix+"-ust-docker-labels", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(5, len(containers), "Expected 4 containers in the task definition (3 app containers + 1 agent)")

	// Expected UST docker labels that should be present on all application containers
	expectedUSTLabels := map[string]string{
		"com.datadoghq.tags.service": "ust-test-service",
		"com.datadoghq.tags.env":     "ust-test-env",
		"com.datadoghq.tags.version": "1.2.3",
	}

	dummyApp, found := GetContainer(containers, "dummy-app")
	s.True(found, "Container dummy-app not found in definitions")
	AssertDockerLabels(s.T(), dummyApp, expectedUSTLabels)

	datadogContainers := []string{"datadog-agent", "datadog-log-router", "cws-instrumentation-init"}
	for _, containerName := range datadogContainers {
		container, found := GetContainer(containers, containerName)
		s.True(found, "Container %s not found in definitions", containerName)
		AssertDockerLabels(s.T(), container, expectedUSTLabels)
	}

	overwrittenLabels, found := GetContainer(containers, "app-overwritten-ust")
	s.True(found, "Container app-overwritten-ust not found in definitions")
	expectedUSTLabels["com.datadoghq.tags.service"] = "different_name"
	AssertDockerLabels(s.T(), overwrittenLabels, expectedUSTLabels)

}
