# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Application-side helper outputs for profiling and inferred proxy services.
module "app_env_vars" {
  source = "../../modules/ecs_managed_instances"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  family     = "${var.test_prefix}-app-env-vars"

  dd_apm = {
    profiling                     = true
    trace_inferred_proxy_services = true
    data_streams                  = true
  }

  create_daemon = false

  tags = {
    Test = "app-env-vars"
  }
}

output "app_env_vars_profiling" {
  value = module.app_env_vars.profiling_env_vars
}

output "app_env_vars_trace_inferred_proxy" {
  value = module.app_env_vars.trace_inferred_proxy_env_vars
}

output "app_env_vars_data_streams" {
  value = module.app_env_vars.data_streams_env_vars
}
