# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Null values
################################################################################

# Verifies that the task definition is created with all optional values set to null
module "dd_task_all_null" {
  source = "../../modules/ecs_fargate"

  # Required values
  dd_api_key = var.dd_api_key
  family     = "${var.test_prefix}-all-null"
  container_definitions = jsonencode([
    {
      name : "dummy-container",
      image : "ubuntu:latest",
      essential : true,
      command : ["sleep", "infinity"]
    }
  ])

  # Optional values set to null
  dd_registry                      = null
  dd_image_version                 = null
  dd_cpu                           = null
  dd_essential                     = null
  dd_is_datadog_dependency_enabled = null
  dd_health_check                  = null
  dd_site                          = null
  dd_environment                   = null
  dd_tags                          = null
  dd_memory_limit_mib              = null
  dd_cluster_name                  = null
  dd_env                           = null
  dd_service                       = null
  dd_version                       = null
  dd_checks_cardinality            = null

  dd_dogstatsd = {
    enabled = null
  }
  dd_apm = {
    enabled = null
  }
  dd_log_collection = {
    enabled = null
  }
  dd_cws = {
    enabled = null
  }

  # Task Definition values set to null
  ephemeral_storage      = null
  enable_fault_injection = null
  execution_role         = null
  inference_accelerator  = null
  ipc_mode               = null
  pid_mode               = null
  placement_constraints  = null
  proxy_configuration    = null
  runtime_platform       = null
  skip_destroy           = null
  tags                   = null
  task_role              = null
  track_latest           = null
  volumes                = null

  # Required values for Fargate
  # cpu                      = null
  # memory                   = null
  # network_mode             = null
  # requires_compatibilities = null

}
