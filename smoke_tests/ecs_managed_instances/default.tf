# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Default configuration - daemon task definition only, no aws_ecs_daemon
# (create_daemon = false avoids needing a real ECS Managed Instances capacity
# provider ARN for this fixture; capacity_provider_arns is only exercised in a
# dedicated, manually-run test against real Managed Instances infrastructure).
module "default" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-default"

  create_daemon = false

  tags = {
    Test = "default"
  }
}

output "default_family" {
  value = module.default.family
}

output "default_container_definition" {
  value     = module.default.container_definition
  sensitive = true
}

output "default_daemon_arn" {
  value = module.default.daemon_arn
}
