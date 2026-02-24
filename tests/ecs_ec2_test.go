// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"log"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/suite"
)

// ECSEC2Suite defines the test suite for ECS EC2
type ECSEC2Suite struct {
	suite.Suite
	terraformOptions *terraform.Options
	testPrefix       string
}

// TODO: Separate tests into different package for each tf module
// TestECSEC2Suite is the entry point for the test suite
func TestECSEC2Suite(t *testing.T) {
	suite.Run(t, new(ECSEC2Suite))
}

// SetupSuite is run once at the beginning of the test suite
func (s *ECSEC2Suite) SetupSuite() {
	log.Println("Setting up ECS EC2 test suite resources...")

	// All resources must be prefixed with terraform-test
	s.testPrefix = "terraform-test"
	ciJobID := os.Getenv("CI_JOB_ID")
	if ciJobID != "" {
		s.testPrefix = s.testPrefix + "-" + ciJobID
	}

	// Define the Terraform options for the suite
	s.terraformOptions = &terraform.Options{
		// Path to the smoke_tests directory
		TerraformDir: "../smoke_tests/ecs_ec2",
		// Use terraform binary instead of tofu
		TerraformBinary: "terraform",
		// Variables to pass to the Terraform module
		Vars: map[string]interface{}{
			"dd_api_key":  "test-api-key",
			"dd_site":     "datadoghq.com",
			"test_prefix": s.testPrefix,
		},
		RetryableTerraformErrors: map[string]string{
			"couldn't find resource": "terratest could not find the resource. check for access denied errors in cloudtrail",
		},
	}

	// Run terraform init and apply
	terraform.InitAndApply(s.T(), s.terraformOptions)
}

// TearDownSuite is run once at the end of the test suite
func (s *ECSEC2Suite) TearDownSuite() {
	log.Println("Tearing down ECS EC2 test suite resources...")
	terraform.Destroy(s.T(), s.terraformOptions)
}

// TestAgentOnly tests the basic agent-only deployment
func (s *ECSEC2Suite) TestAgentOnly() {
	log.Println("TestAgentOnly: Running test...")

	// Retrieve the task ARN for the "agent-only" module
	taskArn := terraform.Output(s.T(), s.terraformOptions, "agent_only_task_arn")
	s.Contains(taskArn, s.testPrefix+"-agent-only", "Task ARN should contain the correct family name")
	s.NotEmpty(taskArn, "Task ARN should not be empty")
}

// TestAllFeatures tests the all-features deployment
func (s *ECSEC2Suite) TestAllFeatures() {
	log.Println("TestAllFeatures: Running test...")

	// Retrieve the task ARN for the "all-features" module
	taskArn := terraform.Output(s.T(), s.terraformOptions, "all_features_task_arn")
	s.Contains(taskArn, s.testPrefix+"-all-features", "Task ARN should contain the correct family name")
}

// TestBridgeNetworking tests bridge networking mode
func (s *ECSEC2Suite) TestBridgeNetworking() {
	log.Println("TestBridgeNetworking: Running test...")

	// Verify bridge network mode is set correctly
	networkMode := terraform.Output(s.T(), s.terraformOptions, "bridge_mode_network_mode")
	s.Equal("bridge", networkMode, "Network mode should be bridge")

	taskArn := terraform.Output(s.T(), s.terraformOptions, "bridge_mode_task_arn")
	s.Contains(taskArn, s.testPrefix+"-bridge-mode", "Task ARN should contain the correct family name")
}

// TestHostNetworking tests host networking mode
func (s *ECSEC2Suite) TestHostNetworking() {
	log.Println("TestHostNetworking: Running test...")

	// Verify host network mode is set correctly
	networkMode := terraform.Output(s.T(), s.terraformOptions, "host_mode_network_mode")
	s.Equal("host", networkMode, "Network mode should be host")

	taskArn := terraform.Output(s.T(), s.terraformOptions, "host_mode_task_arn")
	s.Contains(taskArn, s.testPrefix+"-host-mode", "Task ARN should contain the correct family name")
}
