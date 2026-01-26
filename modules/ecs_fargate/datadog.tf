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

locals {

  is_linux               = var.runtime_platform == null || try(var.runtime_platform.operating_system_family == null, true) || try(var.runtime_platform.operating_system_family == "LINUX", true)
  is_fluentbit_supported = var.dd_log_collection.enabled && local.is_linux

  # Datadog Firelens log configuration
  dd_firelens_log_configuration = local.is_fluentbit_supported ? merge(
    {
      logDriver = "awsfirelens"
      options = merge(
        {
          provider    = "ecs"
          Name        = "datadog"
          Host        = var.dd_log_collection.fluentbit_config.log_driver_configuration.host_endpoint
          retry_limit = "2"
        },
        var.dd_log_collection.fluentbit_config.log_driver_configuration.tls == true ? { TLS = "on" } : {},
        var.dd_log_collection.fluentbit_config.log_driver_configuration.service_name != null ? { dd_service = var.dd_log_collection.fluentbit_config.log_driver_configuration.service_name } : {},
        var.dd_log_collection.fluentbit_config.log_driver_configuration.source_name != null ? { dd_source = var.dd_log_collection.fluentbit_config.log_driver_configuration.source_name } : {},
        var.dd_log_collection.fluentbit_config.log_driver_configuration.message_key != null ? { dd_message_key = var.dd_log_collection.fluentbit_config.log_driver_configuration.message_key } : {},
        var.dd_log_collection.fluentbit_config.log_driver_configuration.compress != null ? { compress = var.dd_log_collection.fluentbit_config.log_driver_configuration.compress } : {},
        var.dd_tags != null ? { dd_tags = var.dd_tags } : {},
        var.dd_api_key != null ? { apikey = var.dd_api_key } : {}
      )
    },
    var.dd_api_key_secret != null ? {
      secretOptions = [
        {
          name      = "apikey"
          valueFrom = var.dd_api_key_secret.arn
        }
      ]
    } : {}
  ) : null

  # Application container modifications
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

  dd_agent_mount = concat(
    local.apm_dsd_mount,
    var.dd_readonly_root_filesystem ? [
      {
        containerPath = "/etc/datadog-agent"
        sourceVolume  = "agent-config"
        readOnly      = false
      },
      {
        containerPath = "/tmp"
        sourceVolume  = "agent-tmp"
        readOnly      = false
      },
      {
        containerPath = "/opt/datadog-agent/run"
        sourceVolume  = "agent-run"
        readOnly      = false
      }
    ] : []
  )

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

  ust_docker_labels = merge(
    var.dd_env != null ? {
      "com.datadoghq.tags.env" = var.dd_env
    } : {},
    var.dd_service != null ? {
      "com.datadoghq.tags.service" = var.dd_service
    } : {},
    var.dd_version != null ? {
      "com.datadoghq.tags.version" = var.dd_version
    } : {},
  )

  application_env_vars = concat(
    var.dd_apm.profiling != null ? [
      {
        name  = "DD_PROFILING_ENABLED"
        value = tostring(var.dd_apm.profiling)
      }
    ] : [],
    var.dd_apm.trace_inferred_proxy_services != null ? [
      {
        name  = "DD_TRACE_INFERRED_PROXY_SERVICES_ENABLED"
        value = tostring(var.dd_apm.trace_inferred_proxy_services)
      }
    ] : [],
  )

  agent_dependency = var.dd_is_datadog_dependency_enabled && try(var.dd_health_check.command != null, false) ? [
    {
      containerName = "datadog-agent"
      condition     = "HEALTHY"
    }
  ] : []

  log_router_dependency = try(var.dd_log_collection.fluentbit_config.is_log_router_dependency_enabled, false) && try(var.dd_log_collection.fluentbit_config.log_router_health_check.command != null, false) && local.dd_firelens_log_configuration != null ? [
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
          local.application_env_vars,
        ),
        # Merge UST docker labels with any existing docker labels.
        dockerLabels = merge(
          lookup(container, "dockerLabels", {}),
          local.ust_docker_labels,
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
      },
      # Only override the log configuration if the Datadog firelens configuration exists
      local.dd_firelens_log_configuration != null ? {
        logConfiguration = local.dd_firelens_log_configuration
      } : {},

      # Only override CWS related configuration if the configuration is proper
      local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? {
        entryPoint = concat(local.cws_entry_point_prefix, lookup(container, "entryPoint", []))
      } : {},

      local.is_cws_supported && lookup(container, "entryPoint", []) != [] ? {
        # Note: SYS_PTRACE is the only linux capability available on Fargate
        linuxParameters = {
          capabilities = {
            add = [
              "SYS_PTRACE",
            ]
            drop = []
          }
        }
      } : {},
    )
  ]

  rofs_volumes = var.dd_readonly_root_filesystem ? [
    {
      name = "agent-config"
    },
    {
      name = "agent-tmp"
    },
    {
      name = "agent-run"
    }
  ] : []

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
    local.rofs_volumes,
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

  dynamic_env = [
    for pair in [
      { key = "DD_API_KEY", value = var.dd_api_key },
      { key = "DD_SITE", value = var.dd_site },
      { key = "DD_DOGSTATSD_TAG_CARDINALITY", value = var.dd_dogstatsd.dogstatsd_cardinality },
      { key = "DD_TAGS", value = var.dd_tags },
      { key = "DD_CLUSTER_NAME", value = var.dd_cluster_name },
      { key = "DD_ORCHESTRATOR_EXPLORER_ORCHESTRATOR_DD_URL", value = var.dd_orchestrator_explorer.url },
    ] : { name = pair.key, value = pair.value } if pair.value != null
  ]

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

  dd_environment = var.dd_environment != null ? var.dd_environment : []

  dd_agent_env = concat(
    local.base_env,
    local.dynamic_env,
    local.origin_detection_vars,
    local.cws_vars,
    local.dd_environment,
  )

  dd_agent_dependency = concat(
    var.dd_readonly_root_filesystem ? [
      {
        condition     = "SUCCESS"
        containerName = "init-volume"
      }
    ] : [],
    try(var.dd_log_collection.fluentbit_config.is_log_router_dependency_enabled, false) && local.dd_firelens_log_configuration != null ? local.log_router_dependency : [],
  )

  # Datadog Agent container definition
  dd_agent_container = concat(
    var.dd_readonly_root_filesystem ? [
      {
        cpu                    = 0
        memory                 = 128
        name                   = "init-volume"
        image                  = "${var.dd_registry}:${var.dd_image_version}"
        essential              = false
        readOnlyRootFilesystem = true
        command                = ["/bin/sh", "-c", "cp -vnR /etc/datadog-agent/* /agent-config/ && exit 0"]
        mountPoints = [
          {
            sourceVolume  = "agent-config"
            containerPath = "/agent-config"
            readOnly      = false
          }
        ]
      }
    ] : [],
    [
      merge(
        {
          name         = "datadog-agent"
          image        = "${var.dd_registry}:${var.dd_image_version}"
          essential    = var.dd_essential
          environment  = local.dd_agent_env
          dockerLabels = var.dd_docker_labels
          cpu          = var.dd_cpu
          memory       = var.dd_memory_limit_mib

          readonlyRootFilesystem = var.dd_readonly_root_filesystem
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
          ],

          mountPoints      = local.dd_agent_mount,
          logConfiguration = local.dd_firelens_log_configuration,
          dependsOn        = local.dd_agent_dependency
          systemControls   = []
          volumesFrom      = []
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
  )

  dd_log_environment = var.dd_log_collection.fluentbit_config.environment != null ? var.dd_log_collection.fluentbit_config.environment : []

  # Datadog log router container definition
  dd_log_container = local.is_fluentbit_supported ? [
    merge(
      {
        name      = "datadog-log-router"
        image     = "${var.dd_log_collection.fluentbit_config.registry}:${var.dd_log_collection.fluentbit_config.image_version}"
        essential = var.dd_log_collection.fluentbit_config.is_log_router_essential
        firelensConfiguration = {
          type = "fluentbit"
          options = merge(
            {
              enable-ecs-log-metadata = "true"
            },
            try(var.dd_log_collection.fluentbit_config.firelens_options.config_file_type != null, false) ? { config-file-type = var.dd_log_collection.fluentbit_config.firelens_options.config_file_type } : {},
            try(var.dd_log_collection.fluentbit_config.firelens_options.config_file_value != null, false) ? { config-file-value = var.dd_log_collection.fluentbit_config.firelens_options.config_file_value } : {}
          )
        }
        cpu              = var.dd_log_collection.fluentbit_config.cpu
        memory_limit_mib = var.dd_log_collection.fluentbit_config.memory_limit_mib
        user             = "0"
        mountPoints      = var.dd_log_collection.fluentbit_config.mountPoints
        environment      = local.dd_log_environment
        dockerLabels     = var.dd_docker_labels
        portMappings     = []
        systemControls   = []
        volumesFrom      = []
        dependsOn        = var.dd_log_collection.fluentbit_config.dependsOn
      },
      var.dd_log_collection.fluentbit_config.log_router_health_check.command == null ? {} : {
        healthCheck = {
          command     = var.dd_log_collection.fluentbit_config.log_router_health_check.command
          interval    = var.dd_log_collection.fluentbit_config.log_router_health_check.interval
          timeout     = var.dd_log_collection.fluentbit_config.log_router_health_check.timeout
          retries     = var.dd_log_collection.fluentbit_config.log_router_health_check.retries
          startPeriod = var.dd_log_collection.fluentbit_config.log_router_health_check.start_period
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
      dockerLabels     = var.dd_docker_labels
      portMappings     = []
      systemControls   = []
      volumesFrom      = []
    }
  ] : []
}
