# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Separate root from smoke_tests/ecs_managed_instances: every module block
# here is expected to fail a precondition at plan time, so it cannot share a
# directory (and a single terraform apply) with the passing fixtures.

terraform {
  required_version = ">= 1.10.0" # see modules/ecs_managed_instances/versions.tf

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.50.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  default     = "test-api-key"
}

variable "test_prefix" {
  description = "The ECS daemon task family name prefix"
  type        = string
  default     = "terraform-test"
}
