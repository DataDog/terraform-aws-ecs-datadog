# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# ECS Daemon Service
################################################################################

locals {
  # Service name defaults to <family>-datadog-agent if not provided
  service_name = var.service_name != null ? var.service_name : "${var.family}-datadog-agent"
}

resource "aws_ecs_service" "datadog_agent" {
  count = var.create_service ? 1 : 0

  name    = local.service_name
  cluster = var.cluster_arn

  # Use latest task definition revision
  task_definition = aws_ecs_task_definition.datadog_agent.arn

  # Daemon scheduling strategy - one agent per EC2 instance
  launch_type         = "EC2"
  scheduling_strategy = "DAEMON"

  # Placement constraints
  dynamic "placement_constraints" {
    for_each = var.service_placement_constraints

    content {
      type       = placement_constraints.value.type
      expression = try(placement_constraints.value.expression, null)
    }
  }

  # Service discovery
  dynamic "service_registries" {
    for_each = var.service_registries != null ? [var.service_registries] : []

    content {
      registry_arn   = service_registries.value.registry_arn
      container_name = try(service_registries.value.container_name, "datadog-agent")
      container_port = try(service_registries.value.container_port, null)
    }
  }

  # ECS managed tags and propagation
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  propagate_tags          = var.propagate_tags

  tags = merge(var.tags, local.tags)

  # Ensure task definition is created before service
  depends_on = [
    aws_ecs_task_definition.datadog_agent
  ]
}
