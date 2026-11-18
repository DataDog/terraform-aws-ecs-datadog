# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Skipped Automatic APM Instrumentation
################################################################################

# Checks that the tracer is skipped when LD_PRELOAD would exceed its byte limit
module "dd_task_apm_env_over_max_length" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language = "dotnet"
  }

  family = "${var.test_prefix}-apm-env-over-max-length"
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "mcr.microsoft.com/dotnet/aspnet:8.0",
      essential = true,
      environment = [
        {
          name = "LD_PRELOAD",
          # Under 1024 characters but over 1024 bytes once merged, so only a byte count exceeds the limit.
          value = "/${join("", [for i in range(600) : "é"])}.so",
        },
      ],
    },
  ])
}

# Checks that the tracer is skipped when the tracer volume name is taken
module "dd_task_apm_tracer_name_taken" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language = "python"
  }

  family = "${var.test_prefix}-apm-tracer-name-taken"
  volumes = [
    {
      name = "datadog-tracer"
    },
  ]
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
    },
  ])
}

# Checks that the tracer is skipped when the container to instrument mounts a volume at the tracer path
module "dd_task_apm_tracer_mount_taken" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language = "python"
  }

  family = "${var.test_prefix}-apm-tracer-mount-taken"
  volumes = [
    {
      name = "shared"
    },
  ]
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
      mountPoints = [
        {
          sourceVolume  = "shared",
          containerPath = "/datadog-lib",
          readOnly      = false,
        },
      ],
    },
  ])
}
