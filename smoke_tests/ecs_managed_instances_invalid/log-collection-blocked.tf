# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Container log collection through the agent is not supported in daemon mode
# on ECS Managed Instances - this must fail the module's precondition.
module "log_collection_blocked" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-log-collection-blocked"

  dd_log_collection = {
    enabled = true
  }

  create_daemon = false
}
