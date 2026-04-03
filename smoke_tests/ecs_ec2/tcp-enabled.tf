# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# TCP transport enabled (UDS disabled)
module "tcp_enabled" {
  source = "../../modules/ecs_ec2"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site

  dd_dogstatsd = {
    enabled        = true
    socket_enabled = false
    tcp_enabled    = true
  }

  dd_apm = {
    enabled        = true
    socket_enabled = false
    tcp_enabled    = true
  }

  family         = "${var.test_prefix}-tcp-enabled"
  create_service = false

  tags = {
    Test = "tcp-enabled"
  }
}

output "tcp_enabled_task_arn" {
  value = module.tcp_enabled.arn
}
