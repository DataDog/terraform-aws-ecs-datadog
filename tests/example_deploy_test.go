// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestFargateExampleDeploys validates that the customer-facing Fargate example
// (examples/ecs_fargate) deploys cleanly against real AWS using the module in
// this working tree.
//
// The published example points its module `source` at the Terraform registry,
// so the existing tests (which exercise fixtures under smoke_tests) never prove
// that the example customers actually copy stays compatible with local module
// changes. This test closes that gap: it copies the real example, swaps the
// registry source for the local module, and applies it.
//
// A successful `terraform apply` means AWS accepted and registered the task
// definition the example produces (registration is server-side validation); the
// module's `arn` output confirms it. The task is never launched — verifying a
// running agent is a deliberately separate, higher-cost e2e (see follow-up
// ticket) so this check stays fast and non-flaky.
func TestFargateExampleDeploys(t *testing.T) {
	log.Println("TestFargateExampleDeploys: Running test...")

	// Point the example at the module in this working tree instead of the
	// published registry version, so we exercise local changes.
	localModule, err := filepath.Abs("../modules/ecs_fargate")
	require.NoError(t, err)

	// Copy the real example to a temp dir so we can drop in a source override
	// without dirtying the tree.
	exampleDir := filepath.Join(t.TempDir(), "ecs_fargate")
	require.NoError(t, copyDir("../examples/ecs_fargate", exampleDir))
	override := fmt.Sprintf("module \"datadog_ecs_fargate_task\" {\n  source = %q\n}\n", localModule)
	require.NoError(t, os.WriteFile(filepath.Join(exampleDir, "zz_local_source_override.tf"), []byte(override), 0o644))

	// Match the resource-prefixing convention used by the other suites so
	// concurrent CI jobs don't collide.
	prefix := "terraform-test"
	if jobID := os.Getenv("CI_JOB_ID"); jobID != "" {
		prefix += "-" + jobID
	}

	opts := &terraform.Options{
		TerraformDir:    exampleDir,
		TerraformBinary: "terraform",
		Vars: map[string]interface{}{
			// Literal key (never a real secret), same as the other tests: the
			// module renders it as an env var, so no Secrets Manager access is
			// required to register the task definition.
			"dd_api_key":       "test-api-key",
			"dd_site":          "datadoghq.com",
			"dd_service":       prefix + "-example",
			"dd_env":           "test",
			"dd_version":       "1.0.0",
			"task_family_name": prefix + "-example",
		},
	}
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// apply succeeding already means AWS registered the task definition; confirm
	// the module returned a well-formed task-definition ARN.
	arn := terraform.Output(t, opts, "example_module")
	require.NotEmpty(t, arn, "example should output a registered task definition ARN")
	require.Contains(t, arn, ":task-definition/", "output should be an ECS task definition ARN")
}

// copyDir recursively copies the .tf files of a Terraform folder into dst.
// Only regular files are copied (the example is flat); .terraform state and
// lock files from any prior local run are skipped so the copy inits cleanly.
func copyDir(src, dst string) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || entry.Name() == ".terraform.lock.hcl" {
			continue
		}
		in, err := os.Open(filepath.Join(src, entry.Name()))
		if err != nil {
			return err
		}
		out, err := os.Create(filepath.Join(dst, entry.Name()))
		if err != nil {
			in.Close()
			return err
		}
		if _, err := io.Copy(out, in); err != nil {
			in.Close()
			out.Close()
			return err
		}
		in.Close()
		if err := out.Close(); err != nil {
			return err
		}
	}
	return nil
}
