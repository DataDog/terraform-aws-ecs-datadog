// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package e2e

import (
	"fmt"
	"maps"
	"reflect"
	"slices"
	"strings"

	e2eshared "github.com/DataDog/terraform-aws-ecs-datadog/e2e/shared"
)

// Names and values the module writes. They're restated, not read from the module, so an
// unintended change on either side fails the suite.
const (
	agentContainerName     = "datadog-agent"
	logRouterContainerName = "datadog-log-router"
	tracerContainerName    = "datadog-tracer"
	socketVolume           = "dd-sockets"
	socketMountPath        = "/var/run/datadog"
	tracerVolume           = "datadog-tracer"
	tracerMountPath        = "/datadog-lib"
	logRouterImage         = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
	injectionModeDDTag     = "_dd.injection.mode:serverless-single-lang"
)

// The application container in fixture/main.tf.
const (
	appContainerName = "app"
	appPort          = 8080
)

// expectations is what the service's task definition must contain.
type expectations struct {
	service         string
	site            string
	runID           string
	agentImage      string
	apiKeySecretARN string
}

func (e expectations) runIDTag() string {
	return e2eshared.DefaultRunIDTagKey + ":" + e.runID
}

// ddTags is the fixture's dd_tags, which the Agent and every log carry.
func (e expectations) ddTags() string {
	return fmt.Sprintf("env:%s,version:%s,%s", testEnv, testVersion, e.runIDTag())
}

// verifyServiceInstrumented checks the service's task definition: the Agent, unified
// service tagging, log collection, the injected tracer, and the tags.
func verifyServiceInstrumented(td taskDefinition, exp expectations) error {
	agent, app := td.container(agentContainerName), td.container(appContainerName)
	if agent == nil || app == nil {
		return fmt.Errorf("%s has no %s or %s container", td.ARN, agentContainerName, appContainerName)
	}
	var v e2eshared.Violations

	if agent.Image != exp.agentImage {
		v.Addf("%s image = %q, want %q", agent.Name, agent.Image, exp.agentImage)
	}
	if agent.Essential {
		v.Addf("%s must not be essential", agent.Name)
	}
	if agent.HealthCheck == nil || !slices.Equal(agent.HealthCheck.Command, []string{"CMD-SHELL", "/probe.sh"}) {
		v.Addf("%s must have the /probe.sh health check", agent.Name)
	}
	agentEnv := agent.env()
	e2eshared.RequireValues(&v, "agent env", agentEnv, map[string]string{
		"ECS_FARGATE":                    "true",
		"DD_SITE":                        exp.site,
		"DD_TAGS":                        exp.ddTags(),
		"DD_ECS_TASK_COLLECTION_ENABLED": "true",
		"DD_DOGSTATSD_TAG_CARDINALITY":   "orchestrator",
	})
	if _, ok := agentEnv["DD_API_KEY"]; ok {
		v.Addf("the Agent must read DD_API_KEY from Secrets Manager, not environment")
	}
	e2eshared.RequireValues(&v, "agent secret", secretValues(agent.Secrets), map[string]string{"DD_API_KEY": exp.apiKeySecretARN})
	requireMount(&v, agent, socketVolume, socketMountPath)

	e2eshared.RequireValues(&v, "app env", app.env(), map[string]string{
		"DD_SERVICE":         exp.service,
		"DD_ENV":             testEnv,
		"DD_VERSION":         testVersion,
		"DD_TRACE_AGENT_URL": "unix:///var/run/datadog/apm.socket",
		"DD_DOGSTATSD_URL":   "unix:///var/run/datadog/dsd.socket",
	})
	e2eshared.RequireValues(&v, "app docker label", app.DockerLabels, map[string]string{
		"com.datadoghq.tags.service": exp.service,
		"com.datadoghq.tags.env":     testEnv,
		"com.datadoghq.tags.version": testVersion,
	})
	requireMount(&v, app, socketVolume, socketMountPath)

	verifyLogCollection(&v, td, exp)
	verifyInjection(&v, td, serviceCase, injectionModeDDTag+","+exp.runIDTag())
	e2eshared.RequirePresent(&v, "tag", td.Tags, "dd_ecs_terraform_module")
	e2eshared.RequireHygieneTags(&v, sharedCfg, td.Tags, exp.runID)
	return v.Err(td.ARN + " isn't instrumented as expected")
}

// verifyLanguageInstrumented checks a task definition that's registered but never run:
// the injected tracer, and the tracer's logs without FireLens.
func verifyLanguageInstrumented(td taskDefinition, sc ssiCase, runID string) error {
	var v e2eshared.Violations
	verifyInjection(&v, td, sc, injectionModeDDTag)
	if tracer, app := td.container(tracerContainerName), td.container(appContainerName); tracer != nil && app != nil {
		if app.LogConfiguration == nil || app.LogConfiguration.LogDriver != "awslogs" || !reflect.DeepEqual(tracer.LogConfiguration, app.LogConfiguration) {
			v.Addf("%s must reuse the awslogs configuration of %s", tracer.Name, app.Name)
		}
	}
	e2eshared.RequireHygieneTags(&v, sharedCfg, td.Tags, runID)
	return v.Err(td.ARN + " doesn't inject the " + sc.language + " tracer as expected")
}

