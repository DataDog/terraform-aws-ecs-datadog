# Datadog ECS Fargate Terraform

Use this Terraform module to install Datadog monitoring for AWS ECS Fargate task.

This Terraform module wraps the [aws_ecs_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) resource. It provides the same variable inputs and outputs as the `aws_ecs_task_definition` resource. This module then automatically configures your task definition for Datadog monitoring by:

* Adding the Datadog Agent container
  * Optionally, the Fluentbit log router
  * Optionally, the Cloud Workload Security tracer
* Configuring application containers with necessary volume mounts, environment variables, and log drivers
* Configuring task role and execution role to have proper permissions for Datadog
* Enabling the collection of metrics, traces, and logs to Datadog

## Usage

```hcl
module "ecs_fargate_task" {
  source = "Datadog/ecs-fargate-datadog/aws"

  # Datadog Configuration
  dd_api_key_secret_arn = "arn:aws:secretsmanager:us-east-1:0000000000:secret:example-secret"
  dd_tags               = "team:cont-p, owner:container-monitoring"

  dd_dogstatsd = {
    enabled = true
  }

  dd_apm = {
    enabled = true
  }

  dd_log_collection = {
    enabled = true
  }

  # Task Configuration
  family = "example-app"
  container_definitions = [
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "datadog-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = true,
    }
  ]
  volumes = [
    {
      name = "example-storage"
    },
    {
      name = "other-storage"
    }
  ]
}
```

## Configuration

### Task Definition

This module exposes the same arguments available in the [aws_ecs_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) resource. However, because this module wraps that resource, it cannot support the exact same interface for configuration blocks defined by AWS. Instead, those blocks are represented as variables with nested attributes.

As a result, configuration blocks must now be assigned using an equals sign. For example, `runtime_platform { ... }` becomes `runtime_platform = { ... }`. Additionally, blocks that support multiple instances (such as volumes) should now be provided as a list of objects. Refer to the examples below for more details.

#### aws_ecs_task_definition

```hcl
resource "aws_ecs_task_definition" "example" {
  family = "my-task-family"

  container_definitions = jsonencode([
    {
      "name": "my-container",
      "image": "my-image:latest",
      "mountPoints": [
        {
          "containerPath": "/mnt/data",
          "sourceVolume": "data-volume"
        },
        {
          "containerPath": "/mnt/config",
          "sourceVolume": "config-volume"
        }
      ]
    }
  ])

  volume {
    name = "data-volume"
    host_path = "/data"
  }

  volume {
    name = "config-volume"
    host_path = "/config"
  }

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
}
```

#### datadog ecs fargate task definition

```hcl
resource "datadog_ecs_fargate_task" "example" {
  dd_api_key = "XXXXXXXXXXX"

  family = "my-task-family"

  container_definitions = jsonencode([
    {
      "name": "my-container",
      "image": "my-image:latest",
      "mountPoints": [
        {
          "containerPath": "/mnt/data",
          "sourceVolume": "data-volume"
        },
        {
          "containerPath": "/mnt/config",
          "sourceVolume": "config-volume"
        }
      ]
    }
  ])

  # Instead of defining both volume configuration blocks separately,
  # define both within a list and supply the argument to `volumes`
  volumes = [
    {
      name = "data-volume"
      host_path = "/data"
    },
    {
      name = "data-volume"
      host_path = "/data"
    }
  ]

  # Instead of creating a configuration block for `runtime_platforms`,
  # supply the definition directly to the argument `runtime_platforms`
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
}
```

### Datadog

#### API Keys

