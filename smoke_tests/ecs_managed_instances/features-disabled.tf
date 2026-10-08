# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Agent features explicitly disabled, plus a non-default host containerd
# socket path (the in-container path must stay fixed).
module "features_disabled" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-features-disabled"

  dd_dogstatsd = {
    enabled = false
  }

  dd_apm = {
    enabled = false
  }

  dd_orchestrator_explorer = {
    enabled = false
  }

  dd_cri_socket_path = "/run/containerd/containerd.sock"

  create_daemon = false

  tags = {
    Test = "features-disabled"
  }
}

output "features_disabled_container_definition" {
  value     = module.features_disabled.container_definition
  sensitive = true
}
