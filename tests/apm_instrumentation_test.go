// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"encoding/json"
	"log"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// tests the task definition with automatic APM instrumentation enabled
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

// verifies that the module rejects automatic APM instrumentation
// when it can't tell which container to instrument, or can't update
// its tracer settings, before the task definition is registered.
func TestApmInstrumentationInvalid(t *testing.T) {
	terraformOptions := &terraform.Options{
		TerraformDir: "../smoke_tests/ecs_fargate_invalid",
		Vars: map[string]any{
			"dd_api_key": "test-api-key",
		},
		// Colorized output injects ANSI escape codes mid-word at line-wrap
		// boundaries, which breaks substring matching on diagnostics.
		NoColor: true,
	}
	terraform.Init(t, terraformOptions)

	// Container definitions known at plan time fail the plan
	_, err := terraform.PlanE(t, terraformOptions)
	require.Error(t, err, "expected terraform plan to fail due to precondition violations")
	assertOutputContains(t, err.Error(),
		"`dd_apm_instrumentation.container_name` is 'missing-app', but no application container has that name. Choose one of: app.",
		"The task definition has several application containers: app, worker.",
		"The container to instrument sets PYTHONPATH from `secrets`",
	)

	// Container definitions unknown until apply pass the plan, then fail the apply
	terraformOptions.Targets = []string{"module.dd_task_apm_unknown_at_plan"}
	defer terraform.Destroy(t, terraformOptions)
	terraform.Plan(t, terraformOptions)
	_, err = terraform.ApplyE(t, terraformOptions)
	require.Error(t, err, "expected terraform apply to fail due to a precondition violation")
	assertOutputContains(t, err.Error(),
		"`dd_apm_instrumentation.container_name` is 'missing-app', but no application container has that name. Choose one of: app.",
	)
}

// verifies that the plan warns and leaves the task
// uninstrumented when the module can't safely add the tracer
func TestApmInstrumentationSkipped(t *testing.T) {
	terraformOptions := &terraform.Options{
		TerraformDir: "../smoke_tests/ecs_fargate_apm_skipped",
		Vars: map[string]any{
			"dd_api_key": "test-api-key",
		},
		PlanFilePath: filepath.Join(t.TempDir(), "plan.out"),
		NoColor:      true,
	}
	output := terraform.InitAndPlan(t, terraformOptions)
	plan := terraform.ShowWithStruct(t, terraformOptions)

	expectedWarnings := map[string]string{
		"dd_task_apm_no_application_container": "Automatic APM instrumentation found no application container in `container_definitions`.",
		"dd_task_apm_duplicated_env":           "The container to instrument sets PYTHONPATH more than once in `environment`.",
		"dd_task_apm_set_if_absent_conflict":   "The container to instrument sets CORECLR_ENABLE_PROFILING to values that conflict with the tracer.",
		"dd_task_apm_env_over_max_length":      "Adding the tracer settings to LD_PRELOAD on the container to instrument exceeds the length limit.",
		"dd_task_apm_tracer_name_taken":        "The task definition already has a container or volume named 'datadog-tracer'",
		"dd_task_apm_tracer_mount_taken":       "These mount points conflict with the tracer volume: app:/datadog-lib.",
	}
	for module, warning := range expectedWarnings {
		t.Run(module, func(t *testing.T) {
			assertOutputContains(t, output, warning)

			task, found := plan.ResourcePlannedValuesMap["module."+module+".aws_ecs_task_definition.this"]
			require.True(t, found, "Task definition not found in the plan")
			tags, _ := task.AttributeValues["tags"].(map[string]any)
			assert.NotContains(t, tags, "dd_sls_injection_mode", "Unexpected injection mode tag")

			var containers []types.ContainerDefinition
			err := json.Unmarshal([]byte(task.AttributeValues["container_definitions"].(string)), &containers)
			require.NoError(t, err, "Failed to parse container definitions")
			_, found = GetContainer(containers, "datadog-tracer")
			assert.False(t, found, "datadog-tracer should not be added")
			for _, container := range containers {
				ddTags, _ := GetEnvVar(container, "DD_TAGS")
				assert.NotContains(t, ddTags, "_dd.injection.mode", "%s should not carry the injection mode tag", *container.Name)
			}
		})
	}
}

// checks that Terraform output contains each message
func assertOutputContains(t *testing.T, output string, messages ...string) {
	t.Helper()
	normalizedOutput := strings.Join(strings.Fields(output), " ")
	for _, message := range messages {
		assert.Contains(t, normalizedOutput, message)
	}
}
