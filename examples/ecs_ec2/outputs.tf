# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Datadog Agent Outputs
################################################################################

output "datadog_agent_task_definition_arn" {
  description = "ARN of the Datadog Agent task definition"
  value       = module.datadog_agent.arn
}

output "datadog_agent_service_name" {
  description = "Name of the Datadog Agent daemon service"
  value       = module.datadog_agent.service_name
}

output "datadog_agent_task_role_arn" {
  description = "ARN of the Datadog Agent task role"
  value       = module.datadog_agent.task_role_arn
}

################################################################################
# Application Outputs
################################################################################

output "app_task_definition_arn" {
  description = "ARN of the application task definition"
  value       = aws_ecs_task_definition.app.arn
}

output "app_service_name" {
  description = "Name of the application ECS service"
  value       = aws_ecs_service.app.name
}

################################################################################
# Helper Outputs
################################################################################

output "dd_agent_env_vars_example" {
  description = "Example of Datadog agent environment variables for user tasks"
  value = {
    dogstatsd = module.datadog_agent.dogstatsd_env_vars
    apm       = module.datadog_agent.apm_env_vars
  }
}
