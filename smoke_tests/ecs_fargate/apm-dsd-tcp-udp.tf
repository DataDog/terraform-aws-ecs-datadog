# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: DogstatsD and APM via TCP and UDP
################################################################################

# Checks that the metrics and traces are properly sent via ports
# Verifies that no volumes are mounted
module "dd_task_apm_dsd_tcp_udp" {
  source = "../../modules/ecs_fargate"

  dd_api_key   = var.dd_api_key
  dd_site      = var.dd_site
  dd_service   = var.dd_service
  dd_tags      = "team:cont-p, owner:container-monitoring"
  dd_essential = true

  dd_dogstatsd = {
    enabled        = true,
    socket_enabled = false,
  }

  dd_apm = {
    enabled        = true,
    socket_enabled = false,
  }

  family = "${var.test_prefix}-apm-dsd-tcp-udp"
  container_definitions = jsonencode([
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "datadog-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = true,
    },
  ])
  volumes                  = []
  requires_compatibilities = ["FARGATE"]
}