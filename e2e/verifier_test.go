// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package e2e

import (
	"maps"
	"slices"
	"testing"

	"github.com/stretchr/testify/require"
)

var testExp = expectations{
	service:         "one-e2e-tf-ecs-deadbeef",
	site:            "datadoghq.com",
	runID:           "deadbeef",
	agentImage:      "public.ecr.aws/datadog/agent:7.84.2",
	apiKeySecretARN: "arn:aws:secretsmanager:eu-central-1:123456789012:secret:dd-api-key",
}

var (
	socketMount = mountPoint{SourceVolume: socketVolume, ContainerPath: socketMountPath}
	tracerMount = mountPoint{SourceVolume: tracerVolume, ContainerPath: tracerMountPath}
)

func TestVerifyServiceInstrumented(t *testing.T) {
	require.NoError(t, verifyServiceInstrumented(serviceTaskDefinition(), testExp))

	for name, tc := range map[string]struct {
		mutate func(td *taskDefinition)
		want   string
	}{
		"unpinned Agent image": {
			func(td *taskDefinition) {
				td.container(agentContainerName).Image = "public.ecr.aws/datadog/agent:latest"
			},
			"datadog-agent image",
		},
		"plain-text API key": {
			func(td *taskDefinition) { addEnv(td.container(agentContainerName), "DD_API_KEY", "key") },
			"DD_API_KEY from Secrets Manager",
		},
		"logs bypass FireLens": {
			func(td *taskDefinition) { td.container(appContainerName).LogConfiguration = nil },
			"app logs must go through FireLens",
		},
		"replaced DD_TAGS": {
			func(td *taskDefinition) { setEnv(td.container(appContainerName), "DD_TAGS", injectionModeDDTag) },
			"app env DD_TAGS",
		},
		"duplicated loader variable": {
			func(td *taskDefinition) { addEnv(td.container(appContainerName), "NODE_OPTIONS", "--require x") },
			"NODE_OPTIONS is set 2 times",
		},
		"no tracer dependency": {
			func(td *taskDefinition) { td.container(appContainerName).DependsOn = nil },
			"app must start after datadog-tracer succeeds",
		},
		"tracer volume on the Agent": {
			func(td *taskDefinition) {
				agent := td.container(agentContainerName)
				agent.MountPoints = append(agent.MountPoints, tracerMount)
			},
			"datadog-agent must not mount datadog-tracer",
		},
		"no injection mode tag": {
			func(td *taskDefinition) { delete(td.Tags, "dd_sls_injection_mode") },
			"dd_sls_injection_mode",
		},
		"no freshness tag": {
			func(td *taskDefinition) { delete(td.Tags, "one_e2e_created") },
			"one_e2e_created",
		},
	} {
		t.Run(name, func(t *testing.T) {
			td := serviceTaskDefinition()
			tc.mutate(&td)
			require.ErrorContains(t, verifyServiceInstrumented(td, testExp), tc.want)
		})
	}
}

func TestVerifyLanguageInstrumented(t *testing.T) {
	for i, sc := range languageCases {
		t.Run(sc.language, func(t *testing.T) {
			require.NoError(t, verifyLanguageInstrumented(languageTaskDefinition(sc), sc, testExp.runID))

			other := languageCases[(i+1)%len(languageCases)]
			require.Error(t, verifyLanguageInstrumented(languageTaskDefinition(other), sc, testExp.runID))

			td := languageTaskDefinition(sc)
			td.container(tracerContainerName).LogConfiguration = nil
			require.ErrorContains(t, verifyLanguageInstrumented(td, sc, testExp.runID), "must reuse the awslogs configuration")
		})
	}
}

