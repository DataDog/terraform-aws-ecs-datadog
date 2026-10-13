// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	e2eshared "github.com/DataDog/terraform-aws-ecs-datadog/e2e/shared"
)

// taskDefinition is the part of an ECS task definition the verifier reads.
type taskDefinition struct {
	ARN                  string                `json:"taskDefinitionArn"`
	ContainerDefinitions []containerDefinition `json:"containerDefinitions"`
	Volumes              []volume              `json:"volumes"`
	// Tags come from the DescribeTaskDefinition response, outside the task definition.
	Tags map[string]string `json:"-"`
}

type containerDefinition struct {
	Name                  string                 `json:"name"`
	Image                 string                 `json:"image"`
	Essential             bool                   `json:"essential"`
	User                  string                 `json:"user"`
	EntryPoint            []string               `json:"entryPoint"`
	Command               []string               `json:"command"`
	Environment           []nameValue            `json:"environment"`
	Secrets               []secret               `json:"secrets"`
	DockerLabels          map[string]string      `json:"dockerLabels"`
	MountPoints           []mountPoint           `json:"mountPoints"`
	DependsOn             []containerDependency  `json:"dependsOn"`
	HealthCheck           *healthCheck           `json:"healthCheck"`
	FirelensConfiguration *firelensConfiguration `json:"firelensConfiguration"`
	LogConfiguration      *logConfiguration      `json:"logConfiguration"`
}

type nameValue struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type secret struct {
	Name      string `json:"name"`
	ValueFrom string `json:"valueFrom"`
}

type mountPoint struct {
	SourceVolume  string `json:"sourceVolume"`
	ContainerPath string `json:"containerPath"`
	ReadOnly      bool   `json:"readOnly"`
}

type containerDependency struct {
	ContainerName string `json:"containerName"`
	Condition     string `json:"condition"`
}

type healthCheck struct {
	Command []string `json:"command"`
}

type firelensConfiguration struct {
	Type string `json:"type"`
}

type logConfiguration struct {
	LogDriver     string            `json:"logDriver"`
	Options       map[string]string `json:"options"`
	SecretOptions []secret          `json:"secretOptions"`
}

type volume struct {
	Name string `json:"name"`
}

func (td taskDefinition) container(name string) *containerDefinition {
	for i := range td.ContainerDefinitions {
		if td.ContainerDefinitions[i].Name == name {
			return &td.ContainerDefinitions[i]
		}
	}
	return nil
}

func (td taskDefinition) hasVolume(name string) bool {
	for _, v := range td.Volumes {
		if v.Name == name {
			return true
		}
	}
	return false
}

func (c containerDefinition) env() map[string]string {
	env := make(map[string]string, len(c.Environment))
	for _, e := range c.Environment {
		env[e.Name] = e.Value
	}
	return env
}

// envCount counts the entries named name, so env() can't hide a duplicate.
func (c containerDefinition) envCount(name string) int {
	n := 0
	for _, e := range c.Environment {
		if e.Name == name {
			n++
		}
	}
	return n
}

func secretValues(secrets []secret) map[string]string {
	values := make(map[string]string, len(secrets))
	for _, s := range secrets {
		values[s.Name] = s.ValueFrom
	}
	return values
}

type ecsService struct {
	Status         string `json:"status"`
	TaskDefinition string `json:"taskDefinition"`
}

type ecsTask struct {
	ARN               string `json:"taskArn"`
	TaskDefinitionARN string `json:"taskDefinitionArn"`
	LastStatus        string `json:"lastStatus"`
	Containers        []struct {
		Name         string `json:"name"`
		LastStatus   string `json:"lastStatus"`
		HealthStatus string `json:"healthStatus"`
		ExitCode     *int   `json:"exitCode"`
	} `json:"containers"`
	Attachments []struct {
		Type    string      `json:"type"`
		Details []nameValue `json:"details"`
	} `json:"attachments"`
}

