# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: CWS
################################################################################

# Verifies that the Datadog Cloud Workload Security events are being sent to Datadog
module "dd_cws_only" {
  source = "../../modules/ecs_fargate"

  dd_api_key                       = var.dd_api_key
  dd_site                          = var.dd_site
  dd_service                       = var.dd_service
  dd_tags                          = "team:cont-p, owner:container-monitoring"
  dd_is_datadog_dependency_enabled = true

  dd_environment = []

  dd_dogstatsd = {
    enabled = false
  }

  dd_apm = {
    enabled = false,
  }

  dd_log_collection = {
    enabled = false,
  }

  dd_cws = {
    enabled = true,
  }

  family = "terraform-test-cws-only"
  container_definitions = jsonencode([
    {
      name      = "datadog-cws-app",
      image     = "public.ecr.aws/ubuntu/ubuntu:22.04_stable",
      essential = true,
      entryPoint = [
        "/usr/bin/bash",
        "-c",
        "cp /usr/bin/bash /tmp/malware; chmod u+s /tmp/malware; apt update;apt install -y curl wget; /tmp/malware -c 'while true; do wget https://google.com; sleep 60; done'"
      ],
    }
  ])
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]
}