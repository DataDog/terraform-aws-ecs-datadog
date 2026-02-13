# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Datadog ECS EC2 Configuration
################################################################################

variable "operating_system" {
  description = "Operating system of the EC2 container instances. Currently only 'linux' is fully supported. Windows support is planned for a future release."
  type        = string
  default     = "linux"
  nullable    = false
  validation {
    condition     = contains(["linux", "windows"], var.operating_system)
    error_message = "operating_system must be 'linux' or 'windows'."
  }
}

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  default     = null
}

variable "dd_api_key_secret" {
  description = "Datadog API Key Secret ARN"
  type = object({
    arn = string
  })
  default = null
  validation {
    condition     = var.dd_api_key_secret == null || try(var.dd_api_key_secret.arn != null, false)
    error_message = "If 'dd_api_key_secret' is set, 'arn' must be a non-null string."
  }
}

variable "dd_registry" {
  description = "Datadog Agent image registry"
  type        = string
  default     = "public.ecr.aws/datadog/agent"
  nullable    = false
}

variable "dd_image_version" {
  description = "Datadog Agent image version"
  type        = string
  default     = "latest"
  nullable    = false
}

variable "dd_cpu" {
  description = "Datadog Agent container CPU units"
  type        = number
  default     = 256
  nullable    = false
}

variable "dd_memory_limit_mib" {
  description = "Datadog Agent container memory limit in MiB"
  type        = number
  default     = 512
  nullable    = false
}

variable "dd_essential" {
  description = "Whether the Datadog Agent container is essential"
  type        = bool
  default     = true
  nullable    = false
}

variable "dd_health_check" {
  description = "Datadog Agent health check configuration"
  type = object({
    command      = optional(list(string))
    interval     = optional(number)
    retries      = optional(number)
    start_period = optional(number)
    timeout      = optional(number)
  })
  default = {
    command      = ["CMD-SHELL", "/probe.sh"]
    interval     = 15
    retries      = 3
    start_period = 60
    timeout      = 5
  }
}

variable "dd_site" {
  description = "Datadog Site"
  type        = string
  default     = "datadoghq.com"
}

variable "dd_environment" {
  description = "Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module. For example, `dd_environment = [ { name = 'DD_VAR', value = 'DD_VAL' } ]`"
  type        = list(map(string))
  default     = [{}]
  nullable    = false
}

variable "dd_docker_labels" {
  description = "Datadog Agent container docker labels"
  type        = map(string)
  default     = {}
}

variable "dd_tags" {
  description = "Datadog Agent global tags (eg. `key1:value1, key2:value2`)"
  type        = string
  default     = null
}

variable "dd_cluster_name" {
  description = "Datadog cluster name"
  type        = string
  default     = null
}

variable "dd_checks_cardinality" {
  description = "Datadog Agent checks cardinality"
  type        = string
  default     = null
  validation {
    condition     = var.dd_checks_cardinality == null || can(contains(["low", "orchestrator", "high"], var.dd_checks_cardinality))
    error_message = "The Datadog Agent checks cardinality must be one of 'low', 'orchestrator', 'high', or null."
  }
}

variable "dd_dogstatsd" {
  description = "Configuration for Datadog DogStatsD"
  type = object({
    enabled                  = optional(bool, true)
    origin_detection_enabled = optional(bool, true)
    dogstatsd_cardinality    = optional(string, "orchestrator")
  })
  default = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"
  }
  validation {
    condition     = var.dd_dogstatsd != null
    error_message = "The Datadog Dogstatsd configuration must be defined."
  }
  validation {
    condition     = try(var.dd_dogstatsd.dogstatsd_cardinality == null, false) || can(contains(["low", "orchestrator", "high"], var.dd_dogstatsd.dogstatsd_cardinality))
    error_message = "The Datadog Dogstatsd cardinality must be one of 'low', 'orchestrator', 'high', or null."
  }
}

variable "dd_apm" {
  description = "Configuration for Datadog APM"
  type = object({
    enabled                       = optional(bool, true)
    profiling                     = optional(bool, false)
    trace_inferred_proxy_services = optional(bool, false)
    data_streams                  = optional(bool, false)
  })
  default = {
    enabled                       = true
    profiling                     = false
    trace_inferred_proxy_services = false
    data_streams                  = false
  }
  validation {
    condition     = var.dd_apm != null
    error_message = "The Datadog APM configuration must be defined."
  }
}

variable "dd_log_collection" {
  description = "Configuration for Datadog Log Collection via the agent"
  type = object({
    enabled               = optional(bool, false)
    container_collect_all = optional(bool, true)
    container_include     = optional(list(string), [])
    container_exclude     = optional(list(string), [])
  })
  default = {
    enabled = false
  }
  validation {
    condition     = var.dd_log_collection != null
    error_message = "The Datadog Log Collection configuration must be defined."
  }
}

variable "dd_orchestrator_explorer" {
  description = "Configuration for Datadog Orchestrator Explorer"
  type = object({
    enabled = optional(bool, true)
    url     = optional(string)
  })
  default = {
    enabled = true
  }
  validation {
    condition     = var.dd_orchestrator_explorer != null
    error_message = "The Datadog Orchestrator Explorer configuration must be defined."
  }
}