// serviceTaskDefinition is what the module registers for the fixture's service.
func serviceTaskDefinition() taskDefinition {
	return taskDefinition{
		ARN: "arn:aws:ecs:eu-central-1:123456789012:task-definition/" + testExp.service + ":1",
		ContainerDefinitions: []containerDefinition{
			{
				Name:  agentContainerName,
				Image: testExp.agentImage,
				Environment: []nameValue{
					{"DD_DOGSTATSD_TAG_CARDINALITY", "orchestrator"},
					{"DD_ECS_TASK_COLLECTION_ENABLED", "true"},
					{"DD_SITE", testExp.site},
					{"DD_TAGS", testExp.ddTags()},
					{"ECS_FARGATE", "true"},
				},
				Secrets:          []secret{{"DD_API_KEY", testExp.apiKeySecretARN}},
				MountPoints:      []mountPoint{socketMount},
				HealthCheck:      &healthCheck{Command: []string{"CMD-SHELL", "/probe.sh"}},
				LogConfiguration: firelensLogs(),
			},
			{
				Name:                  logRouterContainerName,
				Image:                 logRouterImage,
				User:                  "0",
				FirelensConfiguration: &firelensConfiguration{Type: "fluentbit"},
			},
			tracerContainer(serviceCase, firelensLogs()),
			{
				Name:      appContainerName,
				Image:     "registry/node-ssi:latest",
				Essential: true,
				Environment: []nameValue{
					{"DD_DOGSTATSD_URL", "unix:///var/run/datadog/dsd.socket"},
					{"DD_TRACE_AGENT_URL", "unix:///var/run/datadog/apm.socket"},
					{"DD_ENV", testEnv},
					{"DD_SERVICE", testExp.service},
					{"DD_VERSION", testVersion},
					{"DD_TAGS", injectionModeDDTag + "," + testExp.runIDTag()},
					{"NODE_OPTIONS", serviceCase.loaderEnv["NODE_OPTIONS"]},
				},
				DockerLabels: map[string]string{
					"com.datadoghq.tags.env":     testEnv,
					"com.datadoghq.tags.service": testExp.service,
					"com.datadoghq.tags.version": testVersion,
				},
				MountPoints:      []mountPoint{socketMount, tracerMount},
				DependsOn:        []containerDependency{{tracerContainerName, "SUCCESS"}},
				LogConfiguration: firelensLogs(),
			},
		},
		Volumes: []volume{{socketVolume}, {tracerVolume}},
		Tags:    taskDefinitionTags(),
	}
}

// languageTaskDefinition is what the module registers for a language without log collection.
func languageTaskDefinition(sc ssiCase) taskDefinition {
	awslogs := func() *logConfiguration {
		return &logConfiguration{LogDriver: "awslogs", Options: map[string]string{
			"awslogs-group":         "/ecs/one-e2e",
			"awslogs-region":        "eu-central-1",
			"awslogs-stream-prefix": testExp.service + "-" + sc.language,
		}}
	}
	env := []nameValue{{"DD_TAGS", injectionModeDDTag}}
	for _, name := range slices.Sorted(maps.Keys(sc.loaderEnv)) {
		env = append(env, nameValue{name, sc.loaderEnv[name]})
	}
	return taskDefinition{
		ARN: "arn:aws:ecs:eu-central-1:123456789012:task-definition/" + testExp.service + "-" + sc.language + ":1",
		ContainerDefinitions: []containerDefinition{
			{Name: agentContainerName, Image: testExp.agentImage, MountPoints: []mountPoint{socketMount}},
			tracerContainer(sc, awslogs()),
			{
				Name:             appContainerName,
				Essential:        true,
				Environment:      env,
				MountPoints:      []mountPoint{socketMount, tracerMount},
				DependsOn:        []containerDependency{{tracerContainerName, "SUCCESS"}},
				LogConfiguration: awslogs(),
			},
		},
		Volumes: []volume{{socketVolume}, {tracerVolume}},
		Tags:    taskDefinitionTags(),
	}
}

func tracerContainer(sc ssiCase, logs *logConfiguration) containerDefinition {
	return containerDefinition{
		Name:             tracerContainerName,
		Image:            "public.ecr.aws/datadog/dd-lib-" + sc.language + "-init:latest",
		User:             "0",
		EntryPoint:       []string{"/datadog-init/copy-lib.sh"},
		Command:          []string{tracerMountPath},
		MountPoints:      []mountPoint{tracerMount},
		LogConfiguration: logs,
	}
}

func firelensLogs() *logConfiguration {
	return &logConfiguration{
		LogDriver: "awsfirelens",
		Options: map[string]string{
			"Host":        "http-intake.logs." + testExp.site,
			"Name":        "datadog",
			"TLS":         "on",
			"dd_service":  testExp.service,
			"dd_tags":     testExp.ddTags(),
			"provider":    "ecs",
			"retry_limit": "2",
		},
		SecretOptions: []secret{{"apikey", testExp.apiKeySecretARN}},
	}
}

func taskDefinitionTags() map[string]string {
	return map[string]string{
		"dd_ecs_terraform_module": "1.1.1",
		"dd_sls_injection_mode":   "single_language",
		"one_e2e_created":         "1700000000",
		"one_e2e_run_id":          testExp.runID,
	}
}

func addEnv(c *containerDefinition, name, value string) {
	c.Environment = append(c.Environment, nameValue{name, value})
}

func setEnv(c *containerDefinition, name, value string) {
	for i := range c.Environment {
		if c.Environment[i].Name == name {
			c.Environment[i].Value = value
		}
	}
}
