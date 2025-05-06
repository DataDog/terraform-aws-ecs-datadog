// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package test

import (
	"log"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestAllECSInputs tests that the ECS task definition attributes are properly set
func (s *ECSFargateSuite) TestAllECSInputs() {
	log.Println("TestAllECSInputs: Running test...")

	// Retrieve the task output for the "all-ecs-inputs" module
	task := terraform.OutputMap(s.T(), s.terraformOptions, "all-ecs-inputs")

	s.Equal("terraform-test-all-ecs-inputs", task["family"], "Unexpected task family name")
	s.Equal("256", task["cpu"], "Unexpected CPU value")
	s.Equal("512", task["memory"], "Unexpected memory value")
	s.Equal("awsvpc", task["network_mode"], "Unexpected network mode")
	s.Equal("task", task["pid_mode"], "Unexpected PID mode")

	s.Contains(task["ephemeral_storage"], "size_in_gib:40", "Unexpected ephemeral storage size")

	s.Contains(task["runtime_platform"], "cpu_architecture:X86_64", "Unexpected CPU architecture")
	s.Contains(task["runtime_platform"], "operating_system_family:LINUX", "Unexpected OS family")

	s.Contains(task["proxy_configuration"], "type:APPMESH", "Unexpected proxy configuration type")
	s.Contains(task["proxy_configuration"], "container_name:datadog-dummy-app", "Unexpected proxy container name")
	s.Contains(task["proxy_configuration"], "ProxyIngressPort:15000", "Unexpected proxy ingress port")
	s.Contains(task["proxy_configuration"], "AppPorts:8080", "Unexpected app ports")
	s.Contains(task["proxy_configuration"], "EgressIgnoredIPs:", "Unexpected egress ignored IPs")
	s.Contains(task["proxy_configuration"], "IgnoredUID:1337", "Unexpected ignored UID")
	s.Contains(task["proxy_configuration"], "ProxyEgressPort:15001", "Unexpected proxy egress port")

	s.Contains(task["volume"], "efs-storage", "Unexpected volume name")
	s.Contains(task["volume"], "access_point_id:fsap-", "Unexpected EFS access point ID")
	s.Contains(task["volume"], "iam:ENABLED", "Unexpected EFS IAM setting")
	s.Contains(task["volume"], "root_directory:/", "Unexpected EFS root directory")

	s.Contains(task["volume"], "docker-storage", "Unexpected volume name")
	s.Contains(task["volume"], "dd-sockets", "Unexpected volume name")

	s.Contains(task["requires_compatibilities"], "FARGATE", "Unexpected compatibility setting")
}
