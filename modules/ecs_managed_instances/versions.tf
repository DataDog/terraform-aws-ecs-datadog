# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

terraform {
  # Terraform < 1.10.0 rejects a `dynamic` block's for_each argument when it
  # evaluates to a collection of object values, regardless of tolist()/
  # toset() wrapping, for this resource's Set-schema `environment` block
  # ("Cannot use a set of object value in for_each"). Confirmed by bisecting
  # Terraform releases directly - this is a genuine CLI version floor for
  # aws_ecs_daemon_task_definition, not something the module's own HCL can
  # work around on older Terraform.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_ecs_daemon_task_definition and aws_ecs_daemon were added in v6.50.0
      version = ">= 6.50.0"
    }
  }
}
