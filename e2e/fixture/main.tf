# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

provider "aws" {
  region = var.region
}

locals {
  run_id_tag = "one_e2e_run_id:${var.run_id}"

  # The e2e role can't change IAM, so the module must not attach policies.
  execution_role = {
    arn                    = var.execution_role_arn
    add_dd_ecs_permissions = false
  }
  task_role = {
    arn                    = var.task_role_arn
    add_dd_ecs_permissions = false
  }
}

module "service" {
  source = "../../modules/ecs_fargate"

  dd_api_key_secret = { arn = var.dd_api_key_secret_arn }
  dd_site           = var.dd_site
  dd_service        = var.name
  dd_env            = var.dd_env
  dd_version        = var.dd_version
  dd_tags           = "env:${var.dd_env},version:${var.dd_version},${local.run_id_tag}"
  dd_image_version  = var.agent_image_version

  dd_apm_instrumentation = {
    language = var.service_language
  }

  dd_log_collection = {
    enabled = true
    fluentbit_config = {
      log_driver_configuration = {
        host_endpoint = "http-intake.logs.${var.dd_site}"
        tls           = true
        service_name  = var.name
      }
    }
  }

  family         = var.name
  cpu            = 512
  memory         = 1024
  execution_role = local.execution_role
  task_role      = local.task_role
  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.service_image
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      # The injected tracer adds the run ID to every span.
      environment = [{ name = "DD_TAGS", value = local.run_id_tag }]
    },
  ])
  tags = var.tags
}

# Registered and verified, never run.
module "language" {
  for_each = var.language_images
  source   = "../../modules/ecs_fargate"

  dd_api_key_secret = { arn = var.dd_api_key_secret_arn }
  dd_site           = var.dd_site
  dd_service        = "${var.name}-${each.key}"
  dd_env            = var.dd_env
  dd_version        = var.dd_version
  dd_image_version  = var.agent_image_version

  dd_apm_instrumentation = {
    language = each.key
  }

  family         = "${var.name}-${each.key}"
  execution_role = local.execution_role
  task_role      = local.task_role
  container_definitions = jsonencode([
    {
      name         = "app"
      image        = each.value
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      # Without log collection, the tracer container reuses this configuration.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group
          awslogs-region        = var.region
          awslogs-stream-prefix = "${var.name}-${each.key}"
        }
      }
    },
  ])
  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name                  = var.name
  cluster               = var.cluster
  task_definition       = module.service.arn
  desired_count         = 1
  launch_type           = "FARGATE"
  wait_for_steady_state = true

  # The suite sends traffic to the task's public IP address.
  network_configuration {
    subnets          = var.subnets
    security_groups  = [var.security_group]
    assign_public_ip = true
  }

  # Stops replacing a task that can't start.
  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  tags = var.tags

  timeouts {
    create = "10m"
  }
}
