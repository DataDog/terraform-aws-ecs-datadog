# ECS on EC2 Module for Datadog Agent

This Terraform module deploys the Datadog Agent as a **daemon service** on Amazon ECS clusters running on EC2 instances. The daemon scheduling strategy ensures that one Datadog Agent runs on each EC2 instance in your cluster, providing comprehensive monitoring for all containers on that instance.

## Key Features

- **Daemon Service**: Automatically runs one Datadog Agent per EC2 instance
- **Full Observability**: Core infrastructure monitoring, DogStatsD metrics, APM traces, and log collection
- **Flexible Configuration**: Optional service creation, customizable network modes, and IAM role management
- **Easy Integration**: Helper outputs provide ready-to-use environment variables for your application tasks

## Architecture

Unlike the Fargate module which deploys the agent as a sidecar container in each task, this module creates a single daemon service that monitors all containers on each EC2 instance through:

- Docker socket access (`/var/run/docker.sock`)
- Host process information (`/proc`)
- Cgroup metrics (`/sys/fs/cgroup`)

By default, application containers communicate with the agent over **Unix Domain Sockets (UDS)** via a shared volume mount. Port-based communication (DogStatsD on port 8125, APM on port 8126) is available as a fallback when UDS is disabled.

## Quick Start

### Basic Usage

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # Datadog Configuration
  dd_api_key_secret = {
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:datadog-api-key"
  }
  dd_site         = "datadoghq.com"
  dd_cluster_name = "my-ecs-cluster"

  # Task Definition
  family = "datadog-agent-daemon"

  # Daemon Service
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### Minimal Configuration (Task Definition Only)

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  dd_api_key    = var.datadog_api_key
  dd_site       = "datadoghq.com"
  family        = "datadog-agent-daemon"
  create_service = false  # Only create task definition
}

# Create the daemon service separately
resource "aws_ecs_service" "datadog_agent" {
  name                = "datadog-agent"
  cluster             = var.cluster_arn
  task_definition     = module.datadog_agent.arn
  scheduling_strategy = "DAEMON"
}
```

## User Task Configuration

Your application tasks need to be configured to send metrics and traces to the Datadog Agent daemon. The module provides helper outputs to make this easy.

### Example: Application Task with DogStatsD and APM (UDS)

By default, UDS is enabled. Your application task needs a shared volume mount and the appropriate environment variables:

```hcl
resource "aws_ecs_task_definition" "app" {
  family       = "my-app"
  network_mode = "bridge"

  # Add the shared UDS socket volume
  volume {
    name      = module.datadog_agent.app_dd_sockets_volume.name
    host_path = module.datadog_agent.app_dd_sockets_volume.host_path
  }

  container_definitions = jsonencode([{
    name  = "app"
    image = "my-app:latest"

    # Use module outputs for easy configuration
    environment = concat(
      module.datadog_agent.dogstatsd_env_vars,
      module.datadog_agent.apm_env_vars,
      [
        {
          name  = "MY_APP_CONFIG"
          value = "value"
        }
      ]
    )

    # Mount the shared UDS socket directory
    mountPoints = [module.datadog_agent.app_dd_sockets_mount]

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
  }])
}
```

### Available Helper Outputs

The module provides these outputs for easy integration:

- **`dogstatsd_env_vars`**: Environment variables for DogStatsD (sets `DD_DOGSTATSD_URL` to the UDS socket path when enabled)
- **`apm_env_vars`**: Environment variables for APM (sets `DD_TRACE_AGENT_URL` to the UDS socket path when enabled)
- **`app_dd_sockets_volume`**: Volume definition for the shared UDS socket directory — add to your task definition's `volume` blocks
- **`app_dd_sockets_mount`**: Mount point for the shared UDS socket directory — add to your application container's `mountPoints`
- **`profiling_env_vars`**: Environment variables for continuous profiling (when enabled)
- **`data_streams_env_vars`**: Environment variables for Data Streams Monitoring (when enabled)
- **`trace_inferred_proxy_env_vars`**: Environment variables for trace inferred proxy services (when enabled)

## Network Modes

### Bridge Mode (Default, Recommended)

The default network mode provides container isolation while allowing communication with the agent.

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...
  network_mode = "bridge"  # Default
}
```

