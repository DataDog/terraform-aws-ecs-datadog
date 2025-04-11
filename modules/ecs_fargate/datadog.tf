# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

locals {
  # Datadog ECS task tags
  tags = {
    dd_ecs_terraform_module = "1.0.0"
  }

  # Datadog Firelens log configuration
  dd_firelens_log_configuration = var.dd_log_collection.enabled ? merge(
    {
      logDriver = "awsfirelens"
      options = merge(
        {
          provider    = "ecs"
          Name        = "datadog"
          Host        = "http-intake.logs.datadoghq.com"
          TLS         = "on"
          retry_limit = "2"
        },
        var.dd_log_collection.log_driver_configuration.service_name != null ? { dd_service = var.dd_log_collection.log_driver_configuration.service_name } : {},
        var.dd_log_collection.log_driver_configuration.source_name != null ? { dd_source = var.dd_log_collection.log_driver_configuration.source_name } : {},
        var.dd_tags != null ? { dd_tags = var.dd_tags } : {},
        var.dd_api_key != null ? { apikey = var.dd_api_key } : {}
      )
    },
    var.dd_api_key_secret_arn != null ? {
      secretOptions = [
        {
          name      = "apikey"
          valueFrom = var.dd_api_key_secret_arn
        }
      ]
    } : {}
  ) : null

  # Application container modifications
  is_linux            = var.runtime_platform == null || var.runtime_platform.operating_system_family == null || var.runtime_platform.operating_system_family == "LINUX"
  is_apm_socket_mount = var.dd_apm.enabled && var.dd_apm.socket_enabled && local.is_linux
  is_dsd_socket_mount = var.dd_dogstatsd.enabled && var.dd_dogstatsd.socket_enabled && local.is_linux
  is_apm_dsd_volume   = local.is_apm_socket_mount || local.is_dsd_socket_mount

  cws_entry_point_prefix = ["/cws-instrumentation-volume/cws-instrumentation", "trace", "--"]
  is_cws_supported       = local.is_linux && var.dd_cws.enabled

  cws_mount = local.is_cws_supported ? [
    {
      sourceVolume  = "cws-instrumentation-volume"
      containerPath = "/cws-instrumentation-volume"
      readOnly      = false
    }
  ] : []

  apm_dsd_mount = local.is_apm_dsd_volume ? [
    {
      containerPath = "/var/run/datadog"
      sourceVolume  = "dd-sockets"
      readOnly      = false
    }
  ] : []

  apm_socket_var = local.is_apm_socket_mount ? [
    {
      name  = "DD_TRACE_AGENT_URL"
      value = "unix:///var/run/datadog/apm.socket"
    }
  ] : []

  dsd_socket_var = local.is_dsd_socket_mount ? [
    {
      name  = "DD_DOGSTATSD_URL"
      value = "unix:///var/run/datadog/dsd.socket"
    }
  ] : []

  dsd_port_var = !local.is_dsd_socket_mount && var.dd_dogstatsd.enabled ? [
    {
      name  = "DD_AGENT_HOST"
      value = "127.0.0.1"
    }
  ] : []

  ust_env_vars = concat(
    var.dd_env != null ? [
      {
        name  = "DD_ENV"
        value = var.dd_env
      }
    ] : [],
    var.dd_service != null ? [
      {
        name  = "DD_SERVICE"
        value = var.dd_service
      }
    ] : [],
    var.dd_version != null ? [
      {
        name  = "DD_VERSION"
        value = var.dd_version
      }
    ] : [],
  )

  agent_dependency = var.dd_is_datadog_dependency_enabled && var.dd_health_check.command != null ? [
    {
      containerName = "datadog-agent"
      condition     = "HEALTHY"
    }
  ] : []

  log_router_dependency = var.dd_log_collection.is_log_router_dependency_enabled && var.dd_log_collection.log_router_health_check.command != null && local.dd_firelens_log_configuration != null ? [
    {
      containerName = "datadog-log-router"
      condition     = "HEALTHY"
    }
  ] : []

  cws_dependency = local.is_cws_supported ? [
    {
      containerName = "cws-instrumentation-init"
      condition     = "SUCCESS"
    }
  ] : []

  modified_container_definitions = [
    for container in jsondecode(var.container_definitions) : merge(
      container,
      # Note: only configure CWS on container if entryPoint is set
      {
        # Append new environment variables to any existing ones.
        environment = concat(
          lookup(container, "environment", []),
          local.dsd_socket_var,
          local.apm_socket_var,
          local.dsd_port_var,
          local.ust_env_vars,
        ),
        # Append new volume mounts to any existing mountPoints.
        mountPoints = concat(
          lookup(container, "mountPoints", []),
          local.apm_dsd_mount,
          local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? local.cws_mount : [],
        )
        dependsOn = concat(
          lookup(container, "dependsOn", []),
          local.agent_dependency,
          local.log_router_dependency,
          local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? local.cws_dependency : [],
        )
        entryPoint = local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? concat(
          local.cws_entry_point_prefix,
          lookup(container, "entryPoint", []),
        ) : null
        linuxParameters = local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? {
          # Note: SYS_PTRACE is the only supported capability on Fargate
          capabilities = {
            add = [
              "SYS_PTRACE",
            ]
            drop = []
          }
        } : null
      },
      # Only override the log configuration if the Datadog firelens configuration exists
      local.dd_firelens_log_configuration != null ? { logConfiguration = local.dd_firelens_log_configuration } : {}
    )
  ]

  # Volume configuration for task
  apm_dsd_volume = local.is_apm_dsd_volume ? [
    {
      name = "dd-sockets"
    }
  ] : []

  cws_volume = local.is_cws_supported ? [
    {
      name = "cws-instrumentation-volume"
    }
  ] : []

  modified_volumes = concat(
    [for k, v in coalesce(var.volumes, []) : v],
    local.apm_dsd_volume,
    local.cws_volume,
  )

  # Datadog Agent container environment variables
  base_env = [
    {
      name  = "ECS_FARGATE"
      value = "true"
    },
    {
      name  = "DD_ECS_TASK_COLLECTION_ENABLED"
      value = "true"
    }
  ]

  dynamic_env = [
    for pair in [
      { key = "DD_API_KEY", value = var.dd_api_key },
      { key = "DD_SITE", value = var.dd_site },
      { key = "DD_DOGSTATSD_TAG_CARDINALITY", value = var.dd_dogstatsd.dogstatsd_cardinality },
      { key = "DD_TAGS", value = var.dd_tags },
      { key = "DD_CLUSTER_NAME", value = var.dd_cluster_name }
    ] : { name = pair.key, value = pair.value } if pair.value != null
  ]

  origin_detection_vars = var.dd_dogstatsd.origin_detection_enabled ? [
    {
      name  = "DD_DOGSTATSD_ORIGIN_DETECTION"
      value = "true"
    },
    {
      name  = "DD_DOGSTATSD_ORIGIN_DETECTION_CLIENT"
      value = "true"
    }
  ] : []

  cws_vars = local.is_cws_supported ? [
    {
      name  = "DD_RUNTIME_SECURITY_CONFIG_ENABLED"
      value = "true"
    },
    {
      name  = "DD_RUNTIME_SECURITY_CONFIG_EBPFLESS_ENABLED"
      value = "true"
    }
  ] : []

  dd_agent_env = concat(
    local.base_env,
    local.dynamic_env,
    local.origin_detection_vars,
    local.cws_vars,
    local.ust_env_vars,
    var.dd_environment,
  )

  # Datadog Agent container definition
  dd_agent_container = [
    merge(
      {
        name        = "datadog-agent"
        image       = "${var.dd_registry}:${var.dd_image_version}"
        essential   = var.dd_essential
        environment = local.dd_agent_env
        secrets = var.dd_api_key_secret_arn != null ? [
          {
            name      = "DD_API_KEY"
            valueFrom = var.dd_api_key_secret_arn
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
        ],
        mountPoints      = local.apm_dsd_mount,
        logConfiguration = local.dd_firelens_log_configuration,
        dependsOn        = var.dd_log_collection.is_log_router_dependency_enabled && local.dd_firelens_log_configuration != null ? local.log_router_dependency : [],
        systemControls   = []
        volumesFrom      = []
      },
      var.dd_health_check.command == null ? {} : {
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

  # Datadog log router container definition
  dd_log_container = var.dd_log_collection.enabled ? [
    merge(
      {
        name      = "datadog-log-router"
        image     = "${var.dd_log_collection.registry}:${var.dd_log_collection.image_version}"
        essential = var.dd_log_collection.is_log_router_essential
        firelensConfiguration = {
          type = "fluentbit"
          options = {
            enable-ecs-log-metadata = "true"
          }
        }
        cpu              = var.dd_log_collection.cpu
        memory_limit_mib = var.dd_log_collection.memory_limit_mib
        user             = "0"
        mountPoints      = []
        environment      = []
        portMappings     = []
        systemControls   = []
        volumesFrom      = []
      },
      var.dd_log_collection.log_router_health_check.command == null ? {} : {
        healthCheck = {
          command     = var.dd_log_collection.log_router_health_check.command
          interval    = var.dd_log_collection.log_router_health_check.interval
          timeout     = var.dd_log_collection.log_router_health_check.timeout
          retries     = var.dd_log_collection.log_router_health_check.retries
          startPeriod = var.dd_log_collection.log_router_health_check.start_period
        }
      }
    )
  ] : []

  # Datadog CWS tracer definition
  dd_cws_container = local.is_cws_supported ? [
    {
      name             = "cws-instrumentation-init"
      image            = "datadog/cws-instrumentation:latest"
      cpu              = var.dd_cws.cpu
      memory_limit_mib = var.dd_cws.memory_limit_mib
      user             = "0"
      essential        = false
      entryPoint       = []
      command          = ["/cws-instrumentation", "setup", "--cws-volume-mount", "/cws-instrumentation-volume"]
      mountPoints      = local.cws_mount
      environment      = []
      portMappings     = []
      systemControls   = []
      volumesFrom      = []
    }
  ] : []
}