################################################################################
# Datadog ECS Fargate Configuration
################################################################################

variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  default     = null
}

variable "dd_api_key_secret_arn" {
  description = "Datadog API Key Secret ARN"
  type        = string
  default     = null
}

variable "dd_registry" {
  description = "Datadog Agent image registry"
  type        = string
  default     = "public.ecr.aws/datadog/agent"
}

variable "dd_image_version" {
  description = "Datadog Agent image version"
  type        = string
  default     = "latest"
}

variable "dd_site" {
  description = "Datadog Site"
  type        = string
  default     = "datadoghq.com"
}

variable "dd_environment" {
  description = "Datadog Agent container environment variables"
  type        = list(map(string))
  default     = [{}]
}

variable "dd_service" {
  description = "The task service name. Used for tagging (UST)"
  type        = string
  default     = null
}

variable "dd_env" {
  description = "The task environment name. Used for tagging (UST)"
  type        = string
  default     = null
}

variable "dd_version" {
  description = "The task version name. Used for tagging (UST)"
  type        = string
  default     = null
}

variable "dd_dogstatsd" {
  description = "Configuration for Datadog DogStatsD"
  type = object({
    enabled                  = optional(bool, true)
    origin_detection_enabled = optional(bool, true)
    dogstatsd_cardinality    = optional(string, "orchestrator")
    socket_enabled           = optional(bool, true)
  })
  default = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"
    socket_enabled           = true
  }
  validation {
    condition     = var.dd_dogstatsd != null
    error_message = "The Datadog Dogstatsd configuration must be defined."
  }
  validation {
    condition = var.dd_dogstatsd.dogstatsd_cardinality == "low" || var.dd_dogstatsd.dogstatsd_cardinality == "orchestrator" || var.dd_dogstatsd.dogstatsd_cardinality == "high"
    error_message = "The Datadog Dogstatsd cardinality must be one of 'low', 'orchestrator', or 'high'."
  }
}

variable "dd_apm" {
  description = "Configuration for Datadog APM"
  type = object({
    enabled        = optional(bool, true)
    socket_enabled = optional(bool, true)
  })
  default = {
    enabled        = true
    socket_enabled = true
  }
  validation {
    condition     = var.dd_apm != null
    error_message = "The Datadog APM configuration must be defined."
  }
}

################################################################################
# Task Definition
################################################################################

variable "container_definitions" {
  description = "A map of valid [container definitions](http://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html). Please note that you should only provide values that are part of the container definition document"
  type        = any
}

variable "cpu" {
  description = "Number of cpu units used by the task. If the `requires_compatibilities` is `FARGATE` this field is required"
  type        = number
  default     = 512
}

variable "enable_fault_injection" {
  description = "Enables fault injection and allows for fault injection requests to be accepted from the task's containers"
  type        = bool
  default     = false
}

variable "ephemeral_storage" {
  description = "The amount of ephemeral storage to allocate for the task. This parameter is used to expand the total amount of ephemeral storage available, beyond the default amount, for tasks hosted on AWS Fargate"
  type        = any
  default     = {}
}

variable "execution_role_arn" {
  description = "ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume"
  type        = string
  default     = null
}

variable "family" {
  description = "A unique name for your task definition"
  type        = string
}

# Not Fargate Compatible
variable "inference_accelerator" {
  description = "Configuration block(s) with Inference Accelerators settings"
  type        = any
  default     = []
}

# Not Fargate Compatible: must always be "task"
variable "ipc_mode" {
  description = "IPC resource namespace to be used for the containers in the task The valid values are `host`, `task`, and `none`"
  type        = string
  default     = null
}

variable "memory" {
  description = "Amount (in MiB) of memory used by the task. If the `requires_compatibilities` is `FARGATE` this field is required"
  type        = number
  default     = 1024
}

# Not Fargate Compatible: must always be "awsvpc"
variable "network_mode" {
  description = "Docker networking mode to use for the containers in the task. Valid values are `none`, `bridge`, `awsvpc`, and `host`"
  type        = string
  default     = "awsvpc"
}

# Not Fargate Compatible: must always be "task"
variable "pid_mode" {
  description = "Process namespace to use for the containers in the task. The valid values are `host` and `task`"
  type        = string
  default     = "task"
}

# Not Fargate Compatible
variable "placement_constraints" {
  description = "Configuration block for rules that are taken into consideration during task placement (up to max of 10). This is set at the task definition, see `placement_constraints` for setting at the service"
  type = list(object({
    type       = string
    expression = string
  }))
  default = []
}

variable "proxy_configuration" {
  description = "Configuration block for the App Mesh proxy"
  type = object({
    container_name = string
    properties     = map(any)
    type           = optional(string, "APPMESH")
  })
  default = null
}

variable "requires_compatibilities" {
  description = "Set of launch types required by the task. The valid values are `EC2` and `FARGATE`"
  type        = list(string)
  default     = ["FARGATE"]
}

variable "runtime_platform" {
  description = "Configuration block for `runtime_platform` that containers in your task may use"
  type = object({
    cpu_architecture        = string
    operating_system_family = string
  })
  default = {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

variable "skip_destroy" {
  description = "Whether to retain the old revision when the resource is destroyed or replacement is necessary"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of additional tags to add to the task definition/set created"
  type        = map(string)
  default     = {}
}

variable "task_role_arn" {
  description = "The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services"
  type        = string
  default     = null
}

variable "track_latest" {
  description = "Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state"
  type        = bool
  default     = false
}

variable "volumes" {
  description = "Configuration block for volumes that containers in your task may use"
  type        = any
  default     = null
}
