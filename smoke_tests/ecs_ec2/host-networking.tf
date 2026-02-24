# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Host networking mode
module "host_mode" {
  source = "../../modules/ecs_ec2"

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  family       = "${var.test_prefix}-host-mode"
  network_mode = "host"

  create_service = false

  tags = {
    Test = "host-networking"
  }
}

output "host_mode_task_arn" {
  value = module.host_mode.arn
}

output "host_mode_network_mode" {
  value = module.host_mode.network_mode
}
