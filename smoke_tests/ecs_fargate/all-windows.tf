# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Windows supported features
################################################################################

# Tests that the Datadog agent configuration on Windows is correct
# In particular, we are checking APM, Dogstatsd, and `ecs.fargate` metrics
module "dd_task_all_windows" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  dd_service = var.dd_service

  dd_readonly_root_filesystem = false

  dd_apm = {
    enabled = true
  }

  dd_dogstatsd = {
    enabled = true
  }

  family = "${var.test_prefix}-all-windows"
  container_definitions = jsonencode([
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "datadog-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = true,
    },
  ])
  cpu    = 1024
  memory = 2048
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "WINDOWS_SERVER_2022_CORE"
  }
}
