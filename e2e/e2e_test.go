// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

// Package e2e deploys the ecs_fargate module to a live ECS Fargate service, then checks the
// task definitions it registers, the traces and logs the service sends to Datadog, that the
// next plan is empty, and that destroy removes everything. See README.md.
package e2e

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	e2eshared "github.com/DataDog/terraform-aws-ecs-datadog/e2e/shared"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func TestECSFargateE2E(t *testing.T) {
	cfg := loadConfig(t)
	ctx := context.Background()
	ecs := ecsAPI{region: cfg.region, cluster: cfg.cluster}

	runID := e2eshared.NewRunID()
	name := e2eshared.ResourceName(sharedCfg, runID)
	t.Logf("run %s deploys service %s to cluster %s in %s", runID, name, cfg.cluster, cfg.region)

	families := []string{name}
	languageImages := map[string]string{}
	for _, sc := range languageCases {
		families = append(families, name+"-"+sc.language)
		languageImages[sc.language] = cfg.image(sc)
	}

	opts := &terraform.Options{
		TerraformDir: copyFixture(t),
		Vars: map[string]any{
			"region":                cfg.region,
			"name":                  name,
			"run_id":                runID,
			"tags":                  e2eshared.Tags(sharedCfg, runID, time.Now().Unix()),
			"cluster":               cfg.cluster,
			"subnets":               cfg.subnets,
			"security_group":        cfg.securityGroup,
			"execution_role_arn":    cfg.executionRoleARN,
			"task_role_arn":         cfg.taskRoleARN,
			"log_group":             cfg.logGroup,
			"dd_api_key_secret_arn": cfg.apiKeySecretARN,
			"dd_site":               cfg.site,
			"dd_env":                testEnv,
			"dd_version":            testVersion,
			"agent_image_version":   cfg.agentImageVersion,
			"service_language":      serviceCase.language,
			"service_image":         cfg.image(serviceCase),
			"language_images":       languageImages,
		},
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               3,
		TimeBetweenRetries:       15 * time.Second,
		NoColor:                  true,
	}

	// Destroy even after a failure, so the service doesn't run until the sweeper deletes it.
	removed := false
	defer func() {
		if removed {
			return
		}
		runPhase(t, "teardown", func() {
			if _, err := terraform.DestroyContextE(t, ctx, opts); err != nil {
				t.Errorf("terraform destroy failed, so the sweeper deletes the %s resources later: %v", name, err)
			}
		})
	}()

	runPhase(t, "applying the module", func() {
		terraform.InitAndApplyContext(t, ctx, opts)
	})
	serviceRevision := terraform.OutputContext(t, ctx, opts, "task_definition_arn")
	languageRevisions := terraform.OutputMapContext(t, ctx, opts, "language_task_definition_arns")

	runPhase(t, "verifying the task definitions", func() {
		for _, family := range families {
			revisions, err := ecs.activeRevisions(ctx, family)
			require.NoError(t, err)
			require.Len(t, revisions, 1, "%s must have one ACTIVE revision", family)
		}
		svc, err := ecs.service(ctx, name)
		require.NoError(t, err)
		require.NotNil(t, svc, "service %s doesn't exist", name)
		require.Equal(t, "ACTIVE", svc.Status)
		require.Equal(t, serviceRevision, svc.TaskDefinition, "the service must run the instrumented revision")

		td, err := ecs.taskDefinition(ctx, serviceRevision)
		require.NoError(t, err)
		require.NoError(t, verifyServiceInstrumented(td, expectations{
			service:         name,
			site:            cfg.site,
			runID:           runID,
			agentImage:      "public.ecr.aws/datadog/agent:" + cfg.agentImageVersion,
			apiKeySecretARN: cfg.apiKeySecretARN,
		}))
		for _, sc := range languageCases {
			td, err := ecs.taskDefinition(ctx, languageRevisions[sc.language])
			require.NoError(t, err)
			require.NoError(t, verifyLanguageInstrumented(td, sc, runID))
		}
	})

	runPhase(t, "waiting for the Datadog Agent", func() {
		require.NoError(t, ecs.waitForAgentHealthy(ctx, t, name, serviceRevision))
	})

	var url string
	runPhase(t, "sending traffic to the service", func() {
		var err error
		url, err = ecs.taskURL(ctx, name, serviceRevision, appPort)
		require.NoError(t, err)
		triggerTraffic(t, url)
	})

	runPhase(t, "waiting for traces and logs", func() {
		// Matches service, env, and run ID. The verifier checks DD_VERSION in the task definition.
		requireTelemetry(ctx, t, cfg, url, e2eshared.IdentityFor(sharedCfg, name, testEnv, "", runID))
	})

	runPhase(t, "checking that the next plan is empty", func() {
		require.Equal(t, 0, terraform.PlanExitCodeContext(t, ctx, opts), "re-applying the module must not change anything")
	})

	runPhase(t, "removing the module", func() {
		terraform.DestroyContext(t, ctx, opts)
		removed = true
	})

	runPhase(t, "verifying cleanup", func() {
		require.NoError(t, ecs.waitForServiceRemoved(ctx, t, name))
		for _, family := range families {
			revisions, err := ecs.activeRevisions(ctx, family)
			require.NoError(t, err)
			require.Empty(t, revisions, "%s still has ACTIVE revisions", family)
		}
	})
}

