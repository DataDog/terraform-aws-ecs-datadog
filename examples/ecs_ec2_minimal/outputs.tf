# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

output "task_definition_arn" {
  description = "ARN of the Datadog Agent task definition"
  value       = module.datadog_agent.arn
}

output "task_definition_family" {
  description = "Family of the Datadog Agent task definition"
  value       = module.datadog_agent.family
}

output "task_role_arn" {
  description = "ARN of the Datadog Agent task role"
  value       = module.datadog_agent.task_role_arn
}

output "execution_role_arn" {
  description = "ARN of the Datadog Agent execution role"
  value       = module.datadog_agent.execution_role_arn
}
