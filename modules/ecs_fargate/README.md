# Datadog ECS Fargate Terraform

Use this Terraform module to install Datadog monitoring for AWS ECS Fargate tasks. If you encounter any issues, please open a GitHub issue to let us know.

This Terraform module wraps the [aws_ecs_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) resource. It provides the same variable inputs and outputs as the `aws_ecs_task_definition` resource. This module then automatically configures your task definition for Datadog monitoring by:

- Adding the Datadog Agent container
  - Optionally, the Fluentbit log router
  - Optionally, the Cloud Workload Security tracer
- Configuring application containers with necessary volume mounts, environment variables, and log drivers
- Configuring task role and execution role to have proper permissions for Datadog
- Enabling the collection of metrics, traces, and logs to Datadog

## Usage

```hcl
module "ecs_fargate_task" {
  source  = "DataDog/ecs-datadog/aws//modules/ecs_fargate"

  # Datadog Configuration
  dd_api_key_secret = {
    arn = "arn:aws:secretsmanager:us-east-1:0000000000:secret:example-secret"
  }
  dd_tags = "team:cont-p, owner:container-monitoring"

  dd_dogstatsd = {
    enabled = true
  }

  dd_apm = {
    enabled = true
  }

  dd_log_collection = {
    enabled = true
    fluentbit_config = {
      # Optional: Mount additional volumes to the log router
      mountPoints = [
        {
          sourceVolume  = "config-volume"
          containerPath = "/fluent-bit/config"
          readOnly      = true
        }
      ]
      # Optional: Add dependencies for the log router
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
    }
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

As a result, configuration blocks must now be assigned using an equals sign. For example, `runtime_platform { ... }` becomes `runtime_platform = { ... }`. Additionally, blocks that support multiple instances (such as volumes) should now be provided as a list of objects.

One other minor difference is related to the way the `task_role_arn` and the `execution_role_arn` are provided. Instead of directly providing the value like `task_role_arn = "xxxxxx"`, you must provide the value wrapped in an object like `task_role = { arn = "xxxxxx" }`.

Refer to the examples below for more details.

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

  task_role_arn = "arn:aws:iam::123456789012:role/my-example-role"
}
```

#### datadog ecs fargate task definition

