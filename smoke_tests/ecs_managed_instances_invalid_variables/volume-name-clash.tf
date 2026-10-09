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

# A user volume mounted at a module-managed path must fail variable validation.
module "volume_path_clash" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-volume-path-clash"

  volumes = [
    { name = "extra", host_path = "/tmp/extra", container_path = "/host/proc" },
  ]

  create_daemon = false
}

# A relative container_path must fail variable validation.
module "volume_relative_path" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-volume-relative-path"

  volumes = [
    { name = "extra", host_path = "/tmp/extra", container_path = "data" },
  ]

  create_daemon = false
}
