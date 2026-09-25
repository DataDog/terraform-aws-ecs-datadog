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

// TestApmInstrumentation tests the task definition with automatic APM instrumentation enabled
func (s *ECSFargateSuite) TestApmInstrumentation() {
	log.Println("TestApmInstrumentation: Running test...")

	// Retrieve the task output for the "apm-instrumentation" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "apm-instrumentation")
	s.Equal(s.testPrefix+"-apm-instrumentation", task["family"], "Unexpected task family name")
	s.Contains(task["volume"], "datadog-tracer", "Expected the datadog-tracer volume")
	s.Contains(task["tags"], "dd_sls_injection_mode:single_language", "Expected the injection mode tag")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")
	s.Equal(4, len(containers), "Expected 4 containers in the task definition")

	// Test tracer container
	tracerContainer, found := GetContainer(containers, "datadog-tracer")
	s.True(found, "Container datadog-tracer not found in definitions")
	s.Equal("public.ecr.aws/datadog/dd-lib-python-init:latest", *tracerContainer.Image, "Unexpected image for datadog-tracer")
	s.False(*tracerContainer.Essential, "datadog-tracer should not be essential")
	s.Equal("0", *tracerContainer.User, "Unexpected user for datadog-tracer")
	s.Equal([]string{"/datadog-init/copy-lib.sh"}, tracerContainer.EntryPoint, "Unexpected entrypoint for datadog-tracer")
	s.Equal([]string{"/datadog-lib"}, tracerContainer.Command, "Unexpected command for datadog-tracer")
	AssertMountPoint(s.T(), tracerContainer, MountTracer)

	// Test the instrumented datadog-apm-app container
	apmAppContainer, found := GetContainer(containers, "datadog-apm-app")
	s.True(found, "Container datadog-apm-app not found in definitions")
	expectedApmEnvVars := map[string]string{
		"PYTHONPATH": "/app:/datadog-lib",
		"DD_TAGS":    "_dd.injection.mode:serverless-single-lang,team:serverless",
		"DD_SERVICE": "test-service",
	}
	AssertEnvVars(s.T(), apmAppContainer, expectedApmEnvVars)
	AssertMountPoint(s.T(), apmAppContainer, MountTracer)
	AssertContainerDependency(s.T(), apmAppContainer, DependencyTracer)

	// Test that the datadog-dogstatsd-app container is not instrumented
	dogstatsdAppContainer, found := GetContainer(containers, "datadog-dogstatsd-app")
	s.True(found, "Container datadog-dogstatsd-app not found in definitions")
	AssertNotEnvVars(s.T(), dogstatsdAppContainer, []string{"PYTHONPATH", "DD_TAGS"})
	for _, mountPoint := range dogstatsdAppContainer.MountPoints {
		s.NotEqual("datadog-tracer", *mountPoint.SourceVolume, "datadog-dogstatsd-app should not mount the tracer volume")
	}
	for _, dependency := range dogstatsdAppContainer.DependsOn {
		s.NotEqual("datadog-tracer", *dependency.ContainerName, "datadog-dogstatsd-app should not depend on datadog-tracer")
	}
}
