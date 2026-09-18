# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Datadog Agent Outputs
################################################################################

output "datadog_agent_daemon_task_definition_arn" {
  description = "ARN of the Datadog Agent daemon task definition"
  value       = module.datadog_agent.arn
}

output "datadog_agent_daemon_arn" {
  description = "ARN of the Datadog Agent daemon"
  value       = module.datadog_agent.daemon_arn
}

################################################################################
# Cluster / Capacity Provider Outputs
################################################################################

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "capacity_provider_arn" {
  description = "ARN of the ECS Managed Instances capacity provider"
  value       = aws_ecs_capacity_provider.managed_instances.arn
}

################################################################################
# Application Outputs
################################################################################

output "dogstatsd_app_task_definition_arn" {
  description = "ARN of the example application task definition"
  value       = aws_ecs_task_definition.dogstatsd_app.arn
}
