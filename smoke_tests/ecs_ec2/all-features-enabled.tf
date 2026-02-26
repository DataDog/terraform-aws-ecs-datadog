# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# All Datadog features enabled
module "all_features" {
  source = "../../modules/ecs_ec2"

  dd_api_key      = var.dd_api_key
  dd_site         = var.dd_site
  dd_cluster_name = "test-cluster"

  dd_dogstatsd = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "high"
  }

  dd_apm = {
    enabled                       = true
    profiling                     = true
    trace_inferred_proxy_services = true
    data_streams                  = true
  }

  dd_log_collection = {
    enabled               = true
    container_collect_all = true
  }

  dd_orchestrator_explorer = {
    enabled = true
  }

  family         = "${var.test_prefix}-all-features"
  create_service = false

  tags = {
    Test = "all-features-enabled"
  }
}

output "all_features_task_arn" {
  value = module.all_features.arn
}
