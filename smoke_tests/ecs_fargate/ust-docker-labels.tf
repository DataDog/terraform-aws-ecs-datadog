# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: UST Docker Labels Test
################################################################################

module "dd_task_ust_docker_labels" {
  source = "../../modules/ecs_fargate"

  # Configure Datadog with UST tags
  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  dd_service   = "ust-test-service"
  dd_env       = "ust-test-env"
  dd_version   = "1.2.3"
  dd_tags      = "team:test"
  dd_essential = true

  dd_is_datadog_dependency_enabled = true

  dd_log_collection = {
    enabled = true,
  }

  dd_cws = {
    enabled = true,
  }

  # Configure Task Definition with multiple containers
  family = "${var.test_prefix}-ust-docker-labels"
  container_definitions = jsonencode([
    {
      name      = "dummy-app",
      image     = "nginx:latest",
      essential = true,
    },
    {
      name      = "app-overwritten-ust",
      image     = "nginx:latest",
      essential = false,
      dockerLabels = {
        "com.datadoghq.tags.service" : "different_name",
        "custom.label" = "custom-value"
      }
    }
  ])

  requires_compatibilities = ["FARGATE"]
}
