// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package e2e

import (
	"os"
	"sort"
	"strings"
	"testing"

	e2eshared "github.com/DataDog/terraform-aws-ecs-datadog/e2e/shared"
	"github.com/stretchr/testify/require"
)

const (
	testEnv     = "e2e"
	testVersion = "1.0.0"

	defaultRegion = "eu-central-1"
	defaultSite   = "datadoghq.com"
	// Pinned so an Agent release can't fail the suite. Override with E2E_AGENT_IMAGE_VERSION.
	// The tracer stays on latest on purpose so a tracer release that breaks injection fails the suite.
	defaultAgentImageVersion = "7.84.2"
)

var sharedCfg = e2eshared.Config{
	Tool:     "tf",
	Platform: "ecs",
	Command:  "aws",
	// AWS CLI errors worth retrying: throttling, server faults, and dropped connections.
	RetryPatterns: []string{
		"Throttling",
		"TooManyRequests",
		"Rate exceeded",
		"RequestLimitExceeded",
		"ServerException",
		"ServiceUnavailable",
		"InternalFailure",
		"Could not connect to the endpoint URL",
		"Connection was closed",
		"Read timeout on endpoint URL",
	},
}

// Terraform errors worth retrying. Terratest matches each key as a regular expression.
var retryableTerraformErrors = map[string]string{
	"(?i)throttl":              "AWS throttled the request",
	"Rate exceeded":            "AWS throttled the request",
	"ServerException":          "ECS returned a server error",
	"connection reset by peer": "the connection to AWS dropped",
	"TLS handshake timeout":    "the connection to AWS timed out",
}

// ssiCase is one language the module can inject a tracer for.
type ssiCase struct {
	language string
	// image is the repository in AWS_ECS_APP_IMAGE_REGISTRY that serves HTTP without a tracer.
	image string
	// loaderEnv is the startup environment that loads the copied tracer.
	loaderEnv map[string]string
}

// serviceCase is the language the service runs, which proves an injected tracer sends traces.
var serviceCase = ssiCase{
	language:  "js",
	image:     "node-ssi",
	loaderEnv: map[string]string{"NODE_OPTIONS": "--require /datadog-lib/node_modules/dd-trace/init.js"},
}

// languageCases are registered and verified, but never run.
var languageCases = []ssiCase{
	{
		language: "dotnet",
		image:    "dotnet-ssi",
		loaderEnv: map[string]string{
			"CORECLR_ENABLE_PROFILING": "1",
			"CORECLR_PROFILER":         "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}",
			"CORECLR_PROFILER_PATH":    "/datadog-lib/Datadog.Trace.ClrProfiler.Native.so",
			"DD_DOTNET_TRACER_HOME":    "/datadog-lib",
			"LD_PRELOAD":               "/datadog-lib/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so",
		},
	},
	{
		language:  "java",
		image:     "java-ssi",
		loaderEnv: map[string]string{"JAVA_TOOL_OPTIONS": "-javaagent:/datadog-lib/dd-java-agent.jar -XX:+IgnoreUnrecognizedVMOptions"},
	},
	{
		language: "php",
		image:    "php-ssi",
		loaderEnv: map[string]string{
			"PHP_INI_SCAN_DIR":       ":/datadog-lib/linux-gnu/loader",
			"DD_LOADER_PACKAGE_PATH": "/datadog-lib",
		},
	},
	{
		language:  "python",
		image:     "python-ssi",
		loaderEnv: map[string]string{"PYTHONPATH": "/datadog-lib"},
	},
	{
		language:  "ruby",
		image:     "ruby-ssi",
		loaderEnv: map[string]string{"RUBYOPT": "-r/datadog-lib/auto_inject"},
	},
}

// testConfig is the pre-provisioned AWS infrastructure and the credentials the suite uses.
type testConfig struct {
	region            string
	site              string
	apiKey            string
	appKey            string
	cluster           string
	subnets           []string
	securityGroup     string
	executionRoleARN  string
	taskRoleARN       string
	imageRegistry     string
	apiKeySecretARN   string
	logGroup          string
	agentImageVersion string
}

func loadConfig(t *testing.T) testConfig {
	t.Helper()
	cfg := testConfig{
		region: firstEnv(defaultRegion, "AWS_REGION", "AWS_DEFAULT_REGION"),
		site:   firstEnv(defaultSite, "DD_SITE"),
		// DATADOG_* comes first: CI can also export a DD_API_KEY for another organization.
		apiKey:            firstEnv("", "DATADOG_API_KEY", "DD_API_KEY"),
		appKey:            firstEnv("", "DATADOG_APP_KEY", "DD_APP_KEY"),
		cluster:           os.Getenv("AWS_ECS_CLUSTER"),
		securityGroup:     os.Getenv("AWS_ECS_SECURITY_GROUP"),
		executionRoleARN:  os.Getenv("AWS_ECS_EXECUTION_ROLE_ARN"),
		taskRoleARN:       os.Getenv("AWS_ECS_TASK_ROLE_ARN"),
		imageRegistry:     strings.TrimSuffix(os.Getenv("AWS_ECS_APP_IMAGE_REGISTRY"), "/"),
		apiKeySecretARN:   os.Getenv("AWS_ECS_API_KEY_SECRET_ARN"),
		logGroup:          os.Getenv("AWS_ECS_LOG_GROUP"),
		agentImageVersion: firstEnv(defaultAgentImageVersion, "E2E_AGENT_IMAGE_VERSION"),
	}
	for _, subnet := range strings.Split(os.Getenv("AWS_ECS_SUBNETS"), ",") {
		if subnet = strings.TrimSpace(subnet); subnet != "" {
			cfg.subnets = append(cfg.subnets, subnet)
		}
	}

	var missing []string
	for name, value := range map[string]string{
		"DATADOG_API_KEY":            cfg.apiKey,
		"DATADOG_APP_KEY":            cfg.appKey,
		"AWS_ECS_CLUSTER":            cfg.cluster,
		"AWS_ECS_SUBNETS":            strings.Join(cfg.subnets, ","),
		"AWS_ECS_SECURITY_GROUP":     cfg.securityGroup,
		"AWS_ECS_EXECUTION_ROLE_ARN": cfg.executionRoleARN,
		"AWS_ECS_TASK_ROLE_ARN":      cfg.taskRoleARN,
		"AWS_ECS_APP_IMAGE_REGISTRY": cfg.imageRegistry,
		"AWS_ECS_API_KEY_SECRET_ARN": cfg.apiKeySecretARN,
		"AWS_ECS_LOG_GROUP":          cfg.logGroup,
	} {
		if value == "" {
			missing = append(missing, name)
		}
	}
	sort.Strings(missing)
	require.Empty(t, missing, "missing required e2e configuration (see README.md): %v", missing)
	return cfg
}

// image is the fixture application image for a case.
func (c testConfig) image(sc ssiCase) string {
	return c.imageRegistry + "/" + sc.image + ":latest"
}

// firstEnv returns the first set environment variable among keys, or fallback.
func firstEnv(fallback string, keys ...string) string {
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return fallback
}
