# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Log collection through the json-file log driver volume, with include and
# exclude filters.
module "log_collection" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-log-collection"

  dd_log_collection = {
    enabled           = true
    container_include = ["name:app-.*"]
    container_exclude = ["name:sidecar-.*", "image:busybox"]
  }

  create_daemon = false

  tags = {
    Test = "log-collection"
  }
}

output "log_collection_container_definition" {
  value     = module.log_collection.container_definition
  sensitive = true
}
