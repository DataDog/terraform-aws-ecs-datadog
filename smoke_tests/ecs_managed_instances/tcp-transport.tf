# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# TCP-only transport: the application helper outputs must point at the
# daemon bridge IP instead of the UDS sockets.
module "tcp_transport" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-tcp-transport"

  dd_dogstatsd = {
    socket_enabled = false
    tcp_enabled    = true
  }

  dd_apm = {
    socket_enabled = false
    tcp_enabled    = true
  }

  create_daemon = false

  tags = {
    Test = "tcp-transport"
  }
}

output "tcp_transport_dogstatsd_env_vars" {
  value = module.tcp_transport.dogstatsd_env_vars
}

output "tcp_transport_apm_env_vars" {
  value = module.tcp_transport.apm_env_vars
}
