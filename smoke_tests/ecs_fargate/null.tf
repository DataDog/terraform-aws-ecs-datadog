# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Datadog Agent Example
################################################################################

resource "null_resource" "ecs_propagation_delay" {
  provisioner "local-exec" {
    command = "sleep 10"
  }

  depends_on = [
    module.dd_task_all_dd_inputs,
    module.dd_task_all_ecs_inputs,
    module.dd_task_logging_only,
    module.dd_task_all_dd_disabled,
    module.dd_task_apm_dsd_tcp_udp,
    module.dd_task_all_windows,
    module.dd_task_all_null,
    module.dd_task_cws_only
  ]
}