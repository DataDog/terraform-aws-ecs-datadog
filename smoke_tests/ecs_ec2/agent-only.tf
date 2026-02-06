# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Minimal agent deployment - task definition only, no service
module "agent_only" {
  source = "../../modules/ecs_ec2"

  dd_api_key     = "test-api-key"
  dd_site        = "datadoghq.com"
  family         = "smoke-test-agent-only"
  create_service = false

  tags = {
    Test = "agent-only"
  }
}

output "agent_only_task_arn" {
  value = module.agent_only.arn
}
