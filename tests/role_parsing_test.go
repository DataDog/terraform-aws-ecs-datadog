// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"encoding/json"
	"log"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestRoleParsingWithPath tests that the module correctly parses role names from ARNs with paths
func (s *ECSFargateSuite) TestRoleParsingWithPath() {
	log.Println("TestRoleParsingWithPath: Running test...")

	// Retrieve the task output for the "role-parsing-with-path" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "role-parsing-with-path")

	s.Equal(s.testPrefix+"-role-parsing-with-path", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")

	// Verify that the task was created successfully (which means role parsing worked)
	s.NotEmpty(task["arn"], "Task definition ARN should not be empty")
	s.NotEmpty(task["revision"], "Task definition revision should not be empty")

	// Verify the task role ARN contains the expected path
	taskRoleArn := task["task_role_arn"]
	s.NotEmpty(taskRoleArn, "Task role ARN should not be empty")
	s.Contains(taskRoleArn, "/test-path/", "Task role ARN should contain the path '/test-path/'")
	s.Contains(taskRoleArn, s.testPrefix+"-task-role-with-path", "Task role ARN should contain the expected role name")

	// Verify the execution role ARN contains the expected path
	executionRoleArn := task["execution_role_arn"]
	s.NotEmpty(executionRoleArn, "Execution role ARN should not be empty")
	s.Contains(executionRoleArn, "/test-execution-path/", "Execution role ARN should contain the path '/test-execution-path/'")
	s.Contains(executionRoleArn, s.testPrefix+"-execution-role-with-path", "Execution role ARN should contain the expected role name")

	// Test Agent Container exists and is configured
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.NotNil(agentContainer.Image, "Agent container image should not be nil")

	// Test application container exists
	appContainer, found := GetContainer(containers, "test-app")
	s.True(found, "Container test-app not found in definitions")
	s.Equal("nginx:latest", *appContainer.Image, "Unexpected image for test-app")

	log.Println("TestRoleParsingWithPath: Role parsing with path test completed successfully")
}

// TestRoleParsingWithoutPath tests that the module correctly parses role names from ARNs without paths
func (s *ECSFargateSuite) TestRoleParsingWithoutPath() {
	log.Println("TestRoleParsingWithoutPath: Running test...")

	// Retrieve the task output for the "role-parsing-without-path" module
	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "role-parsing-without-path")

	s.Equal(s.testPrefix+"-role-parsing-without-path", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")

	// Verify that the task was created successfully (which means role parsing worked)
	s.NotEmpty(task["arn"], "Task definition ARN should not be empty")
	s.NotEmpty(task["revision"], "Task definition revision should not be empty")

	// Verify the task role ARN does NOT contain additional paths (should be at root)
	taskRoleArn := task["task_role_arn"]
	s.NotEmpty(taskRoleArn, "Task role ARN should not be empty")
	s.Contains(taskRoleArn, s.testPrefix+"-task-role-without-path", "Task role ARN should contain the expected role name")

	// For roles without explicit paths, AWS defaults to "/" so the ARN format should be:
	// arn:aws:iam::account:role/role-name (not arn:aws:iam::account:role/path/role-name)
	roleArnParts := strings.Split(taskRoleArn, "/")
	s.Equal(2, len(roleArnParts), "Role ARN without path should have exactly 2 parts when split by '/'")
	s.Contains(roleArnParts[1], s.testPrefix+"-task-role-without-path", "Role name should be the second part after splitting by '/'")

	// Verify the execution role ARN does NOT contain additional paths
	executionRoleArn := task["execution_role_arn"]
	s.NotEmpty(executionRoleArn, "Execution role ARN should not be empty")
	s.Contains(executionRoleArn, s.testPrefix+"-execution-role-without-path", "Execution role ARN should contain the expected role name")

	execRoleArnParts := strings.Split(executionRoleArn, "/")
	s.Equal(2, len(execRoleArnParts), "Execution role ARN without path should have exactly 2 parts when split by '/'")
	s.Contains(execRoleArnParts[1], s.testPrefix+"-execution-role-without-path", "Execution role name should be the second part after splitting by '/'")

	// Test that containers are properly configured
	s.GreaterOrEqual(len(containers), 2, "Expected at least 2 containers (datadog-agent + test-app)")

	// Test Agent Container exists and is configured
	agentContainer, found := GetContainer(containers, "datadog-agent")
	s.True(found, "Container datadog-agent not found in definitions")
	s.NotNil(agentContainer.Image, "Agent container image should not be nil")

	// Test application container exists
	appContainer, found := GetContainer(containers, "test-app")
	s.True(found, "Container test-app not found in definitions")
	s.Equal("nginx:latest", *appContainer.Image, "Unexpected image for test-app")

	log.Println("TestRoleParsingWithoutPath: Role parsing without path test completed successfully")
}
