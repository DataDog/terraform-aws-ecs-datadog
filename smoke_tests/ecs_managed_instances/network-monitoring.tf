# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Cloud Network Monitoring enabled
module "network_monitoring" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-network-monitoring"

  dd_network_monitoring = {
    enabled = true
  }

  create_daemon = false

  tags = {
    Test = "network-monitoring"
  }
}

output "network_monitoring_container_definition" {
  value     = module.network_monitoring.container_definition
  sensitive = true
}
