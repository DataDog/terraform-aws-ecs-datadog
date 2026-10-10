# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Wraps the module with container definitions that are unknown until apply.
resource "terraform_data" "image_tag" {
  input = "1.0.0"
}

module "task" {
  source = "../.."

  dd_api_key = "test-api-key"
  family     = "unknown-container-definitions"
  container_definitions = jsonencode([
    { name = "app", image = "app:${terraform_data.image_tag.id}", essential = true },
  ])
}

output "tags" {
  value = module.task.tags
}