```hcl
resource "datadog_ecs_fargate_task" "example" {
  source  = "DataDog/ecs-datadog/aws//modules/ecs_fargate"

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
    },
    {
      name = "config-volume"
    }
  ]

  # Instead of creating a configuration block for `runtime_platform`,
  # supply the definition directly to the argument `runtime_platform`
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # Instead of supplying the `task_role_arn` directly,
  # provide it into the `arn` field of the `task_role` object.
  task_role = {
    arn = "arn:aws:iam::123456789012:role/my-example-role"
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

#### DogStatsD

The `dd_dogstatsd` configuration block controls the [DogStatsD server](https://docs.datadoghq.com/developers/dogstatsd/?tab=containeragent#datadog-agent-dogstatsd-server), which collects custom metrics from your applications.

*   `enabled` (default: `true`): Enables the DogStatsD server.
*   `origin_detection_enabled` (default: `true`): Enables origin detection, which allows DogStatsD to automatically detect the container where the metrics originated and tag them accordingly.
*   `dogstatsd_cardinality` (default: `orchestrator`): Sets tag cardinality (`low`, `orchestrator`, or `high`). Use `orchestrator` for task-level tags or `high` for granular tagging (may impact costs).
*   `socket_enabled` (default: `true`): Enables DogStatsD over a Unix Domain Socket. Adds relevant volumes, mounts, and environment variables. This is the recommended communication method on Fargate as it avoids networking overhead and simplifies origin detection.

For the full list of configuration options, reference the [inputs](#inputs).

#### APM (Application Performance Monitoring)

The `dd_apm` configuration block controls the Datadog Trace Agent, which collects traces from your instrumented applications.

*   `enabled` (default: `true`): Enables the Trace Agent.
*   `socket_enabled` (default: `true`): Enables APM over a Unix Domain Socket. Adds relevant volumes, mounts, and environment variables. Similar to DogStatsD, this is the preferred method for Fargate tasks to communicate trace data to the Agent.

For the full list of configuration options, reference the [inputs](#inputs).

#### Log Collection

The `dd_log_collection` configuration block sets up log collection using the [AWS FireLens log driver](https://docs.datadoghq.com/integrations/aws-fargate/?tab=webui#log-collection) with Fluent Bit.

*   `enabled` (default: `false`): Enables log collection. When enabled, a Fluent Bit sidecar container is added to your task to route logs to Datadog and the log driver configuration is added to all containers.
*   `fluentbit_config` (optional): Configuration for the Fluent Bit log router and Firelens log driver.
    *   `is_log_router_essential` (default: `false`): Marks the log router as an essential container.
    *   `is_log_router_dependency_enabled` (default: `false`): Adds a dependency so application containers start only after the log router is healthy. This ensures no logs are missed during startup.
    *   `log_driver_configuration` (optional): Configuration for the [Datadog fluentbit output plugin](https://docs.fluentbit.io/manual/data-pipeline/outputs/datadog).

**Note**: enabling this feature automatically applies a log driver configuration to your application containers based on the settings in `dd_log_collection.fluentbit_config.log_driver_configuration`. Use this block to customize the Datadog output plugin parameters, such as `service_name`, `source_name`, `message_key`, `tls`, `compress`, and `host_endpoint`.

For the full list of configuration options, reference the [inputs](#inputs).

### Miscellaneous

To support Process monitoring with the Datadog Agent, the Fargate task must run with `pid_mode` set to `task`. This configuration, however, results in a bug limiting `exec` access onto only one container in the task. For more information, see the [related github issue](https://github.com/aws/containers-roadmap/issues/2268). If you require exec access, you can explicitly set the `pid_mode` to `null`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.85.0 |

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
| [aws_iam_role_policy_attachment.new_role_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.dd_ecs_task_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dd_secret_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_container_definitions"></a> [container\_definitions](#input\_container\_definitions) | A list of valid [container definitions](http://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html). Please note that you should only provide values that are part of the container definition document | `any` | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of cpu units used by the task. If the `requires_compatibilities` is `FARGATE` this field is required | `number` | `256` | no |
| <a name="input_dd_api_key"></a> [dd\_api\_key](#input\_dd\_api\_key) | Datadog API Key | `string` | `null` | no |
| <a name="input_dd_api_key_secret"></a> [dd\_api\_key\_secret](#input\_dd\_api\_key\_secret) | Datadog API Key Secret ARN | <pre>object({<br/>    arn = string<br/>  })</pre> | `null` | no |
| <a name="input_dd_apm"></a> [dd\_apm](#input\_dd\_apm) | Configuration for Datadog APM | <pre>object({<br/>    enabled                       = optional(bool, true)<br/>    socket_enabled                = optional(bool, true)<br/>    profiling                     = optional(bool, false)<br/>    trace_inferred_proxy_services = optional(bool, false)<br/>    data_streams                  = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "data_streams_enabled": false,<br/>  "enabled": true,<br/>  "profiling": false,<br/>  "socket_enabled": true,<br/>  "trace_inferred_proxy_services": false<br/>}</pre> | no |
| <a name="input_dd_checks_cardinality"></a> [dd\_checks\_cardinality](#input\_dd\_checks\_cardinality) | Datadog Agent checks cardinality | `string` | `null` | no |
| <a name="input_dd_cluster_name"></a> [dd\_cluster\_name](#input\_dd\_cluster\_name) | Datadog cluster name | `string` | `null` | no |
| <a name="input_dd_cpu"></a> [dd\_cpu](#input\_dd\_cpu) | Datadog Agent container CPU units | `number` | `null` | no |
| <a name="input_dd_cws"></a> [dd\_cws](#input\_dd\_cws) | Configuration for Datadog Cloud Workload Security (CWS) | <pre>object({<br/>    enabled          = optional(bool, false)<br/>    cpu              = optional(number)<br/>    memory_limit_mib = optional(number)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_docker_labels"></a> [dd\_docker\_labels](#input\_dd\_docker\_labels) | Datadog Agent container docker labels | `map(string)` | `{}` | no |
| <a name="input_dd_dogstatsd"></a> [dd\_dogstatsd](#input\_dd\_dogstatsd) | Configuration for Datadog DogStatsD | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    origin_detection_enabled = optional(bool, true)<br/>    dogstatsd_cardinality    = optional(string, "orchestrator")<br/>    socket_enabled           = optional(bool, true)<br/>  })</pre> | <pre>{<br/>  "dogstatsd_cardinality": "orchestrator",<br/>  "enabled": true,<br/>  "origin_detection_enabled": true,<br/>  "socket_enabled": true<br/>}</pre> | no |
| <a name="input_dd_env"></a> [dd\_env](#input\_dd\_env) | The task environment name. Used for tagging (UST) for application containers. To apply the `dd_env` tag to the Datadog Agent sidecar container, set `dd_docker_labels = { "com.datadoghq.tags.env" = var.dd_env}`. | `string` | `null` | no |
| <a name="input_dd_environment"></a> [dd\_environment](#input\_dd\_environment) | Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module. For example, `dd_environment = [ { name = 'DD_VAR', value = 'DD_VAL' } ]` | `list(map(string))` | <pre>[<br/>  {}<br/>]</pre> | no |
| <a name="input_dd_essential"></a> [dd\_essential](#input\_dd\_essential) | Whether the Datadog Agent container is essential | `bool` | `false` | no |
| <a name="input_dd_health_check"></a> [dd\_health\_check](#input\_dd\_health\_check) | Datadog Agent health check configuration | <pre>object({<br/>    command      = optional(list(string))<br/>    interval     = optional(number)<br/>    retries      = optional(number)<br/>    start_period = optional(number)<br/>    timeout      = optional(number)<br/>  })</pre> | <pre>{<br/>  "command": [<br/>    "CMD-SHELL",<br/>    "/probe.sh"<br/>  ],<br/>  "interval": 15,<br/>  "retries": 3,<br/>  "start_period": 60,<br/>  "timeout": 5<br/>}</pre> | no |
| <a name="input_dd_image_version"></a> [dd\_image\_version](#input\_dd\_image\_version) | Datadog Agent image version | `string` | `"latest"` | no |
| <a name="input_dd_is_datadog_dependency_enabled"></a> [dd\_is\_datadog\_dependency\_enabled](#input\_dd\_is\_datadog\_dependency\_enabled) | Whether the Datadog Agent container is a dependency for other containers | `bool` | `false` | no |
| <a name="input_dd_log_collection"></a> [dd\_log\_collection](#input\_dd\_log\_collection) | Configuration for Datadog Log Collection | <pre>object({<br/>    enabled = optional(bool, false)<br/>    fluentbit_config = optional(object({<br/>      registry                         = optional(string, "public.ecr.aws/aws-observability/aws-for-fluent-bit")<br/>      image_version                    = optional(string, "stable")<br/>      cpu                              = optional(number)<br/>      memory_limit_mib                 = optional(number)<br/>      is_log_router_essential          = optional(bool, false)<br/>      is_log_router_dependency_enabled = optional(bool, false)<br/>      environment = optional(list(object({<br/>        name  = string<br/>        value = string<br/>      })), [])<br/>      log_router_health_check = optional(object({<br/>        command      = optional(list(string))<br/>        interval     = optional(number)<br/>        retries      = optional(number)<br/>        start_period = optional(number)<br/>        timeout      = optional(number)<br/>        }),<br/>        {<br/>          command      = ["CMD-SHELL", "exit 0"]<br/>          interval     = 5<br/>          retries      = 3<br/>          start_period = 15<br/>          timeout      = 5<br/>        }<br/>      )<br/>      firelens_options = optional(object({<br/>        config_file_type  = optional(string)<br/>        config_file_value = optional(string)<br/>      }))<br/>      log_driver_configuration = optional(object({<br/>        host_endpoint = optional(string, "http-intake.logs.datadoghq.com")<br/>        tls           = optional(bool)<br/>        compress      = optional(string)<br/>        service_name  = optional(string)<br/>        source_name   = optional(string)<br/>        message_key   = optional(string)<br/>        }),<br/>        {<br/>          host_endpoint = "http-intake.logs.datadoghq.com"<br/>        }<br/>      )<br/>      mountPoints = optional(list(object({<br/>        sourceVolume : string,<br/>        containerPath : string,<br/>        readOnly : bool<br/>      })), [])<br/>      dependsOn = optional(list(object({<br/>        containerName : string,<br/>        condition : string<br/>      })), [])<br/>      }),<br/>      {<br/>        fluentbit_config = {<br/>          registry      = "public.ecr.aws/aws-observability/aws-for-fluent-bit"<br/>          image_version = "stable"<br/>          log_driver_configuration = {<br/>            host_endpoint = "http-intake.logs.datadoghq.com"<br/>          }<br/>        }<br/>      }<br/>    )<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "fluentbit_config": {<br/>    "is_log_router_essential": false,<br/>    "log_driver_configuration": {<br/>      "host_endpoint": "http-intake.logs.datadoghq.com"<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_dd_memory_limit_mib"></a> [dd\_memory\_limit\_mib](#input\_dd\_memory\_limit\_mib) | Datadog Agent container memory limit in MiB | `number` | `null` | no |
| <a name="input_dd_orchestrator_explorer"></a> [dd\_orchestrator\_explorer](#input\_dd\_orchestrator\_explorer) | Configuration for Datadog Orchestrator Explorer | <pre>object({<br/>    enabled = optional(bool, true)<br/>    url     = optional(string)<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_dd_readonly_root_filesystem"></a> [dd\_readonly\_root\_filesystem](#input\_dd\_readonly\_root\_filesystem) | Datadog Agent container runs with read-only root filesystem enabled | `bool` | `false` | no |
| <a name="input_dd_registry"></a> [dd\_registry](#input\_dd\_registry) | Datadog Agent image registry | `string` | `"public.ecr.aws/datadog/agent"` | no |
| <a name="input_dd_service"></a> [dd\_service](#input\_dd\_service) | The task service name. Used for tagging (UST) | `string` | `null` | no |
| <a name="input_dd_site"></a> [dd\_site](#input\_dd\_site) | Datadog Site | `string` | `"datadoghq.com"` | no |
| <a name="input_dd_tags"></a> [dd\_tags](#input\_dd\_tags) | Datadog Agent global tags (eg. `key1:value1, key2:value2`) | `string` | `null` | no |
| <a name="input_dd_version"></a> [dd\_version](#input\_dd\_version) | The task version name. Used for tagging (UST) | `string` | `null` | no |
| <a name="input_enable_fault_injection"></a> [enable\_fault\_injection](#input\_enable\_fault\_injection) | Enables fault injection and allows for fault injection requests to be accepted from the task's containers | `bool` | `false` | no |
| <a name="input_ephemeral_storage"></a> [ephemeral\_storage](#input\_ephemeral\_storage) | The amount of ephemeral storage to allocate for the task. This parameter is used to expand the total amount of ephemeral storage available, beyond the default amount, for tasks hosted on AWS Fargate | <pre>object({<br/>    size_in_gib = number<br/>  })</pre> | `null` | no |
| <a name="input_execution_role"></a> [execution\_role](#input\_execution\_role) | ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch container and cluster metadata. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_family"></a> [family](#input\_family) | A unique name for your task definition | `string` | n/a | yes |
| <a name="input_inference_accelerator"></a> [inference\_accelerator](#input\_inference\_accelerator) | Configuration list with Inference Accelerators settings | <pre>list(object({<br/>    device_name = string<br/>    device_type = string<br/>  }))</pre> | `[]` | no |
| <a name="input_ipc_mode"></a> [ipc\_mode](#input\_ipc\_mode) | IPC resource namespace to be used for the containers in the task The valid values are `host`, `task`, and `none` | `string` | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount (in MiB) of memory used by the task. If the `requires_compatibilities` is `FARGATE` this field is required | `number` | `512` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | Docker networking mode to use for the containers in the task. Valid values are `none`, `bridge`, `awsvpc`, and `host` | `string` | `"awsvpc"` | no |
| <a name="input_pid_mode"></a> [pid\_mode](#input\_pid\_mode) | Process namespace to use for the containers in the task. The valid values are `host` and `task` | `string` | `"task"` | no |
| <a name="input_placement_constraints"></a> [placement\_constraints](#input\_placement\_constraints) | Configuration list for rules that are taken into consideration during task placement (up to max of 10) | <pre>list(object({<br/>    type       = string<br/>    expression = string<br/>  }))</pre> | `[]` | no |
| <a name="input_proxy_configuration"></a> [proxy\_configuration](#input\_proxy\_configuration) | Configuration for the App Mesh proxy | <pre>object({<br/>    container_name = string<br/>    properties     = map(any)<br/>    type           = optional(string, "APPMESH")<br/>  })</pre> | `null` | no |
| <a name="input_requires_compatibilities"></a> [requires\_compatibilities](#input\_requires\_compatibilities) | Set of launch types required by the task. The valid values are `EC2` and `FARGATE` | `list(string)` | <pre>[<br/>  "FARGATE"<br/>]</pre> | no |
| <a name="input_runtime_platform"></a> [runtime\_platform](#input\_runtime\_platform) | Configuration for `runtime_platform` that containers in your task may use | <pre>object({<br/>    cpu_architecture        = optional(string, "LINUX")<br/>    operating_system_family = optional(string, "X86_64")<br/>  })</pre> | <pre>{<br/>  "cpu_architecture": "X86_64",<br/>  "operating_system_family": "LINUX"<br/>}</pre> | no |
| <a name="input_skip_destroy"></a> [skip\_destroy](#input\_skip\_destroy) | Whether to retain the old revision when the resource is destroyed or replacement is necessary | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of additional tags to add to the task definition/set created | `map(string)` | `null` | no |
| <a name="input_task_role"></a> [task\_role](#input\_task\_role) | The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch a provided Datadog API key secret. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
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
