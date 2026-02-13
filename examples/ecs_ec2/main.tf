# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Datadog Agent Daemon Service
################################################################################

module "datadog_agent" {
  source = "../../modules/ecs_ec2"

  # Datadog Configuration
  dd_api_key_secret = {
    arn = var.dd_api_key_secret_arn
  }
  dd_site         = var.dd_site
  dd_cluster_name = var.cluster_name

  # Enable all features
  dd_dogstatsd = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"
  }

  dd_apm = {
    enabled                       = true
    profiling                     = true
    trace_inferred_proxy_services = false
    data_streams                  = true
  }

  dd_log_collection = {
    enabled               = true
    container_collect_all = true
  }

  dd_orchestrator_explorer = {
    enabled = true
  }

  # Task Definition
  family       = "datadog-agent-daemon"
  network_mode = "bridge"

  # Daemon Service
  create_service = true
  cluster_arn    = var.cluster_arn
  service_name   = "datadog-agent"

  tags = var.tags
}

################################################################################
# Example Application Task
################################################################################

# IAM role for application task
resource "aws_iam_role" "app_task_role" {
  name = "${var.name_prefix}-app-task-role"

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

  tags = var.tags
}

# IAM role for application task execution
resource "aws_iam_role" "app_execution_role" {
  name = "${var.name_prefix}-app-execution-role"

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

  tags = var.tags
}

# Attach ECS task execution policy
resource "aws_iam_role_policy_attachment" "app_execution_role_policy" {
  role       = aws_iam_role.app_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch log group for application
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}-app"
  retention_in_days = 7

  tags = var.tags
}

# Application task definition
resource "aws_ecs_task_definition" "app" {
  family             = "${var.name_prefix}-app"
  network_mode       = "bridge"
  task_role_arn      = aws_iam_role.app_task_role.arn
  execution_role_arn = aws_iam_role.app_execution_role.arn

  container_definitions = jsonencode([{
    name      = "nginx"
    image     = "nginx:latest"
    essential = true

    # Use Datadog agent for monitoring via UDS
    # Combine all Datadog environment variables using module outputs
    environment = concat(
      module.datadog_agent.dogstatsd_env_vars,
      module.datadog_agent.apm_env_vars,
      [
        {
          name  = "DD_SERVICE"
          value = "example-app"
        },
        {
          name  = "DD_ENV"
          value = var.environment
        },
        {
          name  = "DD_VERSION"
          value = "1.0.0"
        }
      ]
    )

    # Mount the shared UDS socket volume for agent communication
    mountPoints = module.datadog_agent.app_dd_sockets_mount

    portMappings = [{
      containerPort = 80
      hostPort      = 0 # Dynamic port mapping
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "nginx"
      }
    }

    memory = 256
    cpu    = 256
  }])

  # Add the shared UDS socket volume for agent communication
  dynamic "volume" {
    for_each = module.datadog_agent.app_dd_sockets_volume

    content {
      name      = volume.value.name
      host_path = volume.value.host_path
    }
  }

  tags = var.tags
}

# Application ECS service
resource "aws_ecs_service" "app" {
  name            = "${var.name_prefix}-app"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_desired_count

  # Ensure Datadog agent daemon is deployed before application tasks
  depends_on = [module.datadog_agent]

  tags = var.tags
}