variable "dd_log_level" {
  description = "Set logging verbosity for Datadog agent. Valid values: trace, debug, info, warn, error, critical, off"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["trace", "debug", "info", "warn", "error", "critical", "off"], var.dd_log_level)
    error_message = "dd_log_level must be one of: trace, debug, info, warn, error, critical, off"
  }
}

variable "dd_docker_socket_path" {
  description = "Path to Docker socket on the host. Defaults to /var/run/docker.sock"
  type        = string
  default     = "/var/run/docker.sock"
  nullable    = false
}

variable "dd_proc_path" {
  description = "Path to /proc directory on the host. Defaults to /proc/"
  type        = string
  default     = "/proc/"
  nullable    = false
}

variable "dd_cgroup_path" {
  description = "Path to cgroup directory on the host. Defaults to /sys/fs/cgroup/. Use /cgroup/ for Amazon Linux 1 instances."
  type        = string
  default     = "/sys/fs/cgroup/"
  nullable    = false
}

################################################################################
# ECS Service Configuration (Daemon)
################################################################################

variable "create_service" {
  description = "Whether to create the ECS daemon service. If false, only the task definition is created."
  type        = bool
  default     = true
  nullable    = false
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster where the Datadog agent daemon service will run. Required if create_service = true."
  type        = string
  default     = null
}

variable "service_name" {
  description = "Name of the ECS daemon service. Defaults to '<family>-datadog-agent'"
  type        = string
  default     = null
}

variable "service_placement_constraints" {
  description = "Placement constraints for the daemon service (e.g., instance type, availability zone)"
  type = list(object({
    type       = string
    expression = optional(string)
  }))
  default = []
}

variable "service_registries" {
  description = "Service discovery registries for the daemon service"
  type = object({
    registry_arn   = string
    container_name = optional(string)
    container_port = optional(number)
  })
  default = null
}

variable "enable_ecs_managed_tags" {
  description = "Enable ECS managed tags for the daemon service"
  type        = bool
  default     = true
  nullable    = false
}

variable "propagate_tags" {
  description = "Propagate tags from task definition or service to tasks. Valid values: TASK_DEFINITION, SERVICE, NONE"
  type        = string
  default     = "SERVICE"
  validation {
    condition     = contains(["TASK_DEFINITION", "SERVICE", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be one of: TASK_DEFINITION, SERVICE, NONE"
  }
}

################################################################################
# Task Definition
################################################################################

variable "family" {
  description = "A unique name for your task definition"
  type        = string
}

variable "network_mode" {
  description = "Docker networking mode to use for the containers in the task. Valid values are `bridge` and `host`"
  type        = string
  default     = "bridge"
  validation {
    condition     = contains(["bridge", "host"], var.network_mode)
    error_message = "network_mode must be 'bridge' or 'host' for EC2 launch type"
  }
}

variable "ipc_mode" {
  description = "IPC resource namespace to be used for the containers in the task The valid values are `host`, `task`, and `none`"
  type        = string
  default     = null
}

variable "pid_mode" {
  description = "Process namespace to use for the containers in the task. The valid values are `host` and `task`"
  type        = string
  default     = null
}

variable "placement_constraints" {
  description = "Configuration list for rules that are taken into consideration during task placement (up to max of 10)"
  type = list(object({
    type       = string
    expression = string
  }))
  default = []
}

variable "proxy_configuration" {
  description = "Configuration for the App Mesh proxy"
  type = object({
    container_name = string
    properties     = map(any)
    type           = optional(string, "APPMESH")
  })
  default = null
}

variable "skip_destroy" {
  description = "Whether to retain the old revision when the resource is destroyed or replacement is necessary"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of additional tags to add to the task definition/service created"
  type        = map(string)
  default     = null
}

variable "execution_role" {
  description = "ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume. Contains:\n  - `arn` (string): The ARN of the IAM role.\n  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch container and cluster metadata."
  type = object({
    arn                    = string
    add_dd_ecs_permissions = optional(bool, true)
  })
  default = null
  validation {
    condition     = var.execution_role == null || try(var.execution_role.arn != null, false)
    error_message = "If 'execution_role' is set, 'arn' must be a non-null string."
  }
}

variable "task_role" {
  description = "The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services. Contains:\n  - `arn` (string): The ARN of the IAM role.\n  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch a provided Datadog API key secret."
  type = object({
    arn                    = string
    add_dd_ecs_permissions = optional(bool, true)
  })
  default = null
  validation {
    condition     = var.task_role == null || try(var.task_role.arn != null, false)
    error_message = "If 'task_role' is set, 'arn' must be a non-null string."
  }
}

variable "track_latest" {
  description = "Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state"
  type        = bool
  default     = false
}

variable "volumes" {
  description = "A list of volume definitions that containers in your task may use"
  type = list(object({
    name      = string
    host_path = optional(string)

    docker_volume_configuration = optional(object({
      autoprovision = optional(bool)
      driver        = optional(string)
      driver_opts   = optional(map(any))
      labels        = optional(map(any))
      scope         = optional(string)
    }))

    efs_volume_configuration = optional(object({
      file_system_id          = string
      root_directory          = optional(string)
      transit_encryption      = optional(string)
      transit_encryption_port = optional(number)
      authorization_config = optional(object({
        access_point_id = optional(string)
        iam             = optional(string)
      }))
    }))
  }))
  default = []
}
