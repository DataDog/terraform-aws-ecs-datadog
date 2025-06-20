// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"log"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/suite"
)

// ECSFargateSuite defines the test suite for ECS Fargate
type ECSFargateSuite struct {
	suite.Suite
	terraformOptions *terraform.Options
}

// TestECSFargateSuite is the entry point for the test suite
func TestECSFargateSuite(t *testing.T) {
	suite.Run(t, new(ECSFargateSuite))
}

// SetupSuite is run once at the beginning of the test suite
func (s *ECSFargateSuite) SetupSuite() {
	log.Println("Setting up test suite resources...")

	// All resources must be prefixed with terraform-test
	testPrefix := "terraform-test"
	ciJobID := os.Getenv("CI_JOB_ID")
	if ciJobID != "" {
		testPrefix = testPrefix + "-" + ciJobID
	}

	// Define the Terraform options for the suite
	s.terraformOptions = &terraform.Options{
		// Path to the smoke_tests directory
		TerraformDir: "../smoke_tests/ecs_fargate",
		// Variables to pass to the Terraform module
		Vars: map[string]interface{}{
			"dd_api_key":  "test-api-key",
			"dd_service":  "test-service",
			"dd_site":     "datadoghq.com",
			"test_prefix": testPrefix,
		},
		RetryableTerraformErrors: map[string]string{
			"couldn't find resource": "ECS eventually consistent or task definition not yet propagated",
		},
		NoColor:            true,
		MaxRetries:         2,
		TimeBetweenRetries: 10 * time.Second,
		Lock:               true,
	}

	// Run terraform init and apply
	terraform.InitAndApply(s.T(), s.terraformOptions)
}

// TearDownSuite is run once at the end of the test suite
func (s *ECSFargateSuite) TearDownSuite() {
	log.Println("Tearing down test suite resources...")
	terraform.Destroy(s.T(), s.terraformOptions)
}
