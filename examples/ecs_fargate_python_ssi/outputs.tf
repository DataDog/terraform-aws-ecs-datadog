# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

output "task_definition_arn" {
  description = "ARN of the registered task definition"
  value       = module.datadog_ecs_fargate_task.arn
}
