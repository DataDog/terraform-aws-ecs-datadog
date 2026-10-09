# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# A user volume that reuses a module-managed volume name must fail variable
# validation.
module "volume_name_clash" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-volume-name-clash"

  volumes = [
    { name = "proc", host_path = "/tmp/proc" },
  ]

  create_daemon = false
}
