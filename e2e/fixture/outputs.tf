# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

output "task_definition_arn" {
  description = "ARN of the service's task definition revision."
  value       = module.service.arn
}

output "language_task_definition_arns" {
  description = "ARN of each language task definition revision, by tracer language."
  value       = { for language, task_definition in module.language : language => task_definition.arn }
}
