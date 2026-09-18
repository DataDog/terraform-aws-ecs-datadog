# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Datadog ECS Managed Instances Configuration
################################################################################

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  default     = null
  sensitive   = true
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
  description = "Datadog Agent image version. ECS Managed Instances daemon mode requires Datadog Agent >= 7.77.0."
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
  description = "Datadog Agent health check configuration. Defaults to Datadog's documented health check command for ECS Managed Instances daemon mode (not the same default used by the ecs_ec2/ecs_fargate modules). aws_ecs_daemon defaults `critical = true` and the Terraform aws_ecs_daemon resource does not expose a way to set `critical = false`, so an unhealthy/flapping health check causes AWS to drain and replace the underlying EC2 instance. Using Datadog's own documented command minimizes that risk."
  type = object({
    command      = optional(list(string))
    interval     = optional(number)
    retries      = optional(number)
    start_period = optional(number)
    timeout      = optional(number)
  })
  default = {
    command      = ["CMD-SHELL", "agent health"]
    interval     = 30
    retries      = 3
    start_period = 15
    timeout      = 5
  }
}

variable "dd_site" {
  description = "Datadog Site"
  type        = string
  default     = "datadoghq.com"
}

variable "dd_environment" {
  description = "Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module. For example, `dd_environment = [ { name = 'DD_VAR', value = 'DD_VAL' } ]`. Defaults to `[]` (not `[{}]` as in the ecs_ec2/ecs_fargate modules) because the `environment` block on aws_ecs_daemon_task_definition is a Terraform Set rather than an ordered list: an empty map would produce an entry with null name/value that passes through into the Set, and precedence must instead be implemented via explicit dedupe-by-name."
  type        = list(map(string))
  default     = []
  nullable    = false
}