func (t ecsTask) networkInterfaceID() string {
	for _, attachment := range t.Attachments {
		if attachment.Type != "ElasticNetworkInterface" {
			continue
		}
		for _, detail := range attachment.Details {
			if detail.Name == "networkInterfaceId" {
				return detail.Value
			}
		}
	}
	return ""
}

// containerStatuses summarizes each container's state, such as a tracer copy that failed.
func (t ecsTask) containerStatuses() string {
	statuses := make([]string, 0, len(t.Containers))
	for _, c := range t.Containers {
		status := c.Name + "=" + c.LastStatus
		if c.HealthStatus != "" && c.HealthStatus != "UNKNOWN" {
			status += "/" + c.HealthStatus
		}
		if c.ExitCode != nil {
			status += fmt.Sprintf("(exit %d)", *c.ExitCode)
		}
		statuses = append(statuses, status)
	}
	sort.Strings(statuses)
	return strings.Join(statuses, " ")
}

// ecsAPI reads ECS and EC2 state through the AWS CLI.
type ecsAPI struct {
	region  string
	cluster string
}

func (a ecsAPI) call(ctx context.Context, out any, args ...string) error {
	args = append(args, "--region", a.region, "--output", "json")
	res, err := e2eshared.RunWithRetries(ctx, sharedCfg, 4, 5*time.Second, args...)
	if err != nil {
		return err
	}
	if err := json.Unmarshal([]byte(res.Stdout), out); err != nil {
		return fmt.Errorf("parse the output of aws %s %s: %w", args[0], args[1], err)
	}
	return nil
}

func (a ecsAPI) taskDefinition(ctx context.Context, arn string) (taskDefinition, error) {
	var out struct {
		TaskDefinition taskDefinition `json:"taskDefinition"`
		Tags           []struct {
			Key   string `json:"key"`
			Value string `json:"value"`
		} `json:"tags"`
	}
	if err := a.call(ctx, &out, "ecs", "describe-task-definition", "--task-definition", arn, "--include", "TAGS"); err != nil {
		return taskDefinition{}, err
	}
	td := out.TaskDefinition
	td.Tags = make(map[string]string, len(out.Tags))
	for _, tag := range out.Tags {
		td.Tags[tag.Key] = tag.Value
	}
	return td, nil
}

// activeRevisions lists the ACTIVE revision ARNs of family.
func (a ecsAPI) activeRevisions(ctx context.Context, family string) ([]string, error) {
	var out struct {
		ARNs []string `json:"taskDefinitionArns"`
	}
	if err := a.call(ctx, &out, "ecs", "list-task-definitions", "--family-prefix", family, "--status", "ACTIVE"); err != nil {
		return nil, err
	}
	// Count only this family, never a language family that shares its prefix.
	var revisions []string
	for _, arn := range out.ARNs {
		if strings.HasPrefix(arn[strings.LastIndex(arn, "/")+1:], family+":") {
			revisions = append(revisions, arn)
		}
	}
	return revisions, nil
}

// service returns the named service, or nil when ECS reports it MISSING.
func (a ecsAPI) service(ctx context.Context, name string) (*ecsService, error) {
	var out struct {
		Services []ecsService `json:"services"`
		Failures []struct {
			Reason string `json:"reason"`
		} `json:"failures"`
	}
	if err := a.call(ctx, &out, "ecs", "describe-services", "--cluster", a.cluster, "--services", name); err != nil {
		return nil, err
	}
	if len(out.Services) > 0 {
		return &out.Services[0], nil
	}
	if len(out.Failures) > 0 && out.Failures[0].Reason == "MISSING" {
		return nil, nil
	}
	return nil, fmt.Errorf("describe service %s: %+v", name, out.Failures)
}

