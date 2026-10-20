# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Python Automatic APM Instrumentation Example
################################################################################

module "datadog_ecs_fargate_task" {
  source = "../../modules/ecs_fargate"

  # Configure Datadog
  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site

  dd_service = var.dd_service
  dd_env     = var.dd_env
  dd_version = var.dd_version

  dd_apm_instrumentation = {
    language = "python"
  }

  dd_log_collection = {
    enabled = true,
    fluentbit_config = {
      log_driver_configuration = {
        service_name = var.dd_service
        source_name  = "python"
      }
    }
  }

  # Configure Task Definition
  family = var.task_family_name
  execution_role = {
    arn = aws_iam_role.task_execution.arn
  }
  container_definitions = jsonencode([
    {
      name      = "python-app",
      image     = var.image,
      essential = true,
      portMappings = [
        {
          containerPort = 8080,
          protocol      = "tcp",
        },
      ],
    },
  ])
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]
}

################################################################################
# Task Execution Role: Pulls the Application Image from Amazon ECR
################################################################################

resource "aws_iam_role" "task_execution" {
  name = "${var.task_family_name}-ecs-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
