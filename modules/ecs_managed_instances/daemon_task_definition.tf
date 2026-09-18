# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Daemon Task Definition
################################################################################
# aws_ecs_daemon_task_definition has a materially different schema from
# aws_ecs_task_definition: no network_mode/pid_mode/ipc_mode/runtime_platform/
# placement_constraints/proxy_configuration/requires_compatibilities, container
# definitions are native HCL blocks rather than a jsonencode'd list, and every
# field forces full resource replacement (there is no update API for this
# resource at all).

resource "aws_ecs_daemon_task_definition" "datadog_agent" {
  family = var.family
  cpu    = var.cpu
  memory = var.memory

  container_definition {
    name      = local.dd_agent_container_definition.name
    image     = local.dd_agent_container_definition.image
    essential = local.dd_agent_container_definition.essential
    cpu       = local.dd_agent_container_definition.cpu
    memory    = local.dd_agent_container_definition.memory

    dynamic "environment" {
      # tolist() coerces the for-expression's inferred tuple type to a
      # homogeneous list - the environment block's Set-based schema rejects
      # a bare tuple with "Cannot use a tuple value in for_each."
      for_each = toset(local.dd_agent_container_definition.environment)

      content {
        name  = environment.value.name
        value = environment.value.value
      }
    }

    dynamic "mount_point" {
      for_each = local.dd_agent_container_definition.mount_point

      content {
        source_volume  = mount_point.value.source_volume
        container_path = mount_point.value.container_path
        read_only      = mount_point.value.read_only
      }
    }

    dynamic "secret" {
      for_each = try(local.dd_agent_container_definition.secret, [])

      content {
        name       = secret.value.name
        value_from = secret.value.value_from
      }
    }

    dynamic "health_check" {
      for_each = try(local.dd_agent_container_definition.health_check, null) != null ? [local.dd_agent_container_definition.health_check] : []

      content {
        command      = health_check.value.command
        interval     = health_check.value.interval
        retries      = health_check.value.retries
        start_period = health_check.value.start_period
        timeout      = health_check.value.timeout
      }
    }

    dynamic "linux_parameters" {
      for_each = try(local.dd_agent_container_definition.linux_parameters, null) != null ? [local.dd_agent_container_definition.linux_parameters] : []

      content {
        capabilities {
          add  = linux_parameters.value.capabilities.add
          drop = linux_parameters.value.capabilities.drop
        }
      }
    }

    dynamic "log_configuration" {
      for_each = try(local.dd_agent_container_definition.log_configuration, null) != null ? [local.dd_agent_container_definition.log_configuration] : []

      content {
        log_driver = log_configuration.value.log_driver
        options    = log_configuration.value.options

        dynamic "secret_option" {
          for_each = coalesce(log_configuration.value.secret_option, [])

          content {
            name       = secret_option.value.name
            value_from = secret_option.value.value_from
          }
        }
      }
    }
  }

  # Volumes - includes Datadog host volumes (CRI socket, proc, cgroup, UDS
  # sockets, network monitoring debug mount) and user-provided volumes
  dynamic "volume" {
    for_each = local.all_volumes

    content {
      name = volume.value.name

      dynamic "host" {
        for_each = try(volume.value.host_path, null) != null ? [volume.value.host_path] : []

        content {
          source_path = host.value
        }
      }
    }
  }

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

  tags = merge(var.tags, local.tags)

  # Ensure IAM roles are created before the daemon task definition
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

    # Container log collection through the agent is not supported in daemon
    # mode on ECS Managed Instances.
    precondition {
      condition     = var.dd_log_collection.enabled == false
      error_message = "Container log collection through the Datadog Agent is not supported in daemon mode on ECS Managed Instances. Use the FireLens log driver or the 'awslogs' driver configured directly on your application task definition instead."
    }

    # DogStatsD must have at least one transport configured when enabled
    precondition {
      condition     = !var.dd_dogstatsd.enabled || var.dd_dogstatsd.socket_enabled || var.dd_dogstatsd.tcp_enabled
      error_message = "DogStatsD is enabled but neither UDS (socket_enabled) nor TCP (tcp_enabled) transport is configured. Set at least one to true."
    }

    # APM must have at least one transport configured when enabled
    precondition {
      condition     = !var.dd_apm.enabled || var.dd_apm.socket_enabled || var.dd_apm.tcp_enabled
      error_message = "APM is enabled but neither UDS (socket_enabled) nor TCP (tcp_enabled) transport is configured. Set at least one to true."
    }
  }
}
