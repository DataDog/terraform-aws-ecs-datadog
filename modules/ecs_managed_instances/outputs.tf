# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Daemon Task Definition Outputs
################################################################################

output "arn" {
  description = "Full ARN of the Daemon Task Definition (including both family and revision)."
  value       = aws_ecs_daemon_task_definition.datadog_agent.arn
}

output "family" {
  description = "A unique name for your daemon task definition."
  value       = aws_ecs_daemon_task_definition.datadog_agent.family
}

output "revision" {
  description = "Revision of the daemon task definition in a particular family."
  value       = aws_ecs_daemon_task_definition.datadog_agent.revision
}

output "task_role_arn" {
  description = "ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services."
  value       = aws_ecs_daemon_task_definition.datadog_agent.task_role_arn
}

output "execution_role_arn" {
  description = "ARN of the task execution role."
  value       = aws_ecs_daemon_task_definition.datadog_agent.execution_role_arn
}

output "tags" {
  description = "Key-value map of resource tags."
  value       = aws_ecs_daemon_task_definition.datadog_agent.tags
}

output "tags_all" {
  description = "Map of tags assigned to the resource, including inherited tags."
  value       = aws_ecs_daemon_task_definition.datadog_agent.tags_all
}

output "container_definition" {
  description = "JSON-encoded representation of the Datadog Agent container definition, provided for testing/inspection convenience since aws_ecs_daemon_task_definition has no native container_definitions JSON attribute."
  value       = jsonencode(local.dd_agent_container_definition)
  # Transitively includes DD_API_KEY when var.dd_api_key (sensitive) is used,
  # so Terraform requires this output itself to be marked sensitive.
  sensitive = true
}

################################################################################
# Daemon Outputs (Conditional)
################################################################################

output "daemon_arn" {
  description = "ARN of the daemon. Only available if create_daemon = true."
  value       = try(aws_ecs_daemon.datadog_agent[0].arn, null)
}

output "daemon_deployment_arn" {
  description = "ARN of the daemon's latest deployment. Only available if create_daemon = true."
  value       = try(aws_ecs_daemon.datadog_agent[0].deployment_arn, null)
}

output "daemon_status" {
  description = "Status of the daemon (ACTIVE or DELETE_IN_PROGRESS). Only available if create_daemon = true."
  value       = try(aws_ecs_daemon.datadog_agent[0].status, null)
}

################################################################################
# Helper Outputs for User Tasks
################################################################################

output "app_dd_sockets_volume" {
  description = "Volume definition for the shared UDS socket directory. Add this to your application task definition's volumes to enable UDS communication with the Datadog Agent daemon."
  value = {
    name      = "dd-sockets"
    host_path = "/var/run/datadog"
  }
}

output "app_dd_sockets_mount" {
  description = "Mount point for the shared UDS socket directory. Add this to your application container's mountPoints to enable communication with the Datadog Agent daemon over Unix Domain Sockets."
  value = {
    sourceVolume  = "dd-sockets"
    containerPath = "/var/run/datadog"
    readOnly      = true
  }
}

output "dogstatsd_env_vars" {
  description = "Environment variables for DogStatsD in user application containers. When UDS is enabled (dd_dogstatsd.socket_enabled), provides DD_DOGSTATSD_URL pointing to the Unix socket. Otherwise, when TCP is enabled (dd_dogstatsd.tcp_enabled), provides DD_DOGSTATSD_URL pointing to the daemon bridge IP. Empty when DogStatsD is disabled."
  value = !var.dd_dogstatsd.enabled ? [] : (
    var.dd_dogstatsd.socket_enabled ? [
      {
        name  = "DD_DOGSTATSD_URL"
        value = "unix:///var/run/datadog/dsd.socket"
      }
      ] : var.dd_dogstatsd.tcp_enabled ? [
      {
        name  = "DD_DOGSTATSD_URL"
        value = "udp://${local.daemon_bridge_ipv4}:8125"
      }
    ] : []
  )
}

output "apm_env_vars" {
  description = "Environment variables for APM in user application containers. When UDS is enabled (dd_apm.socket_enabled), provides DD_TRACE_AGENT_URL pointing to the Unix socket. Otherwise, when TCP is enabled (dd_apm.tcp_enabled), provides DD_TRACE_AGENT_URL pointing to the daemon bridge IP. Empty when APM is disabled."
  value = !var.dd_apm.enabled ? [] : (
    var.dd_apm.socket_enabled ? [
      {
        name  = "DD_TRACE_AGENT_URL"
        value = "unix:///var/run/datadog/apm.socket"
      }
      ] : var.dd_apm.tcp_enabled ? [
      {
        name  = "DD_TRACE_AGENT_URL"
        value = "http://${local.daemon_bridge_ipv4}:8126"
      }
    ] : []
  )
}

output "data_streams_env_vars" {
  description = "Environment variables for Data Streams Monitoring in user application containers. Only includes values when enabled."
  value = var.dd_apm.data_streams ? [
    {
      name  = "DD_DATA_STREAMS_ENABLED"
      value = "true"
    }
  ] : []
}

output "profiling_env_vars" {
  description = "Environment variables for continuous profiling in user application containers. Only includes values when enabled."
  value = var.dd_apm.profiling ? [
    {
      name  = "DD_PROFILING_ENABLED"
      value = "true"
    }
  ] : []
}

output "trace_inferred_proxy_env_vars" {
  description = "Environment variables for trace inferred proxy services in user application containers. Only includes values when enabled."
  value = var.dd_apm.trace_inferred_proxy_services ? [
    {
      name  = "DD_TRACE_INFERRED_PROXY_SERVICES_ENABLED"
      value = "true"
    }
  ] : []
}
