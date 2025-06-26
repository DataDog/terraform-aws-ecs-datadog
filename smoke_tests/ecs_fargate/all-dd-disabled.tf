# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Datadog Features Disabled
################################################################################

# Verifies that no Datadog features are configured on the task definition
module "dd_task_all_dd_disabled" {
  source = "../../modules/ecs_fargate"

  dd_api_key                       = var.dd_api_key
  dd_site                          = var.dd_site
  dd_service                       = var.dd_service
  dd_tags                          = "team:cont-p, owner:container-monitoring"
  dd_essential                     = true
  dd_is_datadog_dependency_enabled = false

  dd_environment = []

  dd_dogstatsd = {
    enabled = false
  }

  dd_apm = {
    enabled = false,
  }

  dd_log_collection = {
    enabled = false,
  }

  dd_cws = {
    enabled = false,
  }

  family = "${var.test_prefix}-all-dd-disabled"
  container_definitions = jsonencode([
    {
      name : "dummy-container",
      image : "ubuntu:latest",
      essential : true,
      command : ["sleep", "infinity"]
    }
  ])

  requires_compatibilities = ["FARGATE"]
}
