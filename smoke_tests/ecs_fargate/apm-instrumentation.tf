# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Automatic APM Instrumentation
################################################################################

# Checks that the tracer is added to the selected application container only
# Verifies that existing tracer settings are extended instead of replaced
module "dd_task_apm_instrumentation" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  dd_service = var.dd_service

  dd_apm_instrumentation = {
    language       = "python"
    container_name = "datadog-apm-app"
  }

  family = "${var.test_prefix}-apm-instrumentation"
  container_definitions = jsonencode([
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "datadog-apm-app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
      environment = [
        {
          name  = "PYTHONPATH",
          value = "/app",
        },
        {
          name  = "DD_TAGS",
          value = "team:serverless",
        },
      ],
    },
  ])
  requires_compatibilities = ["FARGATE"]
}