**How it works:**

- Agent communicates with application containers via **UDS** (default) through a shared socket volume
- When UDS is disabled, application containers use port-based communication with `DD_AGENT_HOST` set to the EC2 metadata endpoint
- Provides network isolation between containers

### Host Mode (Alternative)

For simpler configuration with less isolation:

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...
  network_mode = "host"
}
```

**How it works:**

- Agent uses host network namespace
- Application containers use `DD_AGENT_HOST=127.0.0.1`
- Less network isolation

## Features

### Core Monitoring

Enabled by default. Collects infrastructure metrics from EC2 instances and ECS containers.

### DogStatsD

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_dogstatsd = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"  # low, orchestrator, or high
  }
}
```

### APM (Application Performance Monitoring)

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_apm = {
    enabled                       = true
    profiling                     = true
    trace_inferred_proxy_services = false
    data_streams                  = true
  }
}
```

### Log Collection

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_log_collection = {
    enabled               = true
    container_collect_all = true
    container_include     = []  # Optional: specific container names
    container_exclude     = []  # Optional: exclude container names
  }
}
```

## IAM Roles

The module manages two IAM roles:

### Task Execution Role

Used by ECS to pull container images and access secrets.

**Auto-created** if not provided. Includes:

- `AmazonECSTaskExecutionRolePolicy` (AWS managed)
- Secrets Manager access (if using `dd_api_key_secret`)

**User-provided example:**

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  execution_role = {
    arn                    = aws_iam_role.my_exec_role.arn
    add_dd_ecs_permissions = true  # Attach Datadog-specific policies
  }
}
```

### Task Role

Used by the Datadog Agent to query ECS and EC2 APIs.

**Auto-created** if not provided. Includes permissions for:

- `ecs:ListClusters`, `ecs:ListContainerInstances`, `ecs:DescribeContainerInstances`
- `ecs:DescribeTasks`, `ecs:ListTasks`
- `ec2:DescribeInstances`, `ec2:DescribeTags`

### EC2 Instance IAM Role

**Not managed by this module.** Your EC2 container instances must have an IAM role with:

- AWS managed policy: `AmazonEC2ContainerServiceforEC2Role`
- Permissions to pull images from ECR (if applicable)

## Service Configuration

### Placement Constraints

Restrict which EC2 instances run the Datadog Agent:

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  service_placement_constraints = [
    {
      type       = "memberOf"
      expression = "attribute:ecs.instance-type =~ t3.*"
    },
    {
      type       = "memberOf"
      expression = "attribute:ecs.availability-zone != us-east-1a"
    }
  ]
}
```

### Service Discovery

Register the agent with AWS Cloud Map:

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  service_registries = {
    registry_arn   = aws_service_discovery_service.datadog.arn
    container_name = "datadog-agent"
  }
}
```

## Advanced Configuration

### Custom Volume Paths

For non-standard Docker installations:

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_docker_socket_path = "/var/run/docker.sock"
  dd_proc_path          = "/proc/"
  dd_cgroup_path        = "/sys/fs/cgroup/"
}
```

### Logging Verbosity

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_log_level = "debug"  # trace, debug, info, warn, error, critical, off
}
```

### Health Checks

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_ec2"

  # ... other config ...

  dd_health_check = {
    command      = ["CMD-SHELL", "/probe.sh"]
    interval     = 15
    timeout      = 5
    retries      = 3
    start_period = 60
  }
}
```

## Complete Example

See the [examples/ecs_ec2](../../examples/ecs_ec2) directory for a complete working example that includes:

- Datadog Agent daemon service with all features enabled
- Sample application task definition
- ECS service for the application
- Proper IAM role configuration

## Troubleshooting