// verifyLogCollection checks that every container sends its logs through the FireLens
// router, which authenticates with the API key secret.
func verifyLogCollection(v *e2eshared.Violations, td taskDefinition, exp expectations) {
	router := td.container(logRouterContainerName)
	if router == nil {
		v.Addf("missing the %s container", logRouterContainerName)
		return
	}
	if router.Image != logRouterImage {
		v.Addf("%s image = %q, want %q", router.Name, router.Image, logRouterImage)
	}
	if router.FirelensConfiguration == nil || router.FirelensConfiguration.Type != "fluentbit" {
		v.Addf("%s must be a Fluent Bit FireLens router", router.Name)
	}
	for _, c := range td.ContainerDefinitions {
		if c.Name == router.Name {
			continue
		}
		if c.LogConfiguration == nil || c.LogConfiguration.LogDriver != "awsfirelens" {
			v.Addf("%s logs must go through FireLens", c.Name)
			continue
		}
		label := c.Name + " log option"
		e2eshared.RequireValues(v, label, c.LogConfiguration.Options, map[string]string{
			"Name":       "datadog",
			"provider":   "ecs",
			"Host":       "http-intake.logs." + exp.site,
			"TLS":        "on",
			"dd_service": exp.service,
			"dd_tags":    exp.ddTags(),
		})
		if _, ok := c.LogConfiguration.Options["apikey"]; ok {
			v.Addf("%s apikey must come from Secrets Manager", label)
		}
		e2eshared.RequireValues(v, c.Name+" log secret", secretValues(c.LogConfiguration.SecretOptions), map[string]string{"apikey": exp.apiKeySecretARN})
	}
}

// verifyInjection checks one language's tracer injection: the copy container and volume,
// and the application's mount, start dependency, and environment.
func verifyInjection(v *e2eshared.Violations, td taskDefinition, sc ssiCase, wantDDTags string) {
	tracer, app := td.container(tracerContainerName), td.container(appContainerName)
	if tracer == nil || app == nil {
		v.Addf("missing the %s or %s container", tracerContainerName, appContainerName)
		return
	}

	wantImage := "public.ecr.aws/datadog/dd-lib-" + sc.language + "-init:latest"
	if tracer.Image != wantImage {
		v.Addf("%s image = %q, want %q", tracer.Name, tracer.Image, wantImage)
	}
	// The copy runs as root and exits, which only a non-essential container may do.
	if tracer.Essential || tracer.User != "0" {
		v.Addf("%s must be non-essential and run as root", tracer.Name)
	}
	if !slices.Equal(tracer.EntryPoint, []string{"/datadog-init/copy-lib.sh"}) || !slices.Equal(tracer.Command, []string{tracerMountPath}) {
		v.Addf("%s runs %v %v, want [/datadog-init/copy-lib.sh] [%s]", tracer.Name, tracer.EntryPoint, tracer.Command, tracerMountPath)
	}
	requireMount(v, tracer, tracerVolume, tracerMountPath)
	if !td.hasVolume(tracerVolume) {
		v.Addf("missing the %s volume", tracerVolume)
	}

	requireMount(v, app, tracerVolume, tracerMountPath)
	if !slices.Contains(app.DependsOn, containerDependency{ContainerName: tracer.Name, Condition: "SUCCESS"}) {
		v.Addf("%s must start after %s succeeds", app.Name, tracer.Name)
	}
	appEnv := app.env()
	e2eshared.RequireValues(v, "app env", appEnv, sc.loaderEnv)
	e2eshared.RequireValues(v, "app env", appEnv, map[string]string{"DD_TAGS": wantDDTags})
	loaderEnvNames := slices.Sorted(maps.Keys(sc.loaderEnv))
	for _, name := range append(loaderEnvNames, "DD_TAGS") {
		if n := app.envCount(name); n > 1 {
			v.Addf("app env %s is set %d times", name, n)
		}
	}

	// Only the application loads the tracer.
	for _, c := range td.ContainerDefinitions {
		if c.Name == app.Name || c.Name == tracer.Name {
			continue
		}
		for _, m := range c.MountPoints {
			if m.SourceVolume == tracerVolume {
				v.Addf("%s must not mount %s", c.Name, tracerVolume)
			}
		}
		env := c.env()
		for _, name := range loaderEnvNames {
			if _, ok := env[name]; ok {
				v.Addf("%s must not set %s", c.Name, name)
			}
		}
		if strings.Contains(env["DD_TAGS"], injectionModeDDTag) {
			v.Addf("%s DD_TAGS must not include %s", c.Name, injectionModeDDTag)
		}
	}

	if got := td.Tags["dd_sls_injection_mode"]; got != "single_language" {
		v.Addf("tag dd_sls_injection_mode = %q, want %q", got, "single_language")
	}
}

// requireMount checks that c mounts the named volume once, at path.
func requireMount(v *e2eshared.Violations, c *containerDefinition, name, path string) {
	var paths []string
	for _, m := range c.MountPoints {
		if m.SourceVolume == name {
			paths = append(paths, m.ContainerPath)
		}
	}
	if !slices.Equal(paths, []string{path}) {
		v.Addf("%s mounts %s at %v, want [%s]", c.Name, name, paths, path)
	}
}
