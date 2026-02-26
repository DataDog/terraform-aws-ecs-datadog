# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
}

variable "dd_site" {
  description = "Datadog Site"
  type        = string
  default     = "datadoghq.com"
}

variable "test_prefix" {
  description = "The ECS task family name prefix"
  type        = string
  default     = "terraform-test"
}
