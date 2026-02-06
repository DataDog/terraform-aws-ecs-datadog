# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  sensitive   = true
}

variable "dd_site" {
  description = "Datadog site (e.g., datadoghq.com, datadoghq.eu)"
  type        = string
  default     = "datadoghq.com"
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster (only needed if create_service = true)"
  type        = string
  default     = null
}

variable "create_service" {
  description = "Whether to create the ECS daemon service"
  type        = bool
  default     = false
}
