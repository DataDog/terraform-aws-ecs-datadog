# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: Datadog Agent Example
################################################################################

module "datadog_ecs_fargate_task" {
  source = "../../modules/ecs_fargate"

  # Configure Datadog
  dd_api_key                       = var.dd_api_key
  dd_site                          = var.dd_site
  dd_service                       = var.dd_service
  dd_tags                          = "team:cont-p, owner:container-monitoring"
  dd_essential                     = true
  dd_is_datadog_dependency_enabled = true

  dd_environment = [
    {
      name  = "DD_CUSTOM_FEATURE",
      value = "true",
    },
  ]

  dd_dogstatsd = {
    enabled                  = true
    dogstatsd_cardinality    = "high",
    origin_detection_enabled = true,
  }

  dd_apm = {
    enabled   = true,
    profiling = true,
  }

  dd_log_collection = {
    enabled = true,
  }

  dd_cws = {
    enabled = true,
  }

  # Configure Task Definition
  family = "dummy-terraform-app"
  container_definitions = jsonencode([
    {
      name      = "dummy-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "dummy-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = true,
    },
    {
      name      = "dummy-cws-app",
      image     = "public.ecr.aws/ubuntu/ubuntu:22.04_stable",
      essential = false,
      entryPoint = [
        "/usr/bin/bash",
        "-c",
        "cp /usr/bin/bash /tmp/malware; chmod u+s /tmp/malware; apt update;apt install -y curl wget; /tmp/malware -c 'while true; do wget https://google.com; sleep 60; done'"
      ],
    }
  ])
  volumes = [
    {
      name = "app-volume"
    }
  ]
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]
}
