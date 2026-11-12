# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Log configuration for module-managed containers
################################################################################

# `dd_log_collection` is disabled here — the caller runs its own log router —
# so the containers this module creates would otherwise be registered with no
# log driver. `dd_log_configuration` covers them, which keeps the task
# definition passing AWS FSBP control ECS.9 and keeps the Agent's own output
# reachable. Read-only root filesystem is on so the `init-volume` container is
# part of the task definition too.

module "dd_task_managed_container_logging" {
  source = "../../modules/ecs_fargate"

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  dd_service   = var.dd_service
  dd_essential = true

  dd_readonly_root_filesystem = true

  dd_log_collection = {
    enabled = false
  }

  dd_log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = "/ecs/${var.test_prefix}-managed-container-logging"
      awslogs-region        = "us-east-1"
      awslogs-stream-prefix = "datadog"
    }
  }

  family = "${var.test_prefix}-managed-container-logging"
  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "public.ecr.aws/docker/library/busybox:latest"
      essential = true
      command   = ["sh", "-c", "sleep infinity"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.test_prefix}-managed-container-logging"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])

  cpu    = 256
  memory = 512
}
