# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Test: Role ARN parsing with path
# This test verifies that the module correctly parses role names from ARNs
# that include paths (e.g., /my-path/role-name)
################################################################################

# Create IAM roles with paths to test the parsing logic
resource "aws_iam_role" "test_task_role_with_path" {
  name = "${var.test_prefix}-task-role-with-path"
  path = "/test-path/"

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

resource "aws_iam_role" "test_execution_role_with_path" {
  name = "${var.test_prefix}-execution-role-with-path"
  path = "/test-execution-path/"

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

# Attach required policies to execution role
resource "aws_iam_role_policy_attachment" "test_execution_role_policy" {
  role       = aws_iam_role.test_execution_role_with_path.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

module "dd_task_role_parsing_with_path" {
  source = "../../modules/ecs_fargate"

  # Use roles with paths to test parsing
  task_role      = aws_iam_role.test_task_role_with_path
  execution_role = aws_iam_role.test_execution_role_with_path

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  dd_service   = var.dd_service
  dd_essential = true

  # Configure Task Definition
  family = "${var.test_prefix}-role-parsing-with-path"
  container_definitions = jsonencode([
    {
      name      = "test-app",
      image     = "nginx:latest",
      essential = true,
    }
  ])

  requires_compatibilities = ["FARGATE"]
}
