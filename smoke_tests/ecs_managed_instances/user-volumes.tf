# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# User volumes: one mounted read-only at a custom container path, one mounted
# read-write, and one with no container_path (mounted at its host path).
module "user_volumes" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-user-volumes"

  volumes = [
    { name = "ro-data", host_path = "/data/ro", container_path = "/host/data/ro" },
    { name = "rw-data", host_path = "/data/rw", container_path = "/host/data/rw", read_only = false },
    { name = "same-path", host_path = "/data/same" },
  ]

  create_daemon = false

  tags = {
    Test = "user-volumes"
  }
}

output "user_volumes_container_definition" {
  value     = module.user_volumes.container_definition
  sensitive = true
}