### Agent Not Starting

1. **Check IAM permissions**: Ensure the task execution role can pull images
2. **Verify API key**: Check that the secret ARN is correct and accessible
3. **Review logs**: Check ECS console for container startup errors

### Metrics Not Appearing

1. **Verify agent is running**: Check ECS service status
2. **Check application configuration**: Ensure UDS socket volume is mounted and `DD_DOGSTATSD_URL` / `DD_TRACE_AGENT_URL` are set (or `DD_AGENT_HOST` if using port-based communication)
3. **Socket mount**: Verify the shared socket volume is present in both the agent and application task definitions
4. **Review agent logs**: Check for connection errors

### Log Collection Not Working

1. **Verify Docker socket mount**: Ensure `/var/run/docker.sock` is accessible
2. **Check permissions**: Agent needs read access to Docker socket
3. **Enable log collection**: Set `dd_log_collection.enabled = true`
4. **Review agent configuration**: Check `DD_LOGS_ENABLED` environment variable

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
| [aws_ecs_service.datadog_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.datadog_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
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
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the ECS cluster where the Datadog agent daemon service will run. Required if create\_service = true. | `string` | `null` | no |
| <a name="input_create_service"></a> [create\_service](#input\_create\_service) | Whether to create the ECS daemon service. If false, only the task definition is created. | `bool` | `true` | no |
| <a name="input_dd_api_key"></a> [dd\_api\_key](#input\_dd\_api\_key) | Datadog API Key | `string` | `null` | no |
| <a name="input_dd_api_key_secret"></a> [dd\_api\_key\_secret](#input\_dd\_api\_key\_secret) | Datadog API Key Secret ARN | <pre>object({<br/>    arn = string<br/>  })</pre> | `null` | no |
| <a name="input_dd_apm"></a> [dd\_apm](#input\_dd\_apm) | Configuration for Datadog APM | <pre>object({<br/>    enabled                       = optional(bool, true)<br/>    socket_enabled                = optional(bool, true)<br/>    profiling                     = optional(bool, false)<br/>    trace_inferred_proxy_services = optional(bool, false)<br/>    data_streams                  = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "data_streams": false,<br/>  "enabled": true,<br/>  "profiling": false,<br/>  "socket_enabled": true,<br/>  "trace_inferred_proxy_services": false<br/>}</pre> | no |
| <a name="input_dd_cgroup_path"></a> [dd\_cgroup\_path](#input\_dd\_cgroup\_path) | Path to cgroup directory on the host. Defaults to /sys/fs/cgroup/. Use /cgroup/ for Amazon Linux 1 instances. | `string` | `"/sys/fs/cgroup/"` | no |
| <a name="input_dd_checks_cardinality"></a> [dd\_checks\_cardinality](#input\_dd\_checks\_cardinality) | Datadog Agent checks cardinality | `string` | `null` | no |
| <a name="input_dd_cluster_name"></a> [dd\_cluster\_name](#input\_dd\_cluster\_name) | Datadog cluster name | `string` | `null` | no |
| <a name="input_dd_cpu"></a> [dd\_cpu](#input\_dd\_cpu) | Datadog Agent container CPU units | `number` | `256` | no |
| <a name="input_dd_docker_labels"></a> [dd\_docker\_labels](#input\_dd\_docker\_labels) | Datadog Agent container docker labels | `map(string)` | `{}` | no |
| <a name="input_dd_docker_socket_path"></a> [dd\_docker\_socket\_path](#input\_dd\_docker\_socket\_path) | Path to Docker socket on the host. Defaults to /var/run/docker.sock | `string` | `"/var/run/docker.sock"` | no |
| <a name="input_dd_dogstatsd"></a> [dd\_dogstatsd](#input\_dd\_dogstatsd) | Configuration for Datadog DogStatsD | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    origin_detection_enabled = optional(bool, true)<br/>    dogstatsd_cardinality    = optional(string, "orchestrator")<br/>    socket_enabled           = optional(bool, true)<br/>  })</pre> | <pre>{<br/>  "dogstatsd_cardinality": "orchestrator",<br/>  "enabled": true,<br/>  "origin_detection_enabled": true,<br/>  "socket_enabled": true<br/>}</pre> | no |
| <a name="input_dd_environment"></a> [dd\_environment](#input\_dd\_environment) | Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module. For example, `dd_environment = [ { name = 'DD_VAR', value = 'DD_VAL' } ]` | `list(map(string))` | <pre>[<br/>  {}<br/>]</pre> | no |
| <a name="input_dd_essential"></a> [dd\_essential](#input\_dd\_essential) | Whether the Datadog Agent container is essential | `bool` | `true` | no |
| <a name="input_dd_health_check"></a> [dd\_health\_check](#input\_dd\_health\_check) | Datadog Agent health check configuration | <pre>object({<br/>    command      = optional(list(string))<br/>    interval     = optional(number)<br/>    retries      = optional(number)<br/>    start_period = optional(number)<br/>    timeout      = optional(number)<br/>  })</pre> | <pre>{<br/>  "command": [<br/>    "CMD-SHELL",<br/>    "/probe.sh"<br/>  ],<br/>  "interval": 15,<br/>  "retries": 3,<br/>  "start_period": 60,<br/>  "timeout": 5<br/>}</pre> | no |
| <a name="input_dd_image_version"></a> [dd\_image\_version](#input\_dd\_image\_version) | Datadog Agent image version | `string` | `"latest"` | no |
| <a name="input_dd_log_collection"></a> [dd\_log\_collection](#input\_dd\_log\_collection) | Configuration for Datadog Log Collection via the agent | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    container_collect_all = optional(bool, true)<br/>    container_include     = optional(list(string), [])<br/>    container_exclude     = optional(list(string), [])<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_log_level"></a> [dd\_log\_level](#input\_dd\_log\_level) | Set logging verbosity for Datadog agent. Valid values: trace, debug, info, warn, error, critical, off | `string` | `"info"` | no |
| <a name="input_dd_memory_limit_mib"></a> [dd\_memory\_limit\_mib](#input\_dd\_memory\_limit\_mib) | Datadog Agent container memory limit in MiB | `number` | `512` | no |
| <a name="input_dd_orchestrator_explorer"></a> [dd\_orchestrator\_explorer](#input\_dd\_orchestrator\_explorer) | Configuration for Datadog Orchestrator Explorer | <pre>object({<br/>    enabled = optional(bool, true)<br/>    url     = optional(string)<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_dd_proc_path"></a> [dd\_proc\_path](#input\_dd\_proc\_path) | Path to /proc directory on the host. Defaults to /proc/ | `string` | `"/proc/"` | no |
| <a name="input_dd_registry"></a> [dd\_registry](#input\_dd\_registry) | Datadog Agent image registry | `string` | `"public.ecr.aws/datadog/agent"` | no |
| <a name="input_dd_site"></a> [dd\_site](#input\_dd\_site) | Datadog Site | `string` | `"datadoghq.com"` | no |
| <a name="input_dd_tags"></a> [dd\_tags](#input\_dd\_tags) | Datadog Agent global tags (eg. `key1:value1, key2:value2`) | `string` | `null` | no |
| <a name="input_enable_ecs_managed_tags"></a> [enable\_ecs\_managed\_tags](#input\_enable\_ecs\_managed\_tags) | Enable ECS managed tags for the daemon service | `bool` | `true` | no |
| <a name="input_execution_role"></a> [execution\_role](#input\_execution\_role) | ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch container and cluster metadata. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_family"></a> [family](#input\_family) | A unique name for your task definition | `string` | n/a | yes |
| <a name="input_ipc_mode"></a> [ipc\_mode](#input\_ipc\_mode) | IPC resource namespace to be used for the containers in the task The valid values are `host`, `task`, and `none` | `string` | `null` | no |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode) | Docker networking mode to use for the containers in the task. Valid values are `bridge` and `host` | `string` | `"bridge"` | no |
| <a name="input_pid_mode"></a> [pid\_mode](#input\_pid\_mode) | Process namespace to use for the containers in the task. The valid values are `host` and `task` | `string` | `null` | no |
| <a name="input_placement_constraints"></a> [placement\_constraints](#input\_placement\_constraints) | Configuration list for rules that are taken into consideration during task placement (up to max of 10) | <pre>list(object({<br/>    type       = string<br/>    expression = string<br/>  }))</pre> | `[]` | no |
| <a name="input_propagate_tags"></a> [propagate\_tags](#input\_propagate\_tags) | Propagate tags from task definition or service to tasks. Valid values: TASK\_DEFINITION, SERVICE, NONE | `string` | `"SERVICE"` | no |
| <a name="input_proxy_configuration"></a> [proxy\_configuration](#input\_proxy\_configuration) | Configuration for the App Mesh proxy | <pre>object({<br/>    container_name = string<br/>    properties     = map(any)<br/>    type           = optional(string, "APPMESH")<br/>  })</pre> | `null` | no |
| <a name="input_runtime_platform"></a> [runtime\_platform](#input\_runtime\_platform) | Configuration for the runtime platform of the ECS task. Used to determine OS-specific agent configuration. Currently only Linux is fully supported; Windows support is planned (EXP-242). | <pre>object({<br/>    operating_system_family = optional(string, "LINUX")<br/>    cpu_architecture        = optional(string, "X86_64")<br/>  })</pre> | `null` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Name of the ECS daemon service. Defaults to '<family>-datadog-agent' | `string` | `null` | no |
| <a name="input_service_placement_constraints"></a> [service\_placement\_constraints](#input\_service\_placement\_constraints) | Placement constraints for the daemon service (e.g., instance type, availability zone) | <pre>list(object({<br/>    type       = string<br/>    expression = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_service_registries"></a> [service\_registries](#input\_service\_registries) | Service discovery registries for the daemon service | <pre>object({<br/>    registry_arn   = string<br/>    container_name = optional(string)<br/>    container_port = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_skip_destroy"></a> [skip\_destroy](#input\_skip\_destroy) | Whether to retain the old revision when the resource is destroyed or replacement is necessary | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of additional tags to add to the task definition/service created | `map(string)` | `null` | no |
| <a name="input_task_role"></a> [task\_role](#input\_task\_role) | The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch a provided Datadog API key secret. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_track_latest"></a> [track\_latest](#input\_track\_latest) | Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state | `bool` | `false` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | A list of volume definitions that containers in your task may use | <pre>list(object({<br/>    name      = string<br/>    host_path = optional(string)<br/><br/>    docker_volume_configuration = optional(object({<br/>      autoprovision = optional(bool)<br/>      driver        = optional(string)<br/>      driver_opts   = optional(map(any))<br/>      labels        = optional(map(any))<br/>      scope         = optional(string)<br/>    }))<br/><br/>    efs_volume_configuration = optional(object({<br/>      file_system_id          = string<br/>      root_directory          = optional(string)<br/>      transit_encryption      = optional(string)<br/>      transit_encryption_port = optional(number)<br/>      authorization_config = optional(object({<br/>        access_point_id = optional(string)<br/>        iam             = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apm_env_vars"></a> [apm\_env\_vars](#output\_apm\_env\_vars) | Environment variables for APM in user application containers. When UDS is enabled, uses the socket path. When disabled, returns an empty list (users must set DD\_AGENT\_HOST dynamically via the EC2 metadata endpoint). |
| <a name="output_app_dd_sockets_mount"></a> [app\_dd\_sockets\_mount](#output\_app\_dd\_sockets\_mount) | Mount point for the shared UDS socket volume. Add this to your application container's mountPoints to enable communication with the Datadog Agent over Unix Domain Sockets. |
| <a name="output_app_dd_sockets_volume"></a> [app\_dd\_sockets\_volume](#output\_app\_dd\_sockets\_volume) | Volume definition for the shared UDS socket volume. Add this to your application task definition's volumes to enable UDS communication with the Datadog Agent. |
| <a name="output_arn"></a> [arn](#output\_arn) | Full ARN of the Task Definition (including both family and revision). |
| <a name="output_arn_without_revision"></a> [arn\_without\_revision](#output\_arn\_without\_revision) | ARN of the Task Definition with the trailing revision removed. |
| <a name="output_container_definitions"></a> [container\_definitions](#output\_container\_definitions) | A list of valid container definitions provided as a single valid JSON document. |
| <a name="output_data_streams_env_vars"></a> [data\_streams\_env\_vars](#output\_data\_streams\_env\_vars) | Environment variables for Data Streams Monitoring in user application containers. Only includes values when enabled. |
| <a name="output_dogstatsd_env_vars"></a> [dogstatsd\_env\_vars](#output\_dogstatsd\_env\_vars) | Environment variables for DogStatsD in user application containers. When UDS is enabled, uses the socket path. When disabled, returns an empty list (users must set DD\_AGENT\_HOST dynamically via the EC2 metadata endpoint). |
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | ARN of the task execution role. |
| <a name="output_family"></a> [family](#output\_family) | A unique name for your task definition. |
| <a name="output_ipc_mode"></a> [ipc\_mode](#output\_ipc\_mode) | IPC resource namespace to be used for the containers. |
| <a name="output_network_mode"></a> [network\_mode](#output\_network\_mode) | Docker networking mode to use for the containers. |
| <a name="output_pid_mode"></a> [pid\_mode](#output\_pid\_mode) | Process namespace to use for the containers. |
| <a name="output_placement_constraints"></a> [placement\_constraints](#output\_placement\_constraints) | Rules that are taken into consideration during task placement. |
| <a name="output_profiling_env_vars"></a> [profiling\_env\_vars](#output\_profiling\_env\_vars) | Environment variables for profiling configuration in user application containers. Only includes values when enabled. |
| <a name="output_proxy_configuration"></a> [proxy\_configuration](#output\_proxy\_configuration) | Configuration block for the App Mesh proxy. |
| <a name="output_requires_compatibilities"></a> [requires\_compatibilities](#output\_requires\_compatibilities) | Set of launch types required by the task. |
| <a name="output_revision"></a> [revision](#output\_revision) | Revision of the task in a particular family. |
| <a name="output_service_cluster"></a> [service\_cluster](#output\_service\_cluster) | ARN of cluster which the service runs on. Only available if create\_service = true. |
| <a name="output_service_desired_count"></a> [service\_desired\_count](#output\_service\_desired\_count) | Number of instances of the task definition. Only available if create\_service = true. |
| <a name="output_service_id"></a> [service\_id](#output\_service\_id) | ARN that identifies the service. Only available if create\_service = true. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the service. Only available if create\_service = true. |
| <a name="output_skip_destroy"></a> [skip\_destroy](#output\_skip\_destroy) | Whether to retain the old revision when the resource is destroyed or replacement is necessary. |
| <a name="output_tags"></a> [tags](#output\_tags) | Key-value map of resource tags. |
| <a name="output_tags_all"></a> [tags\_all](#output\_tags\_all) | Map of tags assigned to the resource, including inherited tags. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services. |
| <a name="output_trace_inferred_proxy_env_vars"></a> [trace\_inferred\_proxy\_env\_vars](#output\_trace\_inferred\_proxy\_env\_vars) | Environment variables for trace inferred proxy services in user application containers. Only includes values when enabled. |
| <a name="output_track_latest"></a> [track\_latest](#output\_track\_latest) | Whether should track latest ACTIVE task definition on AWS or the one created with the resource stored in state. |
| <a name="output_volume"></a> [volume](#output\_volume) | Configuration block for volumes that containers in your task may use. |
<!-- END_TF_DOCS -->
