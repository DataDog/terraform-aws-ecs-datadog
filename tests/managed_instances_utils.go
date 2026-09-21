// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"slices"
	"testing"

	"github.com/stretchr/testify/assert"
)

// MIEnvVar is a single environment variable entry in the ecs_managed_instances
// module's container_definition output. Field names match the snake_case
// keys produced by aws_ecs_daemon_task_definition's HCL block, not the
// camelCase ECS API shape used by types.ContainerDefinition.
type MIEnvVar struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// MIMountPoint mirrors the mount_point block on aws_ecs_daemon_task_definition.
type MIMountPoint struct {
	SourceVolume  string `json:"source_volume"`
	ContainerPath string `json:"container_path"`
	ReadOnly      bool   `json:"read_only"`
}

// MISecret mirrors the secret block on aws_ecs_daemon_task_definition.
type MISecret struct {
	Name      string `json:"name"`
	ValueFrom string `json:"value_from"`
}

// MIHealthCheck mirrors the health_check block on aws_ecs_daemon_task_definition.
type MIHealthCheck struct {
	Command     []string `json:"command"`
	Interval    int      `json:"interval"`
	Retries     int      `json:"retries"`
	StartPeriod int      `json:"start_period"`
	Timeout     int      `json:"timeout"`
}

// MICapabilities mirrors the capabilities block nested under linux_parameters.
type MICapabilities struct {
	Add  []string `json:"add"`
	Drop []string `json:"drop"`
}

// MILinuxParameters mirrors the linux_parameters block on aws_ecs_daemon_task_definition.
type MILinuxParameters struct {
	Capabilities MICapabilities `json:"capabilities"`
}

// MILogConfiguration mirrors the log_configuration block on aws_ecs_daemon_task_definition.
type MILogConfiguration struct {
	LogDriver    string            `json:"log_driver"`
	Options      map[string]string `json:"options"`
	SecretOption []MISecret        `json:"secret_option"`
}

// MIContainerDefinition mirrors the single container_definition block produced
// by modules/ecs_managed_instances, as returned via jsonencode(local.dd_agent_container_definition)
// on the module's `container_definition` output. This is a single JSON OBJECT,
// not an array, and its keys are the snake_case HCL attribute names of
// aws_ecs_daemon_task_definition's container_definition block - NOT the
// camelCase ECS API field names that types.ContainerDefinition expects, so
// that SDK type cannot be reused to deserialize it.
type MIContainerDefinition struct {
	Name             string              `json:"name"`
	Image            string              `json:"image"`
	Essential        bool                `json:"essential"`
	CPU              int                 `json:"cpu"`
	Memory           int                 `json:"memory"`
	Environment      []MIEnvVar          `json:"environment"`
	MountPoint       []MIMountPoint      `json:"mount_point"`
	Secret           []MISecret          `json:"secret"`
	HealthCheck      *MIHealthCheck      `json:"health_check"`
	LinuxParameters  *MILinuxParameters  `json:"linux_parameters"`
	LogConfiguration *MILogConfiguration `json:"log_configuration"`
}

// GetMIEnvVar retrieves the value of an environment variable from a
// MIContainerDefinition.
func GetMIEnvVar(container MIContainerDefinition, name string) (string, bool) {
	for _, env := range container.Environment {
		if env.Name == name {
			return env.Value, true
		}
	}
	return "", false
}

// AssertMIEnvVars checks that the expected environment variables are all
// present in the container with the expected values.
func AssertMIEnvVars(t *testing.T, container MIContainerDefinition, expectedEnvVars map[string]string) {
	for key, expectedValue := range expectedEnvVars {
		value, found := GetMIEnvVar(container, key)
		assert.True(t, found, "Environment variable %s not found in %s container", key, container.Name)
		assert.Equal(t, expectedValue, value, "Environment variable %s value does not match expected in %s container", key, container.Name)
	}
}

// AssertMINotEnvVars checks that a container does NOT have the specified
// environment variables (e.g. verifying dd_environment overrides removed a
// module-set default rather than producing a duplicate Set member).
func AssertMINotEnvVars(t *testing.T, container MIContainerDefinition, unexpectedEnvVars []string) {
	for _, unexpectedName := range unexpectedEnvVars {
		_, found := GetMIEnvVar(container, unexpectedName)
		assert.False(t, found, "Environment variable %s should not be present in %s container", unexpectedName, container.Name)
	}
}

// AssertMIMountPoint checks that an expected mount point exists in the container.
func AssertMIMountPoint(t *testing.T, container MIContainerDefinition, expected MIMountPoint) {
	found := slices.Contains(container.MountPoint, expected)
	assert.True(t, found, "Expected mount point %+v not found in %s container", expected, container.Name)
}
