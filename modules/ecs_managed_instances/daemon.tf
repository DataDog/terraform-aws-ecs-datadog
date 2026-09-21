# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# ECS Managed Daemon
################################################################################
# ECS Managed Daemons only run on ECS Managed Instances capacity providers.
# This module does not create the cluster or capacity provider - both must be
# supplied by the caller, the same boundary ecs_ec2 uses for cluster_arn.

locals {
  # Daemon name defaults to <family>-datadog-agent if not provided
  daemon_name = var.daemon_name != null ? var.daemon_name : "${var.family}-datadog-agent"
}

resource "aws_ecs_daemon" "datadog_agent" {
  count = var.create_daemon ? 1 : 0

  name                       = local.daemon_name
  cluster_arn                = var.cluster_arn
  daemon_task_definition_arn = aws_ecs_daemon_task_definition.datadog_agent.arn

  # ECS Managed Daemons are only supported on ECS Managed Instances capacity providers
  capacity_provider_arns = var.capacity_provider_arns

  # Write-only: the API does not return these values, so Terraform plans will
  # always show a diff here. This is expected provider behavior, not a bug.
  deployment_configuration {
    drain_percent        = var.deployment_configuration.drain_percent
    bake_time_in_minutes = var.deployment_configuration.bake_time_in_minutes

    alarms {
      alarm_names = var.deployment_configuration.alarms.alarm_names
      enable      = var.deployment_configuration.alarms.enable
    }
  }

  # Write-only and ignored by the provider on update - changing these after
  # creation has no effect until the daemon is recreated.
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  enable_execute_command  = var.enable_execute_command
  propagate_tags          = var.propagate_tags

  tags = merge(var.tags, local.tags)

  lifecycle {
    precondition {
      condition     = var.create_daemon == false || var.cluster_arn != null
      error_message = "cluster_arn must be provided when create_daemon is true."
    }

    precondition {
      condition     = var.create_daemon == false || length(var.capacity_provider_arns) > 0
      error_message = "capacity_provider_arns must contain at least one ARN when create_daemon is true. ECS Managed Daemons only run on ECS Managed Instances capacity providers."
    }
  }

  depends_on = [
    aws_ecs_daemon_task_definition.datadog_agent
  ]
}
