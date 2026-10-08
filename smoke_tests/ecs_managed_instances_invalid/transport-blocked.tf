# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# DogStatsD enabled with neither UDS nor TCP transport configured - this must
# fail the module's precondition.
module "transport_blocked" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-transport-blocked"

  dd_dogstatsd = {
    enabled        = true
    socket_enabled = false
    tcp_enabled    = false
  }

  dd_apm = {
    enabled = false
  }

  create_daemon = false
}
