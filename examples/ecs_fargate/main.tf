################################################################################
# Task Definition: Datadog Agent Example
################################################################################

module "ecs_task" {
  source = "../../modules/ecs_fargate"

  # Configure Datadog
  dd_api_key                       = var.dd_api_key
  dd_api_key_secret_arn            = var.dd_api_key_secret_arn
  dd_site                          = var.dd_site
  dd_service                       = var.dd_service
  dd_tags                          = "team:cont-p, owner:container-monitoring"
  dd_essential                     = true
  dd_is_datadog_dependency_enabled = true

  dd_environment = [
    {
      name  = "DD_CUSTOM_ENV_VAR",
      value = "custom_value",
    },
  ]

  dd_dogstatsd = {
    dogstatsd_cardinality    = "high",
    origin_detection_enabled = true,
  }

  dd_apm = {
    enabled = true,
  }

  dd_log_collection = {
    enabled                          = true,
    is_log_router_dependency_enabled = true,
  }

  # Configure Task Definition
  family = "datadog-terraform-app"
  container_definitions = {
    dogstatsd = {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    apm = {
      name      = "datadog-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = false,
    },
    cws = {
      name      = "datadog-cws-app",
      image     = "public.ecr.aws/ubuntu/ubuntu:22.04_stable",
      essential = true,
      entryPoint = [
        "/usr/bin/bash",
        "-c",
        "cp /usr/bin/bash /tmp/malware; chmod u+s /tmp/malware; apt update;apt install -y curl wget; /tmp/malware -c 'while true; do wget https://google.com; sleep 60; done'"
      ]
    }
  }
  requires_compatibilities = ["FARGATE"]
}
