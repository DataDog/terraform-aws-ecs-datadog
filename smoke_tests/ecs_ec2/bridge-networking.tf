# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Bridge networking mode (default)
module "bridge_mode" {
  source = "../../modules/ecs_ec2"

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  family       = "${var.test_prefix}-bridge-mode"
  network_mode = "bridge"

  create_service = false

  tags = {
    Test = "bridge-networking"
  }
}

output "bridge_mode_task_arn" {
  value = module.bridge_mode.arn
}

output "bridge_mode_network_mode" {
  value = module.bridge_mode.network_mode
}