// runningTasks returns the service's RUNNING tasks on revision.
func (a ecsAPI) runningTasks(ctx context.Context, service, revision string) ([]ecsTask, error) {
	var list struct {
		ARNs []string `json:"taskArns"`
	}
	if err := a.call(ctx, &list, "ecs", "list-tasks", "--cluster", a.cluster, "--service-name", service, "--desired-status", "RUNNING"); err != nil {
		return nil, err
	}
	if len(list.ARNs) == 0 {
		return nil, nil
	}
	var out struct {
		Tasks []ecsTask `json:"tasks"`
	}
	if err := a.call(ctx, &out, append([]string{"ecs", "describe-tasks", "--cluster", a.cluster, "--tasks"}, list.ARNs...)...); err != nil {
		return nil, err
	}
	var tasks []ecsTask
	for _, task := range out.Tasks {
		if task.TaskDefinitionARN == revision && task.LastStatus == "RUNNING" {
			tasks = append(tasks, task)
		}
	}
	return tasks, nil
}

// waitForAgentHealthy waits until a task on revision reports a HEALTHY Agent.
func (a ecsAPI) waitForAgentHealthy(ctx context.Context, t *testing.T, service, revision string) error {
	t.Helper()
	const attempts, interval = 12, 20 * time.Second
	for attempt := 1; attempt <= attempts; attempt++ {
		tasks, err := a.runningTasks(ctx, service, revision)
		if err != nil {
			return err
		}
		var statuses []string
		for _, task := range tasks {
			for _, c := range task.Containers {
				if c.Name != agentContainerName {
					continue
				}
				switch c.HealthStatus {
				case "HEALTHY":
					return nil
				case "UNHEALTHY":
					return fmt.Errorf("the Agent in %s is UNHEALTHY: check that AWS_ECS_API_KEY_SECRET_ARN holds a valid API key for DD_SITE", task.ARN)
				}
			}
			statuses = append(statuses, task.containerStatuses())
		}
		t.Logf("[agent health] attempt %d/%d: %d running task(s) %v", attempt, attempts, len(tasks), statuses)
		time.Sleep(interval)
	}
	return fmt.Errorf("no task on %s reported a HEALTHY Agent after %d attempts", revision, attempts)
}

// taskURL returns the address of the application on a running task of revision.
func (a ecsAPI) taskURL(ctx context.Context, service, revision string, port int) (string, error) {
	tasks, err := a.runningTasks(ctx, service, revision)
	if err != nil {
		return "", err
	}
	for _, task := range tasks {
		eni := task.networkInterfaceID()
		if eni == "" {
			continue
		}
		var out struct {
			NetworkInterfaces []struct {
				Association *struct {
					PublicIP string `json:"PublicIp"`
				} `json:"Association"`
			} `json:"NetworkInterfaces"`
		}
		if err := a.call(ctx, &out, "ec2", "describe-network-interfaces", "--network-interface-ids", eni); err != nil {
			return "", err
		}
		for _, ni := range out.NetworkInterfaces {
			if ni.Association != nil && ni.Association.PublicIP != "" {
				return fmt.Sprintf("http://%s:%d/", ni.Association.PublicIP, port), nil
			}
		}
	}
	return "", fmt.Errorf("no running task on %s has a public IP", revision)
}

// waitForServiceRemoved waits until ECS reports the service INACTIVE or MISSING.
func (a ecsAPI) waitForServiceRemoved(ctx context.Context, t *testing.T, name string) error {
	t.Helper()
	const attempts, interval = 20, 15 * time.Second
	for attempt := 1; attempt <= attempts; attempt++ {
		svc, err := a.service(ctx, name)
		if err != nil {
			return err
		}
		if svc == nil || svc.Status == "INACTIVE" {
			return nil
		}
		t.Logf("[cleanup] attempt %d/%d: service %s is %s", attempt, attempts, name, svc.Status)
		time.Sleep(interval)
	}
	return fmt.Errorf("service %s is not INACTIVE after %d attempts", name, attempts)
}
