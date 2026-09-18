# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Version and Install Info
locals {
  # Datadog ECS task tags
  version = "0.1.0"

  install_info_tool              = "terraform"
  install_info_tool_version      = "terraform-aws-ecs-datadog"
  install_info_installer_version = local.version

  # AWS Resource Tags
  tags = {
    dd_ecs_terraform_module = local.version
  }
}

################################################################################
# CRI / Host Monitoring Volume Configuration
################################################################################
# ECS Managed Instances run containerd (not Docker), so the agent collects
# container and host metrics via the containerd socket, /proc, and cgroup
# host mounts rather than the Docker socket used on ecs_ec2.

locals {
  cri_volumes = [
    {
      name      = "containerd_sock"
      host_path = var.dd_cri_socket_path
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

  cri_mounts = [
    {
      source_volume  = "containerd_sock"
      container_path = "/var/run/containerd/containerd.sock"
      read_only      = true
    },
    {
      source_volume  = "proc"
      container_path = "/host/proc"
      read_only      = true
    },
    {
      source_volume  = "cgroup"
      container_path = "/host/sys/fs/cgroup"
      read_only      = true
    }
  ]
}

################################################################################
# UDS (Unix Domain Socket) Configuration
################################################################################

locals {
  is_apm_socket_mount = var.dd_apm.enabled && var.dd_apm.socket_enabled
  is_dsd_socket_mount = var.dd_dogstatsd.enabled && var.dd_dogstatsd.socket_enabled
  is_apm_dsd_volume   = local.is_apm_socket_mount || local.is_dsd_socket_mount

  # Host-mounted volume for shared UDS sockets between the daemon and application tasks.
  # Managed daemons run in a shared network namespace, so the socket directory is
  # bind-mounted from the host filesystem rather than an ephemeral task-local volume.
  apm_dsd_volume = local.is_apm_dsd_volume ? [
    {
      name      = "dd-sockets"
      host_path = "/var/run/datadog"
    }
  ] : []

  apm_dsd_mount = local.is_apm_dsd_volume ? [
    {
      source_volume  = "dd-sockets"
      container_path = "/var/run/datadog"
      read_only      = false
    }
  ] : []
}

################################################################################
# Cloud Network Monitoring (Linux only)
################################################################################

locals {
  network_monitoring_volume = var.dd_network_monitoring.enabled ? [
    {
      name      = "debug"
      host_path = "/sys/kernel/debug"
    }
  ] : []

  network_monitoring_mount = var.dd_network_monitoring.enabled ? [
    {
      source_volume  = "debug"
      container_path = "/sys/kernel/debug"
      read_only      = false
    }
  ] : []

  network_monitoring_env = var.dd_network_monitoring.enabled ? [
    {
      name  = "DD_SYSTEM_PROBE_NETWORK_ENABLED"
      value = "true"
    }
  ] : []

  # Datadog's documented capability set for Cloud Network Monitoring in daemon mode.
  network_monitoring_capabilities = var.dd_network_monitoring.enabled ? [
    "SYS_ADMIN",
    "SYS_RESOURCE",
    "SYS_PTRACE",
    "NET_ADMIN",
    "NET_BROADCAST",
    "NET_RAW",
    "IPC_LOCK",
    "CHOWN",
  ] : []
}

################################################################################
# Volume Aggregation
################################################################################

locals {
  all_volumes = concat(
    local.cri_volumes,
    local.apm_dsd_volume,
    local.network_monitoring_volume,
    var.volumes,
  )

  dd_agent_mount = concat(
    local.cri_mounts,
    local.apm_dsd_mount,
    local.network_monitoring_mount,
  )
}

################################################################################
# Datadog Agent Environment Variables
################################################################################

locals {
  # Base environment variables (always set)
  base_env = [
    {
      name  = "ECS_MANAGED_INSTANCES"
      value = "true"
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
    }
  ]

  # Dynamic environment variables (only set if provided)
  dynamic_env = [
    for pair in [
      { key = "DD_API_KEY", value = var.dd_api_key },
      { key = "DD_SITE", value = var.dd_site },
      { key = "DD_CHECKS_TAG_CARDINALITY", value = var.dd_checks_cardinality },
      { key = "DD_DOGSTATSD_TAG_CARDINALITY", value = var.dd_dogstatsd.dogstatsd_cardinality },
      { key = "DD_TAGS", value = var.dd_tags },
      { key = "DD_ORCHESTRATOR_EXPLORER_ORCHESTRATOR_DD_URL", value = var.dd_orchestrator_explorer.url },
      { key = "DD_LOG_LEVEL", value = var.dd_log_level },
      { key = "DD_CRI_SOCKET_PATH", value = var.dd_cri_socket_path },
    ] : { name = pair.key, value = pair.value } if pair.value != null
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

  process_vars = var.dd_process_collection.enabled ? [
    {
      name  = "DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED"
      value = "true"
    }
  ] : []

  # TCP fallback variables. Daemons share a single network namespace per instance
  # (the "daemon bridge"), so non-local traffic must be allowed for TCP-based
  # DogStatsD/APM communication. This is not documented by Datadog for daemon
  # mode; UDS is the recommended and default transport.
  tcp_traffic_vars = concat(
    var.dd_dogstatsd.enabled && var.dd_dogstatsd.tcp_enabled ? [
      {
        name  = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC"
        value = "true"
      }
    ] : [],
    var.dd_apm.enabled && var.dd_apm.tcp_enabled ? [
      {
        name  = "DD_APM_NON_LOCAL_TRAFFIC"
        value = "true"
      }
    ] : [],
  )

  # User-provided environment variables (highest precedence)
  dd_environment = var.dd_environment != null ? var.dd_environment : []

  # Merge module-defined env with user overrides, deduping by name (user wins).
  # `environment` is a Set block on aws_ecs_daemon_task_definition, so unlike the
  # other submodules, simple list concatenation cannot express "later entry wins" -
  # a duplicate name becomes two set members instead of an override.
  merged_env_map = merge(
    { for e in concat(
      local.base_env,
      local.dynamic_env,
      local.origin_detection_vars,
      local.apm_vars,
      local.process_vars,
      local.network_monitoring_env,
      local.tcp_traffic_vars,
    ) : e.name => e.value },
    { for e in local.dd_environment : e.name => e.value if try(e.name, null) != null },
  )

  dd_agent_env = [for name, value in local.merged_env_map : { name = name, value = value }]
}

################################################################################
# Datadog Agent Container Definition
################################################################################

locals {
  dd_agent_container_definition = merge(
    {
      name        = "datadog-agent"
      image       = "${var.dd_registry}:${var.dd_image_version}"
      essential   = var.dd_essential
      cpu         = var.dd_cpu
      memory      = var.dd_memory_limit_mib
      environment = local.dd_agent_env
      mount_point = local.dd_agent_mount

      secret = var.dd_api_key_secret != null ? [
        {
          name       = "DD_API_KEY"
          value_from = var.dd_api_key_secret.arn
        }
      ] : []
    },
    try(var.dd_health_check.command == null, true) ? {} : {
      health_check = {
        command      = var.dd_health_check.command
        interval     = var.dd_health_check.interval
        retries      = var.dd_health_check.retries
        start_period = var.dd_health_check.start_period
        timeout      = var.dd_health_check.timeout
      }
    },
    var.dd_network_monitoring.enabled ? {
      linux_parameters = {
        capabilities = {
          add  = local.network_monitoring_capabilities
          drop = []
        }
      }
    } : {},
    var.dd_agent_log_configuration != null ? {
      log_configuration = {
        log_driver = var.dd_agent_log_configuration.log_driver
        options    = try(var.dd_agent_log_configuration.options, null)
        # try() only catches evaluation errors, not null - an omitted (optional,
        # no-default) secret_options field evaluates to null without erroring,
        # which would otherwise reach a `for_each` downstream and fail with
        # "Cannot use a null value in for_each."
        secret_option = coalesce(var.dd_agent_log_configuration.secret_options, [])
      }
    } : {},
  )
}
