# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

output "container_definitions" {
  description = "A list of valid container definitions provided as a single valid JSON document."
  value       = aws_ecs_task_definition.this.container_definitions
}

output "cpu" {
  description = "Number of cpu units used by the task."
  value       = aws_ecs_task_definition.this.cpu
}

output "enable_fault_injection" {
  description = "Enables fault injection and allows for fault injection requests to be accepted from the task's containers."
  value       = aws_ecs_task_definition.this.enable_fault_injection
}

output "ephemeral_storage" {
  description = "The amount of ephemeral storage to allocate for the task."
  value       = aws_ecs_task_definition.this.ephemeral_storage
}

output "execution_role_arn" {
  description = "ARN of the task execution role."
  value       = aws_ecs_task_definition.this.execution_role_arn
}

output "family" {
  description = "A unique name for your task definition."
  value       = aws_ecs_task_definition.this.family
}

output "inference_accelerator" {
  description = "Inference accelerator settings."
  value       = aws_ecs_task_definition.this.inference_accelerator
}

output "ipc_mode" {
  description = "IPC resource namespace to be used for the containers."
  value       = aws_ecs_task_definition.this.ipc_mode
}

output "memory" {
  description = "Amount (in MiB) of memory used by the task."
  value       = aws_ecs_task_definition.this.memory
}

output "network_mode" {
  description = "Docker networking mode to use for the containers."
  value       = aws_ecs_task_definition.this.network_mode
}

output "pid_mode" {
  description = "Process namespace to use for the containers."
  value       = aws_ecs_task_definition.this.pid_mode
}

output "placement_constraints" {
  description = "Rules that are taken into consideration during task placement."
  value       = aws_ecs_task_definition.this.placement_constraints
}

output "proxy_configuration" {
  description = "Configuration block for the App Mesh proxy."
  value       = aws_ecs_task_definition.this.proxy_configuration
}

output "requires_compatibilities" {
  description = "Set of launch types required by the task."
  value       = aws_ecs_task_definition.this.requires_compatibilities
}

output "runtime_platform" {
  description = "Runtime platform configuration for the task definition."
  value       = aws_ecs_task_definition.this.runtime_platform
}

output "skip_destroy" {
  description = "Whether to retain the old revision when the resource is destroyed or replacement is necessary."
  value       = aws_ecs_task_definition.this.skip_destroy
}

output "tags" {
  description = "Key-value map of resource tags."
  value       = aws_ecs_task_definition.this.tags
}

output "task_role_arn" {
  description = "ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services."
  value       = aws_ecs_task_definition.this.task_role_arn
}

output "track_latest" {
  description = "Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state."
  value       = aws_ecs_task_definition.this.track_latest
}

output "volume" {
  description = "Configuration block for volumes that containers in your task may use."
  value       = aws_ecs_task_definition.this.volume
}

# Attribute reference outputs

output "arn" {
  description = "Full ARN of the Task Definition (including both family and revision)."
  value       = aws_ecs_task_definition.this.arn
}

output "arn_without_revision" {
  description = "ARN of the Task Definition with the trailing revision removed."
  value       = aws_ecs_task_definition.this.arn_without_revision
}

output "revision" {
  description = "Revision of the task in a particular family."
  value       = aws_ecs_task_definition.this.revision
}

output "tags_all" {
  description = "Map of tags assigned to the resource, including inherited tags."
  value       = aws_ecs_task_definition.this.tags_all
}
