# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Version and Install Info
locals {
  # Datadog ECS task tags
  version = "1.0.7"

  install_info_tool              = "terraform"
  install_info_tool_version      = "terraform-aws-ecs-datadog"
  install_info_installer_version = local.version

  # AWS Resource Tags
  tags = {
    dd_ecs_terraform_module = local.version
  }
}

################################################################################
# Host Volume Configuration (EC2-specific)
################################################################################

locals {
  # Host volumes for Docker monitoring on EC2
  dd_host_volumes = [
    {
      name      = "docker_sock"
      host_path = var.dd_docker_socket_path
    },
    {
      name      = "proc"
      host_path = var.dd_proc_path
    },
    {
      name      = "cgroup"
      host_path = var.dd_cgroup_path
    }
  ]

  # Additional volumes required for log collection
  dd_log_volumes = var.dd_log_collection.enabled ? [
    {
      name      = "pointdir"
      host_path = "/opt/datadog-agent/run"
    },
    {
      name      = "containers_root"
      host_path = "/var/lib/docker/containers/"
    }
  ] : []

  # Container mount points for host volumes
  dd_agent_mount = [
    {
      sourceVolume  = "docker_sock"
      containerPath = "/var/run/docker.sock"
      readOnly      = true
    },
    {
      sourceVolume  = "proc"
      containerPath = "/host/proc"
      readOnly      = true
    },
    {
      sourceVolume  = "cgroup"
      containerPath = "/host/sys/fs/cgroup"
      readOnly      = true
    }
  ]

  # Additional mount points for log collection
  dd_log_mounts = var.dd_log_collection.enabled ? [
    {
      sourceVolume  = "pointdir"
      containerPath = "/opt/datadog-agent/run"
      readOnly      = false
    },
    {
      sourceVolume  = "containers_root"
      containerPath = "/var/lib/docker/containers"
      readOnly      = true
    }
  ] : []

  # Merge user-provided volumes with Datadog host volumes
  all_volumes = concat(
    local.dd_host_volumes,
    local.dd_log_volumes,
    var.volumes
  )
}

################################################################################
# Datadog Agent Environment Variables
################################################################################

locals {
  # Base environment variables (always set)
  base_env = [
    {
      name  = "DD_ECS_TASK_COLLECTION_ENABLED"
      value = var.dd_orchestrator_explorer.enabled ? "true" : "false"
    },
    {
      name  = "DD_INSTALL_INFO_TOOL"
      value = local.install_info_tool
    },
    {
      name  = "DD_INSTALL_INFO_TOOL_VERSION"
      value = local.install_info_tool_version
    },
    {
      name  = "DD_INSTALL_INFO_INSTALLER_VERSION"
      value = local.install_info_installer_version
    },
    {
      name  = "DD_LOG_FILE"
      value = "/opt/datadog-agent/run/logs"
    }
  ]

  # Dynamic environment variables (only set if provided)
  dynamic_env = [
    for pair in [
      { key = "DD_API_KEY", value = var.dd_api_key },
      { key = "DD_SITE", value = var.dd_site },
      { key = "DD_DOGSTATSD_TAG_CARDINALITY", value = var.dd_dogstatsd.dogstatsd_cardinality },
      { key = "DD_TAGS", value = var.dd_tags },
      { key = "DD_CLUSTER_NAME", value = var.dd_cluster_name },
      { key = "DD_ORCHESTRATOR_EXPLORER_ORCHESTRATOR_DD_URL", value = var.dd_orchestrator_explorer.url },
      { key = "DD_LOG_LEVEL", value = var.dd_log_level },
    ] : { name = pair.key, value = pair.value } if pair.value != null
  ]

  # EC2-specific environment variables (allow non-local traffic)
  ec2_env = [
    {
      name  = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"
      value = var.dd_dogstatsd.enabled ? "true" : "false"
    },
    {
      name  = "DD_APM_NON_LOCAL_TRAFFIC"
      value = var.dd_apm.enabled ? "true" : "false"
    }
  ]

  # DogStatsD origin detection variables
  origin_detection_vars = var.dd_dogstatsd.enabled && var.dd_dogstatsd.origin_detection_enabled ? [
    {
      name  = "DD_DOGSTATSD_ORIGIN_DETECTION"
      value = "true"
    },
    {
      name  = "DD_DOGSTATSD_ORIGIN_DETECTION_CLIENT"
      value = "true"
    }
  ] : []

  # APM configuration variables (agent-side only)
  apm_vars = var.dd_apm.enabled ? [
    {
      name  = "DD_APM_ENABLED"
      value = "true"
    }
  ] : []

  # Log collection configuration variables
  logs_vars = var.dd_log_collection.enabled ? concat(
    [
      {
        name  = "DD_LOGS_ENABLED"
        value = "true"
      },
      {
        name  = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL"
        value = tostring(var.dd_log_collection.container_collect_all)
      }
    ],
    length(var.dd_log_collection.container_include) > 0 ? [
      {
        name  = "DD_CONTAINER_INCLUDE_LOGS"
        value = join(" ", var.dd_log_collection.container_include)
      }
    ] : [],
    length(var.dd_log_collection.container_exclude) > 0 ? [
      {
        name  = "DD_CONTAINER_EXCLUDE_LOGS"
        value = join(" ", var.dd_log_collection.container_exclude)
      }
    ] : []
  ) : []

  # User-provided environment variables (highest precedence)
  dd_environment = var.dd_environment != null ? var.dd_environment : []

  # Combine all environment variables
  dd_agent_env = concat(
    local.base_env,
    local.dynamic_env,
    local.ec2_env,
    local.origin_detection_vars,
    local.apm_vars,
    local.logs_vars,
    local.dd_environment,
  )
}

################################################################################
# Datadog Agent Container Definition
################################################################################

locals {
  # Datadog Agent container
  dd_agent_container = [
    merge(
      {
        name         = "datadog-agent"
        image        = "${var.dd_registry}:${var.dd_image_version}"
        essential    = var.dd_essential
        environment  = local.dd_agent_env
        dockerLabels = var.dd_docker_labels
        cpu          = var.dd_cpu
        memory       = var.dd_memory_limit_mib

        secrets = var.dd_api_key_secret != null ? [
          {
            name      = "DD_API_KEY"
            valueFrom = var.dd_api_key_secret.arn
          }
        ] : []

        portMappings = [
          {
            containerPort = 8125
            hostPort      = 8125
            protocol      = "udp"
          },
          {
            containerPort = 8126
            hostPort      = 8126
            protocol      = "tcp"
          }
        ]

        mountPoints    = concat(local.dd_agent_mount, local.dd_log_mounts)
        systemControls = []
        volumesFrom    = []
      },
      try(var.dd_health_check.command == null, true) ? {} : {
        healthCheck = {
          command     = var.dd_health_check.command
          interval    = var.dd_health_check.interval
          timeout     = var.dd_health_check.timeout
          retries     = var.dd_health_check.retries
          startPeriod = var.dd_health_check.start_period
        }
      }
    )
  ]
}
