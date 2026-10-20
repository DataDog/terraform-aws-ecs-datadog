# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

variable "region" {
  description = "AWS region of the shared ECS resources."
  type        = string
}

variable "name" {
  description = "Run-scoped name of the service and its task definition family."
  type        = string
}

variable "run_id" {
  description = "Run ID that the service's traces and logs carry."
  type        = string
}

variable "tags" {
  description = "Run ID and creation time tags that the sweeper reads."
  type        = map(string)
}

variable "cluster" {
  description = "ECS cluster that runs the service."
  type        = string
}

variable "subnets" {
  description = "Public subnets for the service's task."
  type        = list(string)
}

variable "security_group" {
  description = "Security group that allows inbound traffic to the application port."
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the task execution role, which can read the API key secret."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the task role."
  type        = string
}

variable "log_group" {
  description = "CloudWatch Logs group for the language task definitions."
  type        = string
}

variable "dd_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret that holds the Datadog API key."
  type        = string
}

variable "dd_site" {
  description = "Datadog site."
  type        = string
}

variable "dd_env" {
  description = "Datadog environment."
  type        = string
}

variable "dd_version" {
  description = "Datadog version of the service."
  type        = string
}

variable "agent_image_version" {
  description = "Datadog Agent image tag."
  type        = string
}

variable "service_language" {
  description = "Language of the tracer to inject into the service."
  type        = string
}

variable "service_image" {
  description = "Application image that the service runs."
  type        = string
}

variable "language_images" {
  description = "Application image of each language task definition, by tracer language."
  type        = map(string)
}
