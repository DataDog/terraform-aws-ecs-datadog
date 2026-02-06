# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition
################################################################################

resource "aws_ecs_task_definition" "datadog_agent" {
  family = var.family

  container_definitions = jsonencode(local.dd_agent_container)

  # EC2 launch type
  requires_compatibilities = ["EC2"]

  # Network configuration
  network_mode = var.network_mode
  ipc_mode     = var.ipc_mode
  pid_mode     = var.pid_mode

  # IAM roles - prioritize user-provided over module-created
  execution_role_arn = try(
    var.execution_role.arn,
    aws_iam_role.new_ecs_task_execution_role[0].arn,
    null
  )

  task_role_arn = try(
    var.task_role.arn,
    aws_iam_role.new_ecs_task_role[0].arn,
    null
  )

  # Placement constraints
  dynamic "placement_constraints" {
    for_each = var.placement_constraints != null ? var.placement_constraints : []

    content {
      expression = try(placement_constraints.value.expression, null)
      type       = placement_constraints.value.type
    }
  }

  # Proxy configuration
  dynamic "proxy_configuration" {
    for_each = var.proxy_configuration != null ? [var.proxy_configuration] : []

    content {
      container_name = proxy_configuration.value.container_name
      properties     = try(proxy_configuration.value.properties, null)
      type           = try(proxy_configuration.value.type, null)
    }
  }

  # Volumes - includes Datadog host volumes and user-provided volumes
  dynamic "volume" {
    for_each = local.all_volumes

    content {
      name      = volume.value.name
      host_path = try(volume.value.host_path, null)

      dynamic "docker_volume_configuration" {
        for_each = try(volume.value.docker_volume_configuration != null ? [volume.value.docker_volume_configuration] : [], [])

        content {
          autoprovision = try(docker_volume_configuration.value.autoprovision, null)
          driver        = try(docker_volume_configuration.value.driver, null)
          driver_opts   = try(docker_volume_configuration.value.driver_opts, null)
          labels        = try(docker_volume_configuration.value.labels, null)
          scope         = try(docker_volume_configuration.value.scope, null)
        }
      }

      dynamic "efs_volume_configuration" {
        for_each = try(volume.value.efs_volume_configuration != null ? [volume.value.efs_volume_configuration] : [], [])

        content {
          dynamic "authorization_config" {
            for_each = try(efs_volume_configuration.value.authorization_config != null ? [efs_volume_configuration.value.authorization_config] : [], [])

            content {
              access_point_id = try(authorization_config.value.access_point_id, null)
              iam             = try(authorization_config.value.iam, null)
            }
          }

          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = try(efs_volume_configuration.value.root_directory, null)
          transit_encryption      = try(efs_volume_configuration.value.transit_encryption, null)
          transit_encryption_port = try(efs_volume_configuration.value.transit_encryption_port, null)
        }
      }
    }
  }

  skip_destroy = var.skip_destroy
  track_latest = var.track_latest
  tags         = merge(var.tags, local.tags)

  # Ensure IAM roles are created before task definition
  depends_on = [
    aws_iam_role.new_ecs_task_role,
    aws_iam_role.new_ecs_task_execution_role,
  ]

  lifecycle {
    create_before_destroy = true

    # Must provide exactly one of the two Datadog API key options
    precondition {
      condition     = (var.dd_api_key == null && var.dd_api_key_secret != null) || (var.dd_api_key != null && var.dd_api_key_secret == null)
      error_message = "You must provide exactly one of the two Datadog API key options: 'dd_api_key' or 'dd_api_key_secret'."
    }

    # Validate cluster_arn is provided when service creation is enabled
    precondition {
      condition     = var.create_service == false || (var.create_service == true && var.cluster_arn != null)
      error_message = "cluster_arn must be provided when create_service is true."
    }
  }
}