variable "dd_tags" {
  description = "Datadog Agent global tags (eg. `key1:value1, key2:value2`)"
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
  description = "Configuration for Datadog DogStatsD. UDS (socket_enabled) is the default and is Datadog-documented for daemon mode on ECS Managed Instances. TCP (tcp_enabled) is also supported: daemons on an instance share a static bridge IP (169.254.172.2) reachable over the network. Origin detection over TCP requires a real DogStatsD client library, since the client embeds the container ID/inode directly in the packet - a hand-rolled socket sender will produce untagged metrics."
  type = object({
    enabled                  = optional(bool, true)
    origin_detection_enabled = optional(bool, true)
    dogstatsd_cardinality    = optional(string, "orchestrator")
    socket_enabled           = optional(bool, true)
    tcp_enabled              = optional(bool, false)
  })
  default = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"
    socket_enabled           = true
    tcp_enabled              = false
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
  description = "Configuration for Datadog APM. UDS (socket_enabled) is the default and is Datadog-documented for daemon mode on ECS Managed Instances. TCP (tcp_enabled) is also supported: daemons on an instance share a static bridge IP (169.254.172.2) reachable over the network. Origin detection over TCP requires a real APM client library, since the client embeds the container ID directly in the request - a hand-rolled sender will produce untagged traces."
  type = object({
    enabled                       = optional(bool, true)
    socket_enabled                = optional(bool, true)
    tcp_enabled                   = optional(bool, false)
    profiling                     = optional(bool, false)
    trace_inferred_proxy_services = optional(bool, false)
    data_streams                  = optional(bool, false)
  })
  default = {
    enabled                       = true
    socket_enabled                = true
    tcp_enabled                   = false
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
  description = "Configuration for Datadog Log Collection. Datadog does NOT support container log collection through the agent in daemon mode on ECS Managed Instances. This variable exists only so the module can fail fast with a clear error if a user tries to enable it (enforced via a precondition on the daemon task definition). Use FireLens or the awslogs log driver configured on the application's own task definition instead."
  type = object({
    enabled = optional(bool, false)
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

variable "dd_process_collection" {
  description = "Configuration for Datadog Live Process collection. When enabled, sets DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED."
  type = object({
    enabled = optional(bool, false)
  })
  default = {
    enabled = false
  }
  validation {
    condition     = var.dd_process_collection != null
    error_message = "The Datadog Process Collection configuration must be defined."
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

variable "dd_network_monitoring" {
  description = "Configuration for Datadog Cloud Network Monitoring. Linux only. When enabled, adds DD_SYSTEM_PROBE_NETWORK_ENABLED, the linux capabilities required by the system-probe, and a host-mounted /sys/kernel/debug volume."
  type = object({
    enabled = optional(bool, false)
  })
  default = {
    enabled = false
  }
  validation {
    condition     = var.dd_network_monitoring != null
    error_message = "The Datadog Network Monitoring configuration must be defined."
  }
}

variable "dd_cri_socket_path" {
  description = "Path to the containerd socket on the host. ECS Managed Instances uses containerd, not Docker, so this replaces the docker socket path used by the ecs_ec2 module. Defaults to /var/run/containerd/containerd.sock"
  type        = string
  default     = "/var/run/containerd/containerd.sock"
  nullable    = false
}

variable "dd_proc_path" {
  description = "Path to /proc directory on the host. Defaults to /proc/"
  type        = string
  default     = "/proc/"
  nullable    = false
}

variable "dd_cgroup_path" {
  description = "Path to cgroup directory on the host. Defaults to /sys/fs/cgroup/."
  type        = string
  default     = "/sys/fs/cgroup/"
  nullable    = false
}

variable "dd_agent_log_configuration" {
  description = "Log configuration for the Datadog Agent container's OWN logs (not application container logs, which the agent cannot collect in daemon mode on ECS Managed Instances), e.g. routing to CloudWatch via the awslogs driver. Since a failing/unhealthy daemon causes AWS to drain and replace the instance, this is the primary debugging lever available."
  type = object({
    log_driver = optional(string)
    options    = optional(map(string))
    secret_options = optional(list(object({
      name       = string
      value_from = string
    })))
  })
  default = null
}

################################################################################
# Task Definition
################################################################################

variable "family" {
  description = "A unique name for your daemon task definition"
  type        = string
}

variable "cpu" {
  description = "Number of cpu units used by the task, as a string (e.g. \"256\"). Note this is a string on aws_ecs_daemon_task_definition, unlike the number type used by aws_ecs_task_definition in the other submodules."
  type        = string
  default     = null
}

variable "memory" {
  description = "Amount (in MiB) of memory used by the task, as a string (e.g. \"512\"). Note this is a string on aws_ecs_daemon_task_definition, unlike the number type used by aws_ecs_task_definition in the other submodules."
  type        = string
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

variable "tags" {
  description = "A map of additional tags to add to the daemon task definition/daemon created"
  type        = map(string)
  default     = null
}

variable "volumes" {
  description = "A list of additional host-path volume definitions that containers in your task may use, beyond the ones the module manages. Note: the volume block on aws_ecs_daemon_task_definition only supports `name` + `host.source_path` - no docker_volume_configuration/efs/fsx volume types like the other two submodules, so this type is intentionally simpler."
  type = list(object({
    name      = string
    host_path = optional(string)
  }))
  default = []
}

################################################################################
# Daemon
################################################################################

variable "create_daemon" {
  description = "Whether to create the aws_ecs_daemon resource. If false, only the daemon task definition is created."
  type        = bool
  default     = true
  nullable    = false
}

variable "daemon_name" {
  description = "Name of the ECS daemon. Defaults to '<family>-datadog-agent'"
  type        = string
  default     = null
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster where the Datadog agent daemon will run. Required if create_daemon = true."
  type        = string
  default     = null
}

variable "capacity_provider_arns" {
  description = "ARNs of ECS Managed Instances capacity providers the daemon should run on. Required if create_daemon = true. The module does not create the capacity provider, infrastructure role, or instance profile - those must already exist."
  type        = set(string)
  default     = []
}

variable "deployment_configuration" {
  description = "Controls the daemon's rolling deployment behavior across instances. This block is write-only on the AWS side (not readable back from the API), so Terraform plans will always show a diff here - this is expected provider behavior, not a bug. Note: ANY change to the daemon task definition (including something as small as a tag) forces a full replacement and triggers AWS's drain-provision-replace rollout across every instance in the attached capacity providers, so these settings materially affect production availability during that rollout - they are not cosmetic."
  type = object({
    drain_percent        = optional(number, 25)
    bake_time_in_minutes = optional(number, 0)
    alarms = optional(object({
      alarm_names = optional(list(string), [])
      enable      = optional(bool, false)
    }), {})
  })
  default = {}
}

variable "enable_ecs_managed_tags" {
  description = "Enable ECS managed tags for the daemon"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for daemon tasks"
  type        = bool
  default     = false
  nullable    = false
}

variable "propagate_tags" {
  description = "Propagate tags to daemon tasks. Valid values: DAEMON, NONE. Note this differs from the ecs_ec2 module's TASK_DEFINITION/SERVICE/NONE options, since aws_ecs_daemon only supports DAEMON and NONE."
  type        = string
  default     = "DAEMON"
  validation {
    condition     = contains(["DAEMON", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be one of: DAEMON, NONE"
  }
}
