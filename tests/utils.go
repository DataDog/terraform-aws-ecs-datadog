// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
	"github.com/stretchr/testify/assert"
)

var (
	MountDdSocket       = types.MountPoint{SourceVolume: aws.String("dd-sockets"), ContainerPath: aws.String("/var/run/datadog"), ReadOnly: aws.Bool(false)}
	MountCWS            = types.MountPoint{SourceVolume: aws.String("cws-instrumentation-volume"), ContainerPath: aws.String("/cws-instrumentation-volume"), ReadOnly: aws.Bool(false)}
	MountInitVolume     = types.MountPoint{SourceVolume: aws.String("agent-config"), ContainerPath: aws.String("/agent-config"), ReadOnly: aws.Bool(false)}
	MountAgentConfig    = types.MountPoint{SourceVolume: aws.String("agent-config"), ContainerPath: aws.String("/etc/datadog-agent"), ReadOnly: aws.Bool(false)}
	MountAgentTmp       = types.MountPoint{SourceVolume: aws.String("agent-tmp"), ContainerPath: aws.String("/tmp"), ReadOnly: aws.Bool(false)}
	MountAgentRun       = types.MountPoint{SourceVolume: aws.String("agent-run"), ContainerPath: aws.String("/opt/datadog-agent/run"), ReadOnly: aws.Bool(false)}
	PortTCP             = types.PortMapping{ContainerPort: aws.Int32(8126), HostPort: aws.Int32(8126), Protocol: types.TransportProtocolTcp}
	PortUDP             = types.PortMapping{ContainerPort: aws.Int32(8125), HostPort: aws.Int32(8125), Protocol: types.TransportProtocolUdp}
	DependencyAgent     = types.ContainerDependency{ContainerName: aws.String("datadog-agent"), Condition: types.ContainerConditionHealthy}
	DependencyCWS       = types.ContainerDependency{ContainerName: aws.String("cws-instrumentation-init"), Condition: types.ContainerConditionSuccess}
	DependencyLogRouter = types.ContainerDependency{ContainerName: aws.String("datadog-log-router"), Condition: types.ContainerConditionHealthy}
)

// GetContainer retrieves a container definition by name
func GetContainer(containers []types.ContainerDefinition, name string) (types.ContainerDefinition, bool) {
	for _, container := range containers {
		if container.Name != nil && *container.Name == name {
			return container, true
		}
	}
	return types.ContainerDefinition{}, false
}

// GetEnvVar retrieves the value of an environment variable from a container definition
func GetEnvVar(container types.ContainerDefinition, name string) (string, bool) {
	for _, env := range container.Environment {
		if env.Name != nil && env.Value != nil && *env.Name == name {
			return *env.Value, true
		}
	}
	return "", false
}

// AssertEnvVars checks if the expected environment variables are all present in the container
func AssertEnvVars(t *testing.T, container types.ContainerDefinition, expectedEnvVars map[string]string) {
	assert.NotNil(t, container.Name, "Container name cannot be nil")

	for key, expectedValue := range expectedEnvVars {
		value, found := GetEnvVar(container, key)
		assert.True(t, found, "Environment variable %s not found in %s container", key, container.Name)
		assert.Equal(t, expectedValue, value, "Environment variable %s value does not match expected in %s container", key, container.Name)
	}
}

// AssertNotEnvVars checks that a container does NOT have the specified environment variables
func AssertNotEnvVars(t *testing.T, container types.ContainerDefinition, unexpectedEnvVars []string) {
	for _, unexpectedValue := range unexpectedEnvVars {
		_, found := GetEnvVar(container, unexpectedValue)
		assert.False(t, found, "Environment variable %s should not be present in %s container", unexpectedValue, *container.Name)
	}
}

// AssertPortMapping checks if an expected port mapping exists in the container
func AssertPortMapping(t *testing.T, container types.ContainerDefinition, expectedMapping types.PortMapping) {
	assert.NotNil(t, container.Name, "Container name cannot be nil")
	assert.NotNil(t, expectedMapping.ContainerPort, "Expected container port cannot be nil")
	assert.NotNil(t, expectedMapping.HostPort, "Expected host port cannot be nil")

	found := false
	for _, mapping := range container.PortMappings {
		if mapping.ContainerPort != nil && mapping.HostPort != nil &&
			*mapping.ContainerPort == *expectedMapping.ContainerPort &&
			*mapping.HostPort == *expectedMapping.HostPort &&
			mapping.Protocol == expectedMapping.Protocol {
			found = true
			break
		}
	}
	assert.True(t, found, "Expected port mapping (container:%d, host:%d, protocol:%s) not found in %s container",
		expectedMapping.ContainerPort, expectedMapping.HostPort, expectedMapping.Protocol, container.Name)
}

// AssertMountPoint checks if an expected mount point exists in the container
func AssertMountPoint(t *testing.T, container types.ContainerDefinition, expectedMount types.MountPoint) {
	assert.NotNil(t, expectedMount.SourceVolume, "Source volume cannot be nil")
	assert.NotNil(t, expectedMount.ContainerPath, "Container path cannot be nil")
	assert.NotNil(t, expectedMount.ReadOnly, "ReadOnly flag cannot be nil")

	found := false
	for _, mount := range container.MountPoints {
		if mount.SourceVolume != nil && mount.ContainerPath != nil && mount.ReadOnly != nil &&
			*mount.SourceVolume == *expectedMount.SourceVolume &&
			*mount.ContainerPath == *expectedMount.ContainerPath &&
			*mount.ReadOnly == *expectedMount.ReadOnly {
			found = true
			break
		}
	}
	assert.True(t, found, "Expected mount point (volume:%s, path:%s, readonly:%t) not found in %s container",
		*expectedMount.SourceVolume, *expectedMount.ContainerPath, *expectedMount.ReadOnly, *container.Name)
}

// AssertContainerDependency checks if an expected container dependency exists
func AssertContainerDependency(t *testing.T, container types.ContainerDefinition, expectedDependency types.ContainerDependency) {
	assert.NotNil(t, expectedDependency.ContainerName, "Dependency container name cannot be nil")

	found := false
	for _, dependency := range container.DependsOn {
		if dependency.ContainerName != nil &&
			*dependency.ContainerName == *expectedDependency.ContainerName &&
			dependency.Condition == expectedDependency.Condition {
			found = true
			break
		}
	}
	assert.True(t, found, "Expected dependency (container:%s, condition:%s) not found in %s container",
		*expectedDependency.ContainerName, expectedDependency.Condition, *container.Name)
}

// AssertDockerLabels checks if the expected docker labels are all present in the container
func AssertDockerLabels(t *testing.T, container types.ContainerDefinition, expectedLabels map[string]string) {
	assert.NotNil(t, container.Name, "Container name cannot be nil")

	for key, expectedValue := range expectedLabels {
		value, found := container.DockerLabels[key]
		assert.True(t, found, "Docker label %s not found in %s container", key, *container.Name)
		assert.Equal(t, expectedValue, value, "Docker label %s value does not match expected in %s container", key, *container.Name)
	}
}
