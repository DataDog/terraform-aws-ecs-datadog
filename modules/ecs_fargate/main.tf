# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition
################################################################################

resource "aws_ecs_task_definition" "this" {

  container_definitions = jsonencode(
    concat(
      local.dd_agent_container,
      local.dd_log_container,
      local.dd_cws_container,
      [for k, v in local.modified_container_definitions : v],
    )
  )

  cpu = var.cpu

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage != null ? [var.ephemeral_storage] : []

    content {
      size_in_gib = ephemeral_storage.value.size_in_gib
    }
  }

  enable_fault_injection = var.enable_fault_injection

  # Prioritize the user-provided task execution role over the one created by the module
  execution_role_arn = try(
    var.execution_role.arn,
    aws_iam_role.new_ecs_task_execution_role[0].arn,
    null
  )

  family = var.family

  # Fargate incompatible parameter
  dynamic "inference_accelerator" {
    for_each = var.inference_accelerator != null ? var.inference_accelerator : []

    content {
      device_name = inference_accelerator.value.device_name
      device_type = inference_accelerator.value.device_type
    }
  }

  # Fargate incompatible parameter
  ipc_mode     = var.ipc_mode
  memory       = var.memory
  network_mode = var.network_mode
  pid_mode     = var.pid_mode

  dynamic "placement_constraints" {
    for_each = var.placement_constraints != null ? var.placement_constraints : []

    content {
      expression = try(placement_constraints.value.expression, null)
      type       = placement_constraints.value.type
    }
  }

  dynamic "proxy_configuration" {
    for_each = var.proxy_configuration != null ? [var.proxy_configuration] : []

    content {
      container_name = proxy_configuration.value.container_name
      properties     = try(proxy_configuration.value.properties, null)
      type           = try(proxy_configuration.value.type, null)
    }
  }

  requires_compatibilities = var.requires_compatibilities

  dynamic "runtime_platform" {
    for_each = var.runtime_platform != null ? [var.runtime_platform] : []

    content {
      cpu_architecture        = try(runtime_platform.value.cpu_architecture, null)
      operating_system_family = try(runtime_platform.value.operating_system_family, null)
    }
  }

  skip_destroy = var.skip_destroy
  # Prioritize the user-provided task role over the one created by the module
  task_role_arn = try(
    var.task_role.arn,
    aws_iam_role.new_ecs_task_role[0].arn,
    null
  )

  dynamic "volume" {
    for_each = local.modified_volumes

    content {
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

      dynamic "fsx_windows_file_server_volume_configuration" {
        for_each = try(volume.value.fsx_windows_file_server_volume_configuration != null ? [volume.value.fsx_windows_file_server_volume_configuration] : [], [])

        content {
          dynamic "authorization_config" {
            for_each = try(fsx_windows_file_server_volume_configuration.value.authorization_config != null ? [fsx_windows_file_server_volume_configuration.value.authorization_config] : [], [])

            content {
              credentials_parameter = authorization_config.value.credentials_parameter
              domain                = authorization_config.value.domain
            }
          }

          file_system_id = fsx_windows_file_server_volume_configuration.value.file_system_id
          root_directory = fsx_windows_file_server_volume_configuration.value.root_directory
        }
      }

      host_path           = try(volume.value.host_path, null)
      configure_at_launch = try(volume.value.configure_at_launch, null)
      name                = try(volume.value.name, volume.key)
    }
  }

  tags = merge(
    var.tags,
    local.tags,
  )

  depends_on = [
    data.aws_iam_role.ecs_task_role,
    data.aws_iam_role.ecs_task_exec_role,
    aws_iam_role.new_ecs_task_role,
    aws_iam_role.new_ecs_task_execution_role,
  ]

  lifecycle {
    create_before_destroy = true

    # Attach any complex Datadog configuration rules (multiple variables)
    precondition {
      condition     = var.dd_cws.enabled == false || (var.dd_cws.enabled == true && var.dd_is_datadog_dependency_enabled == true)
      error_message = "The Datadog Agent container dependency must be enabled for CWS to be stable. Please set `dd_is_datadog_dependency_enabled` to `true`."
    }
    precondition {
      condition     = var.dd_log_collection.enabled == false || (var.dd_log_collection.enabled == true && local.is_linux == true)
      error_message = "Log collection is not supported on Windows. Please set `dd_log_collection.enabled` to `false`."
    }
    # Must provide only one of the two Datadog API key options
    precondition {
      condition     = (var.dd_api_key == null && var.dd_api_key_secret != null) || (var.dd_api_key != null && var.dd_api_key_secret == null)
      error_message = "You must provide only one of the two Datadog API key options: `dd_api_key` or `dd_api_key_secret`."
    }
  }
}