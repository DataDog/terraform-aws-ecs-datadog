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

	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "role-parsing-with-path")

	s.Equal(s.testPrefix+"-role-parsing-with-path", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")

	s.NotEmpty(task["arn"], "Task definition ARN should not be empty")
	s.NotEmpty(task["revision"], "Task definition revision should not be empty")

	taskRoleArn := task["task_role_arn"]
	s.NotEmpty(taskRoleArn, "Task role ARN should not be empty")
	s.Contains(taskRoleArn, "/test-task-path/", "Task role ARN should contain the path '/test-path/'")
	s.Contains(taskRoleArn, s.testPrefix+"-task-role-with-path", "Task role ARN should contain the expected role name")

	executionRoleArn := task["execution_role_arn"]
	s.NotEmpty(executionRoleArn, "Execution role ARN should not be empty")
	s.Contains(executionRoleArn, "/test-execution-path/", "Execution role ARN should contain the path '/test-execution-path/'")
	s.Contains(executionRoleArn, s.testPrefix+"-execution-role-with-path", "Execution role ARN should contain the expected role name")
}

// TestRoleParsingWithoutPath tests that the module correctly parses role names from ARNs without paths
func (s *ECSFargateSuite) TestRoleParsingWithoutPath() {
	log.Println("TestRoleParsingWithoutPath: Running test...")

	var containers []types.ContainerDefinition
	task := terraform.OutputMap(s.T(), s.terraformOptions, "role-parsing-without-path")

	s.Equal(s.testPrefix+"-role-parsing-without-path", task["family"], "Unexpected task family name")

	err := json.Unmarshal([]byte(task["container_definitions"]), &containers)
	s.NoError(err, "Failed to parse container definitions")

	s.NotEmpty(task["arn"], "Task definition ARN should not be empty")
	s.NotEmpty(task["revision"], "Task definition revision should not be empty")

	taskRoleArn := task["task_role_arn"]
	s.NotEmpty(taskRoleArn, "Task role ARN should not be empty")
	s.Contains(taskRoleArn, s.testPrefix+"-task-role-without-path", "Task role ARN should contain the expected role name")

	roleArnParts := strings.Split(taskRoleArn, "/")
	s.Equal(2, len(roleArnParts), "Role ARN without path should have exactly 2 parts when split by '/'")
	s.Contains(roleArnParts[1], s.testPrefix+"-task-role-without-path", "Role name should be the second part after splitting by '/'")

	executionRoleArn := task["execution_role_arn"]
	s.NotEmpty(executionRoleArn, "Execution role ARN should not be empty")
	s.Contains(executionRoleArn, s.testPrefix+"-execution-role-without-path", "Execution role ARN should contain the expected role name")

	execRoleArnParts := strings.Split(executionRoleArn, "/")
	s.Equal(2, len(execRoleArnParts), "Execution role ARN without path should have exactly 2 parts when split by '/'")
	s.Contains(execRoleArnParts[1], s.testPrefix+"-execution-role-without-path", "Execution role name should be the second part after splitting by '/'")
}
