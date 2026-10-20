# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Invalid Automatic APM Instrumentation
################################################################################

# Checks that the plan fails when `container_name` matches no application container
module "dd_task_apm_unknown_container" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language       = "python"
    container_name = "missing-app"
  }

  family = "${var.test_prefix}-apm-unknown-container"
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
    },
  ])
}

# Checks that the plan fails when several application containers and no `container_name` are set
module "dd_task_apm_ambiguous_container" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language = "python"
  }

  family = "${var.test_prefix}-apm-ambiguous-container"
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
    },
    {
      name      = "worker",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = false,
    },
  ])
}

# Checks that the plan fails when the container to instrument sets a tracer variable from `secrets`
module "dd_task_apm_secret_env" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language = "python"
  }

  family = "${var.test_prefix}-apm-secret-env"
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
      secrets = [
        {
          name      = "PYTHONPATH",
          valueFrom = "arn:aws:ssm:us-east-1:123456789012:parameter/pythonpath",
        },
      ],
    },
  ])
}

# Checks that the apply fails before it registers the task definition when the
# container definitions are unknown until apply
module "dd_task_apm_unknown_at_plan" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key

  dd_apm_instrumentation = {
    language       = "python"
    container_name = "missing-app"
  }

  family = "${var.test_prefix}-apm-unknown-at-plan"
  # Passing a task role keeps the apply from creating IAM resources before it fails.
  task_role = {
    arn                    = "arn:aws:iam::123456789012:role/unused"
    add_dd_ecs_permissions = false
  }
  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "public.ecr.aws/docker/library/python:3.12-slim",
      essential = true,
      environment = [
        {
          name = "DEPLOYED_AT",
          # timestamp() is unknown until apply.
          value = timestamp(),
        },
      ],
    },
  ])
}
