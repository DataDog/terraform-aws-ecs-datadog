# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Live Process collection enabled
module "process_collection" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-process-collection"

  dd_process_collection = {
    enabled = true
  }

  create_daemon = false

  tags = {
    Test = "process-collection"
  }
}

output "process_collection_container_definition" {
  value     = module.process_collection.container_definition
  sensitive = true
}
