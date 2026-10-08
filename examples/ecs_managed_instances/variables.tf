# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

variable "region" {
  description = "AWS region. Must be a region where ECS Managed Instances is available."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "dd-ecs-mi-example"
}

variable "vpc_id" {
  description = "VPC ID to deploy the ECS Managed Instances capacity provider and application tasks into"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs (in the given VPC) that Managed Instances can be launched into"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs to attach to Managed Instances"
  type        = list(string)
}

variable "datadog_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "dd_site" {
  description = "Datadog site (e.g., datadoghq.com, datadoghq.eu)"
  type        = string
  default     = "datadoghq.com"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Environment = "example"
  }
}