// triggerTraffic waits until the application answers several requests, which also
// produces the first traces and logs.
func triggerTraffic(t *testing.T, url string) {
	t.Helper()
	const attempts, wantSuccesses = 20, 5
	client := &http.Client{Timeout: 15 * time.Second}
	successes := 0
	lastFailure := "none"
	for attempt := 1; attempt <= attempts; attempt++ {
		resp, err := client.Get(url)
		switch {
		case err != nil:
			lastFailure = err.Error()
		case resp.StatusCode != http.StatusOK:
			lastFailure = resp.Status
		default:
			successes++
		}
		if resp != nil {
			resp.Body.Close()
		}
		if successes == wantSuccesses {
			return
		}
		t.Logf("[traffic] attempt %d/%d: %d/%d successful requests, last failure: %s", attempt, attempts, successes, wantSuccesses, lastFailure)
		time.Sleep(10 * time.Second)
	}
	require.Failf(t, "the service didn't answer", "%s answered %d/%d requests, last failure: %s", url, successes, wantSuccesses, lastFailure)
}

// requireTelemetry waits for a span and a log that carry the identity, while traffic keeps
// new ones inside the search window.
func requireTelemetry(ctx context.Context, t *testing.T, cfg testConfig, url string, id e2eshared.Identity) {
	t.Helper()
	trafficCtx, stopTraffic := context.WithCancel(ctx)
	defer stopTraffic()
	go e2eshared.GenerateTraffic(trafficCtx, url, 10*time.Second)

	client := e2eshared.NewTelemetryClient(cfg.site, cfg.apiKey, cfg.appKey)
	errs := make(chan error, 2)
	go func() {
		_, err := client.WaitForMatching(ctx, "spans", client.SearchSpans, e2eshared.SpanQuery(id), id)
		errs <- err
	}()
	go func() {
		_, err := client.WaitForMatching(ctx, "logs", client.SearchLogs, e2eshared.LogQuery(id), id)
		errs <- err
	}()
	require.NoError(t, errors.Join(<-errs, <-errs), "telemetry didn't reach Datadog")
}

// copyFixture copies the module and the fixture into a temporary directory with the
// repository's layout, so each run has its own state and the module source still resolves.
func copyFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, dir := range []string{"modules/ecs_fargate", "e2e/fixture"} {
		files, err := filepath.Glob(filepath.Join("..", dir, "*.tf"))
		require.NoError(t, err)
		require.NotEmpty(t, files, "no Terraform files in %s", dir)
		require.NoError(t, os.MkdirAll(filepath.Join(root, dir), 0o755))
		for _, file := range files {
			contents, err := os.ReadFile(file)
			require.NoError(t, err)
			require.NoError(t, os.WriteFile(filepath.Join(root, dir, filepath.Base(file)), contents, 0o644))
		}
	}
	return filepath.Join(root, "e2e", "fixture")
}

// runPhase logs the start and end of a phase, plus a heartbeat every 30 seconds.
func runPhase(t *testing.T, name string, fn func()) {
	t.Helper()
	t.Logf("==> %s", name)
	start := time.Now()
	stop, stopped := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(stopped)
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				t.Logf("... still %s (%s)", name, time.Since(start).Round(time.Second))
			}
		}
	}()
	defer func() {
		close(stop)
		<-stopped
	}()
	fn()
	t.Logf("<== %s (%s)", name, time.Since(start).Round(time.Second))
}
