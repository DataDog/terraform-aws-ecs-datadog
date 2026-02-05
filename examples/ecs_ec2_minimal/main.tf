# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Minimal Datadog Agent Configuration (Task Definition Only)
################################################################################

module "datadog_agent" {
  source = "../../modules/ecs_ec2"

  # Required: Datadog Configuration
  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site

  # Required: Task Definition
  family = "datadog-agent-daemon"

  # Optional: Skip service creation (you'll create it manually)
  create_service = false
}

################################################################################
# Create Daemon Service Separately (Optional)
################################################################################

resource "aws_ecs_service" "datadog_agent" {
  count = var.create_service ? 1 : 0

  name                = "datadog-agent"
  cluster             = var.cluster_arn
  task_definition     = module.datadog_agent.arn
  scheduling_strategy = "DAEMON"

  depends_on = [module.datadog_agent]
}
