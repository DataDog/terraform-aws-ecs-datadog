# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Logging (from Agent)
################################################################################

module "dd_task_logging_only" {
  source = "../../modules/ecs_fargate"

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  dd_service   = var.dd_service
  dd_essential = true

  dd_dogstatsd = {
    enabled = false,
  }

  dd_apm = {
    enabled = false,
  }

  dd_log_collection = {
    enabled = true,
    fluentbit_config = {
      is_log_router_dependency_enabled = true,
    }
  }

  family                = "terraform-test-logging-only"
  container_definitions = jsonencode([])

  requires_compatibilities = ["FARGATE"]
}