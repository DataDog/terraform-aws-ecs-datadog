# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

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
