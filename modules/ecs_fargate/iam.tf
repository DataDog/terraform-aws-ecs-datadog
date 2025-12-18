# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# ==============================
# Task Execution Role
# ==============================

# Will create or edit the *task execution role*
# only if the user provides a Datadog API key secret ARN
# in order to provide permissions to access the secret

locals {
  create_dd_secret_perms = var.dd_api_key_secret != null && var.dd_manage_execution_role_secret_permissions
  edit_execution_role    = var.execution_role != null && local.create_dd_secret_perms
  create_execution_role  = var.execution_role == null && local.create_dd_secret_perms
  parsed_exec_role_name  = var.execution_role == null ? null : split("/", var.execution_role.arn)[length(split("/", var.execution_role.arn)) - 1]
}

# ==============================
# Datadog API Key Secret Policy (Optional)
# ==============================
data "aws_iam_policy_document" "dd_secret_access" {
  count = local.create_dd_secret_perms ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.dd_api_key_secret.arn]
  }
}

resource "aws_iam_policy" "dd_secret_access" {
  count  = local.create_dd_secret_perms ? 1 : 0
  name   = "${var.family}-dd-secret-access"
  policy = data.aws_iam_policy_document.dd_secret_access[0].json
}

# ==============================
# Case 1: User provides existing Task Execution Role
# ==============================
resource "aws_iam_role_policy_attachment" "existing_role_dd_secret" {
  count      = local.edit_execution_role ? 1 : 0
  role       = local.parsed_exec_role_name
  policy_arn = aws_iam_policy.dd_secret_access[0].arn
}

# ==============================
# Case 2: Create a Task Execution Role
# ==============================
resource "aws_iam_role" "new_ecs_task_execution_role" {
  count = local.create_execution_role ? 1 : 0
  name  = "${var.family}-ecs-task-exec-role"

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

locals {
  new_execution_role_policy_map = merge(
    { "AmazonECSTaskExecutionRolePolicy" = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" },
    local.create_dd_secret_perms ? { "DDSecretAccess" = aws_iam_policy.dd_secret_access[0].arn } : {}
  )
}

resource "aws_iam_role_policy_attachment" "new_ecs_task_execution_role_policy" {
  for_each   = local.create_execution_role ? local.new_execution_role_policy_map : {}
  role       = aws_iam_role.new_ecs_task_execution_role[0].name
  policy_arn = each.value
}

# ==============================
# Task Role
# ==============================

# Will create or edit the *task role* always
# in order to add permissions for the ecs_fargate check

locals {
  edit_task_role        = var.task_role != null && var.dd_manage_task_role_permissions
  create_task_role      = var.task_role == null
  parsed_task_role_name = var.task_role == null ? null : split("/", var.task_role.arn)[length(split("/", var.task_role.arn)) - 1]
}

# ==============================
# ECS Task Permissions Policy
# ==============================
data "aws_iam_policy_document" "dd_ecs_task_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:ListClusters",
      "ecs:ListContainerInstances",
      "ecs:DescribeContainerInstances"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "dd_ecs_task_permissions" {
  name   = "${var.family}-dd-ecs-task-policy"
  policy = data.aws_iam_policy_document.dd_ecs_task_permissions.json
}

# ==============================
# Case 1: User provides existing Task Role
# ==============================
# Always attach `dd_ecs_task_permissions`
resource "aws_iam_role_policy_attachment" "existing_role_ecs_task_permissions" {
  count      = local.edit_task_role ? 1 : 0
  role       = local.parsed_task_role_name
  policy_arn = aws_iam_policy.dd_ecs_task_permissions.arn
}


# ==============================
# Case 2: Create a Task Role
# ==============================

resource "aws_iam_role" "new_ecs_task_role" {
  count = local.create_task_role ? 1 : 0
  name  = "${var.family}-ecs-task-role"

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

# Always attach `dd_ecs_task_permissions`
locals {
  new_task_role_policy_map = {
    "DDECSTaskPermissions" = aws_iam_policy.dd_ecs_task_permissions.arn
  }
}

resource "aws_iam_role_policy_attachment" "new_role_ecs_task_permissions" {
  for_each   = local.create_task_role ? local.new_task_role_policy_map : {}
  role       = aws_iam_role.new_ecs_task_role[0].name
  policy_arn = each.value
}