To ensure the Datadog Agent operates correctly, a Datadog API key is required. You can generate one by following the instructions in [Generate an API Key](https://docs.datadoghq.com/cloudcraft/getting-started/generate-api-key/). The API key can be supplied either directly as plaintext using the `dd_api_key` argument, or securely via the `dd_api_key_secret_arn` argument, which should reference the ARN of an AWS Secrets Manager secret containing the plaintext key. The module automatically grants the necessary permissions to the ECS task execution role to retrieve the key from Secrets Manager and inject it as an environment variable into the Datadog Agent container.

#### Selecting the Datadog Site

The default Datadog site is `datadoghq.com`. To use a different site set the `DD_SITE` input variable to the desired destination site. See [Getting Started with Datadog Sites](https://docs.datadoghq.com/getting_started/site/) for the available site values.

#### Datadog Configuration

All of the input variables prefixed with `dd` are related to Datadog configuration. In order to further customize the Datadog agent configuration beyond the provided interface in this module, you can use the `dd_environment_variables` input argument to customize the Agent configuration. **Note** that `dd_environment_variables` overwrites any other environment variables with the same keys defined. For more information on Datadog configuration, reference [Amazon ECS on AWS Fargate](https://docs.datadoghq.com/integrations/ecs_fargate/?tab=webui) Datadog documentation.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.77.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.90.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.dd_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.dd_secret_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.new_ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.new_ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.existing_role_dd_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.existing_role_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.new_ecs_task_execution_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.new_role_dd_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.new_role_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.dd_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dd_secret_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_role.ecs_task_exec_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |
| [aws_iam_role.ecs_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_container_definitions"></a> [container\_definitions](#input\_container\_definitions) | A list of valid [container definitions](http://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html). Please note that you should only provide values that are part of the container definition document | `any` | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of cpu units used by the task. If the `requires_compatibilities` is `FARGATE` this field is required | `number` | `512` | no |
| <a name="input_dd_api_key"></a> [dd\_api\_key](#input\_dd\_api\_key) | Datadog API Key | `string` | `null` | no |
| <a name="input_dd_api_key_secret_arn"></a> [dd\_api\_key\_secret\_arn](#input\_dd\_api\_key\_secret\_arn) | Datadog API Key Secret ARN | `string` | `null` | no |
| <a name="input_dd_apm"></a> [dd\_apm](#input\_dd\_apm) | Configuration for Datadog APM | <pre>object({<br/>    enabled        = optional(bool, true)<br/>    socket_enabled = optional(bool, true)<br/>  })</pre> | <pre>{<br/>  "enabled": true,<br/>  "socket_enabled": true<br/>}</pre> | no |
| <a name="input_dd_checks_cardinality"></a> [dd\_checks\_cardinality](#input\_dd\_checks\_cardinality) | Datadog Agent checks cardinality | `string` | `null` | no |
| <a name="input_dd_cluster_name"></a> [dd\_cluster\_name](#input\_dd\_cluster\_name) | Datadog cluster name | `string` | `null` | no |
| <a name="input_dd_cws"></a> [dd\_cws](#input\_dd\_cws) | Configuration for Datadog Cloud Workload Security (CWS) | <pre>object({<br/>    enabled          = bool<br/>    cpu              = optional(number)<br/>    memory_limit_mib = optional(number)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_dogstatsd"></a> [dd\_dogstatsd](#input\_dd\_dogstatsd) | Configuration for Datadog DogStatsD | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    origin_detection_enabled = optional(bool, true)<br/>    dogstatsd_cardinality    = optional(string, "orchestrator")<br/>    socket_enabled           = optional(bool, true)<br/>  })</pre> | <pre>{<br/>  "dogstatsd_cardinality": "orchestrator",<br/>  "enabled": true,<br/>  "origin_detection_enabled": true,<br/>  "socket_enabled": true<br/>}</pre> | no |
| <a name="input_dd_env"></a> [dd\_env](#input\_dd\_env) | The task environment name. Used for tagging (UST) | `string` | `null` | no |
| <a name="input_dd_environment"></a> [dd\_environment](#input\_dd\_environment) | Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module | `list(map(string))` | <pre>[<br/>  {}<br/>]</pre> | no |
| <a name="input_dd_essential"></a> [dd\_essential](#input\_dd\_essential) | Whether the Datadog Agent container is essential | `bool` | `false` | no |
| <a name="input_dd_health_check"></a> [dd\_health\_check](#input\_dd\_health\_check) | Datadog Agent health check configuration | <pre>object({<br/>    command      = optional(list(string))<br/>    interval     = optional(number)<br/>    retries      = optional(number)<br/>    start_period = optional(number)<br/>    timeout      = optional(number)<br/>  })</pre> | <pre>{<br/>  "command": [<br/>    "CMD-SHELL",<br/>    "/probe.sh"<br/>  ],<br/>  "interval": 15,<br/>  "retries": 3,<br/>  "start_period": 60,<br/>  "timeout": 5<br/>}</pre> | no |
| <a name="input_dd_image_version"></a> [dd\_image\_version](#input\_dd\_image\_version) | Datadog Agent image version | `string` | `"latest"` | no |
| <a name="input_dd_is_datadog_dependency_enabled"></a> [dd\_is\_datadog\_dependency\_enabled](#input\_dd\_is\_datadog\_dependency\_enabled) | Whether the Datadog Agent container is a dependency for other containers | `bool` | `false` | no |
| <a name="input_dd_log_collection"></a> [dd\_log\_collection](#input\_dd\_log\_collection) | Configuration for Datadog Log Collection | <pre>object({<br/>    enabled                          = optional(bool, true)<br/>    registry                         = optional(string, "public.ecr.aws/aws-observability/aws-for-fluent-bit")<br/>    image_version                    = optional(string, "stable")<br/>    cpu                              = optional(number)<br/>    memory_limit_mib                 = optional(number)<br/>    is_log_router_essential          = optional(bool, false)<br/>    is_log_router_dependency_enabled = optional(bool, false)<br/>    log_router_health_check = optional(object({<br/>      command      = optional(list(string))<br/>      interval     = optional(number)<br/>      retries      = optional(number)<br/>      start_period = optional(number)<br/>      timeout      = optional(number)<br/>      }),<br/>      {<br/>        command      = ["CMD-SHELL", "exit 0"]<br/>        interval     = 5<br/>        retries      = 3<br/>        start_period = 15<br/>        timeout      = 5<br/>      }<br/>    )<br/>    log_driver_configuration = optional(object({<br/>      host_endpoint = optional(string, "http-intake.logs.datadoghq.com")<br/>      tls           = optional(bool)<br/>      compress      = optional(string)<br/>      service_name  = optional(string)<br/>      source_name   = optional(string)<br/>      message_key   = optional(string)<br/>      }),<br/>      {<br/>        host_endpoint = "http-intake.logs.datadoghq.com"<br/>      }<br/>    )<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "is_log_router_essential": false,<br/>  "log_driver_configuration": {<br/>    "host_endpoint": "http-intake.logs.datadoghq.com"<br/>  }<br/>}</pre> | no |
| <a name="input_dd_registry"></a> [dd\_registry](#input\_dd\_registry) | Datadog Agent image registry | `string` | `"public.ecr.aws/datadog/agent"` | no |
| <a name="input_dd_service"></a> [dd\_service](#input\_dd\_service) | The task service name. Used for tagging (UST) | `string` | `null` | no |
| <a name="input_dd_site"></a> [dd\_site](#input\_dd\_site) | Datadog Site | `string` | `"datadoghq.com"` | no |
| <a name="input_dd_tags"></a> [dd\_tags](#input\_dd\_tags) | Datadog Agent global tags (eg. `key1:value1, key2:value2`) | `string` | `null` | no |
| <a name="input_dd_version"></a> [dd\_version](#input\_dd\_version) | The task version name. Used for tagging (UST) | `string` | `null` | no |
| <a name="input_enable_fault_injection"></a> [enable\_fault\_injection](#input\_enable\_fault\_injection) | Enables fault injection and allows for fault injection requests to be accepted from the task's containers | `bool` | `false` | no |
| <a name="input_ephemeral_storage"></a> [ephemeral\_storage](#input\_ephemeral\_storage) | The amount of ephemeral storage to allocate for the task. This parameter is used to expand the total amount of ephemeral storage available, beyond the default amount, for tasks hosted on AWS Fargate | <pre>object({<br/>    size_in_gib = number<br/>  })</pre> | `null` | no |
| <a name="input_execution_role_arn"></a> [execution\_role\_arn](#input\_execution\_role\_arn) | ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume | `string` | `null` | no |
| <a name="input_family"></a> [family](#input\_family) | A unique name for your task definition | `string` | n/a | yes |
| <a name="input_inference_accelerator"></a> [inference\_accelerator](#input\_inference\_accelerator) | Configuration list with Inference Accelerators settings | <pre>list(object({<br/>    device_name = string<br/>    device_type = string<br/>  }))</pre> | `[]` | no |
| <a name="input_ipc_mode"></a> [ipc\_mode](#input\_ipc\_mode) | IPC resource namespace to be used for the containers in the task The valid values are `host`, `task`, and `none` | `string` | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount (in MiB) of memory used by the task. If the `requires_compatibilities` is `FARGATE` this field is required | `number` | `1024` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | Docker networking mode to use for the containers in the task. Valid values are `none`, `bridge`, `awsvpc`, and `host` | `string` | `"awsvpc"` | no |
| <a name="input_pid_mode"></a> [pid\_mode](#input\_pid\_mode) | Process namespace to use for the containers in the task. The valid values are `host` and `task` | `string` | `"task"` | no |
| <a name="input_placement_constraints"></a> [placement\_constraints](#input\_placement\_constraints) | Configuration list for rules that are taken into consideration during task placement (up to max of 10) | <pre>list(object({<br/>    type       = string<br/>    expression = string<br/>  }))</pre> | `[]` | no |
| <a name="input_proxy_configuration"></a> [proxy\_configuration](#input\_proxy\_configuration) | Configuration for the App Mesh proxy | <pre>object({<br/>    container_name = string<br/>    properties     = map(any)<br/>    type           = optional(string, "APPMESH")<br/>  })</pre> | `null` | no |
| <a name="input_requires_compatibilities"></a> [requires\_compatibilities](#input\_requires\_compatibilities) | Set of launch types required by the task. The valid values are `EC2` and `FARGATE` | `list(string)` | <pre>[<br/>  "FARGATE"<br/>]</pre> | no |
| <a name="input_runtime_platform"></a> [runtime\_platform](#input\_runtime\_platform) | Configuration for `runtime_platform` that containers in your task may use | <pre>object({<br/>    cpu_architecture        = optional(string, "LINUX")<br/>    operating_system_family = optional(string, "X86_64")<br/>  })</pre> | <pre>{<br/>  "cpu_architecture": "X86_64",<br/>  "operating_system_family": "LINUX"<br/>}</pre> | no |
| <a name="input_skip_destroy"></a> [skip\_destroy](#input\_skip\_destroy) | Whether to retain the old revision when the resource is destroyed or replacement is necessary | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of additional tags to add to the task definition/set created | `map(string)` | `null` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services | `string` | `null` | no |
| <a name="input_track_latest"></a> [track\_latest](#input\_track\_latest) | Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state | `bool` | `false` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | A list of volume definitions that containers in your task may use | <pre>list(object({<br/>    name                = string<br/>    host_path           = optional(string)<br/>    configure_at_launch = optional(bool)<br/><br/>    docker_volume_configuration = optional(object({<br/>      autoprovision = optional(bool)<br/>      driver        = optional(string)<br/>      driver_opts   = optional(map(any))<br/>      labels        = optional(map(any))<br/>      scope         = optional(string)<br/>    }))<br/><br/>    efs_volume_configuration = optional(object({<br/>      file_system_id          = string<br/>      root_directory          = optional(string)<br/>      transit_encryption      = optional(string)<br/>      transit_encryption_port = optional(number)<br/>      authorization_config = optional(object({<br/>        access_point_id = optional(string)<br/>        iam             = optional(string)<br/>      }))<br/>    }))<br/><br/>    fsx_windows_file_server_volume_configuration = optional(object({<br/>      file_system_id = string<br/>      root_directory = optional(string)<br/>      authorization_config = optional(object({<br/>        credentials_parameter = string<br/>        domain                = string<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | Full ARN of the Task Definition (including both family and revision). |
| <a name="output_arn_without_revision"></a> [arn\_without\_revision](#output\_arn\_without\_revision) | ARN of the Task Definition with the trailing revision removed. |
| <a name="output_container_definitions"></a> [container\_definitions](#output\_container\_definitions) | A list of valid container definitions provided as a single valid JSON document. |
| <a name="output_cpu"></a> [cpu](#output\_cpu) | Number of cpu units used by the task. |
| <a name="output_enable_fault_injection"></a> [enable\_fault\_injection](#output\_enable\_fault\_injection) | Enables fault injection and allows for fault injection requests to be accepted from the task's containers. |
| <a name="output_ephemeral_storage"></a> [ephemeral\_storage](#output\_ephemeral\_storage) | The amount of ephemeral storage to allocate for the task. |
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | ARN of the task execution role. |
| <a name="output_family"></a> [family](#output\_family) | A unique name for your task definition. |
| <a name="output_inference_accelerator"></a> [inference\_accelerator](#output\_inference\_accelerator) | Inference accelerator settings. |
| <a name="output_ipc_mode"></a> [ipc\_mode](#output\_ipc\_mode) | IPC resource namespace to be used for the containers. |
| <a name="output_memory"></a> [memory](#output\_memory) | Amount (in MiB) of memory used by the task. |
| <a name="output_network_mode"></a> [network\_mode](#output\_network\_mode) | Docker networking mode to use for the containers. |
| <a name="output_pid_mode"></a> [pid\_mode](#output\_pid\_mode) | Process namespace to use for the containers. |
| <a name="output_placement_constraints"></a> [placement\_constraints](#output\_placement\_constraints) | Rules that are taken into consideration during task placement. |
| <a name="output_proxy_configuration"></a> [proxy\_configuration](#output\_proxy\_configuration) | Configuration block for the App Mesh proxy. |
| <a name="output_requires_compatibilities"></a> [requires\_compatibilities](#output\_requires\_compatibilities) | Set of launch types required by the task. |
| <a name="output_revision"></a> [revision](#output\_revision) | Revision of the task in a particular family. |
| <a name="output_runtime_platform"></a> [runtime\_platform](#output\_runtime\_platform) | Runtime platform configuration for the task definition. |
| <a name="output_skip_destroy"></a> [skip\_destroy](#output\_skip\_destroy) | Whether to retain the old revision when the resource is destroyed or replacement is necessary. |
| <a name="output_tags"></a> [tags](#output\_tags) | Key-value map of resource tags. |
| <a name="output_tags_all"></a> [tags\_all](#output\_tags\_all) | Map of tags assigned to the resource, including inherited tags. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services. |
| <a name="output_track_latest"></a> [track\_latest](#output\_track\_latest) | Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state. |
| <a name="output_volume"></a> [volume](#output\_volume) | Configuration block for volumes that containers in your task may use. |
<!-- END_TF_DOCS -->