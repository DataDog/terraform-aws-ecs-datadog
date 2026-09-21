# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Verifies dd_environment overrides a module-set variable by name rather than
# producing a duplicate Set member (environment is a Terraform Set block on
# aws_ecs_daemon_task_definition, unlike the ordered list used by the other
# two submodules).
module "environment_override" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-env-override"

  dd_environment = [
    { name = "DD_SITE", value = "datadoghq.eu" }
  ]

  create_daemon = false

  tags = {
    Test = "environment-override"
  }
}

output "environment_override_container_definition" {
  value     = module.environment_override.container_definition
  sensitive = true
}
