# ECS Managed Instances Module for Datadog Agent

This Terraform module deploys the Datadog Agent as an **ECS Managed Daemon** on Amazon ECS Managed Instances clusters. A managed daemon runs one Datadog Agent per instance in an ECS Managed Instances capacity provider, giving full visibility into every container on that instance without touching your application task definitions.

This module uses the `aws_ecs_daemon_task_definition` and `aws_ecs_daemon` resources (added to the `hashicorp/aws` provider in v6.50.0), not `aws_ecs_task_definition`/`aws_ecs_service`. These are new AWS resources with a materially different schema and operational model from the ones used by the `ecs_ec2` and `ecs_fargate` submodules.

## Deployment Behavior

### Any configuration change replaces your entire fleet

Any change to `container_definition` (which covers every `dd_*` variable, since they all end up as environment variables or settings on the Agent's single container), `family`, `cpu`, `memory`, `task_role_arn`, or `execution_role_arn` forces a full resource replacement on `aws_ecs_daemon_task_definition`; there is no in-place update or revision-bump semantics like `aws_ecs_task_definition` has. When the daemon is pointed at a new task definition revision, AWS's daemon deployment model **drains and replaces every EC2 instance** in the attached capacity provider(s), relocating your application tasks in the process. This is a fleet-wide rolling replacement, not a lightweight "restart the agent container" the way `ecs_ec2`'s daemon *service* behaves. The one exception is the `tags` variable: AWS resource tags update in place via a separate API call and do not trigger a replacement.

Use the `deployment_configuration` variable (`drain_percent`, `bake_time_in_minutes`, `alarms`) to control the blast radius and pace of this rollout. Do not leave it at defaults without understanding what they do - see below.

### `critical = true` and no way to opt out

`aws_ecs_daemon` defaults `critical = true` at the AWS API level: if the daemon task stops, fails, or becomes unhealthy, AWS drains and replaces the underlying EC2 instance. **The Terraform `aws_ecs_daemon` resource does not expose any attribute to set `critical = false`.** This module's `dd_health_check` default uses Datadog's own documented health check command (`["CMD-SHELL", "agent health"]`) specifically to minimize the chance of a false-positive failure triggering this, but there is currently no way to fully opt out of the behavior via Terraform.

### `terraform apply` can return before the rollout finishes

The provider only polls the daemon's coarse `ACTIVE` / `DELETE_IN_PROGRESS` status, not the actual per-instance rollout progress. `terraform apply` can exit successfully while the fleet-wide instance replacement is still running in the background. Separately, `daemon_task_definition_arn` has drift detection intentionally disabled by the provider - the API can report a stale revision mid-deployment, and AWS's circuit breaker can automatically roll back to a previous task definition revision without Terraform ever seeing it happen. After an automatic rollback, Terraform state can claim a newer revision is live while AWS is actually still running the old one.

**Recommendation:** after any `apply` that touches the daemon or its task definition, check the ECS console or `DescribeDaemon`/`DescribeDaemonTaskDefinition` for actual rollout status - don't rely solely on `terraform apply` exiting `0`.

## What this module does NOT manage

This module creates only the daemon task definition, the daemon, and (optionally) its task/execution IAM roles. It does **not** create:

- The ECS Managed Instances capacity provider
- The capacity provider's **infrastructure role**
- The EC2 **instance profile** used by Managed Instances

There are four distinct IAM identities in the full picture:

| Role | Trust | Managed policy | Managed by this module? |
|---|---|---|---|
| Capacity provider infrastructure role | `ecs.amazonaws.com` | `arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances` (no `service-role/` path segment) | No |
| EC2 instance profile role | `ec2.amazonaws.com` | `arn:aws:iam::aws:policy/AmazonECSInstanceRolePolicyForManagedInstances` | No |
| Task role (`task_role`) | `ecs-tasks.amazonaws.com` | Module-managed ECS/EC2 metadata permissions | Yes |
| Execution role (`execution_role`) | `ecs-tasks.amazonaws.com` | `AmazonECSTaskExecutionRolePolicy` + secret access | Yes |

**Important:** the `AmazonECSInstanceRolePolicyForManagedInstances` managed policy scopes `iam:PassRole` to role names matching `ecsInstanceRole*`. If your instance profile's IAM role name doesn't start with `ecsInstanceRole`, task launches fail at runtime with a `ResourceInitializationError` - this will not be caught at `terraform plan`/`apply` time. See [examples/ecs_managed_instances](../../examples/ecs_managed_instances) for a worked example of the capacity provider, infrastructure role, and correctly-named instance profile.

## Quick Start

```hcl
module "datadog_agent" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_managed_instances"

  dd_api_key_secret = {
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:datadog-api-key"
  }
  dd_site = "datadoghq.com"

  family = "datadog-agent-daemon"

  cluster_arn             = "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"
  capacity_provider_arns  = ["arn:aws:ecs:us-east-1:123456789012:capacity-provider/my-managed-instances-cp"]
}
```

### Minimum Datadog Agent version

ECS Managed Instances daemon mode requires **Datadog Agent 7.77.0 or later**. The module's `dd_image_version` defaults to `latest`; pin an explicit version if you need reproducibility.

## Configuration

### API Keys

Supply the Datadog API key either directly via `dd_api_key`, or via `dd_api_key_secret` referencing an AWS Secrets Manager secret ARN. The module grants the execution role permission to retrieve the secret and injects it as `DD_API_KEY`.

### Datadog Site

Defaults to `datadoghq.com`. Set `dd_site` to use a different [Datadog site](https://docs.datadoghq.com/getting_started/site/).

## Communication Model: UDS Default, TCP Fallback

### Unix Domain Sockets (default, recommended)

Datadog documents **only UDS** for daemon mode on ECS Managed Instances. The daemon mounts a host-path volume (`dd-sockets` at `/var/run/datadog`) exposing `apm.socket` and `dsd.socket`. Application containers mount the same host path read-only and set:

```
DD_TRACE_AGENT_URL=unix:///var/run/datadog/apm.socket
DD_DOGSTATSD_URL=unix:///var/run/datadog/dsd.socket
```

Use the module's `app_dd_sockets_volume`, `app_dd_sockets_mount`, `apm_env_vars`, and `dogstatsd_env_vars` outputs to wire this up without hardcoding paths - see [App-Side Wiring](#app-side-wiring) below.

### TCP fallback

Set `dd_dogstatsd.tcp_enabled` / `dd_apm.tcp_enabled` to `true` to communicate over the network instead of UDS. Daemons on an ECS Managed Instance share a single network namespace (the "daemon bridge"), reachable via a static IP: `169.254.172.2` (IPv4) or `fd00:ec2::172:2` (IPv6). Point your application at the daemon with:

```
DD_AGENT_HOST=169.254.172.2
```

Use a real DogStatsD/APM client library, not a hand-rolled socket sender. Origin detection (container tagging) over this path works by the client library embedding the container ID/inode directly in the packet - a raw socket send omits this field and produces untagged data.

Be aware that daemons sharing an instance's network namespace cannot bind the same port. If another vendor's daemon on the same capacity provider also uses port 8125 (DogStatsD) or 8126 (APM), you may hit a port collision that Terraform cannot detect or warn about.

## App-Side Wiring

This module manages only the Datadog Agent daemon - it does not touch your application's task definitions. You must wire up your own application task definition to talk to the daemon:

```hcl
resource "aws_ecs_task_definition" "app" {
  family = "my-app"

  volume {
    name      = module.datadog_agent.app_dd_sockets_volume.name
    host_path = module.datadog_agent.app_dd_sockets_volume.host_path
  }

  container_definitions = jsonencode([{
    name  = "app"
    image = "my-app:latest"

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

    mountPoints = [module.datadog_agent.app_dd_sockets_mount]
  }])
}
```

### Available Helper Outputs

- **`dogstatsd_env_vars`**: Environment variables for DogStatsD (sets `DD_DOGSTATSD_URL` to the UDS socket path when enabled)
- **`apm_env_vars`**: Environment variables for APM (sets `DD_TRACE_AGENT_URL` to the UDS socket path when enabled)
- **`app_dd_sockets_volume`**: Volume definition for the shared UDS socket directory - add to your task definition's `volume` blocks
- **`app_dd_sockets_mount`**: Mount point for the shared UDS socket directory - add to your application container's `mountPoints`
- **`data_streams_env_vars`**: Environment variables for Data Streams Monitoring (when enabled)

## Log Collection

**Container log collection through the Datadog Agent is not supported in daemon mode on ECS Managed Instances.** This module enforces that with a `precondition` that fails the plan if `dd_log_collection.enabled = true`.

Instead, configure log delivery directly on your **application's own task definition** - the daemon cannot see or collect logs from your application containers in this mode. For example, using the `awslogs` driver:

```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/my-app",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "my-app"
    }
  }
}
```

Or configure the FireLens log driver on your application task if you need to forward logs to Datadog Log Management directly.

### Debugging the daemon itself

Since a failing or unhealthy daemon causes AWS to drain and replace the instance (see the `critical` warning above), being able to see the agent's own logs before that happens is important. Use `dd_agent_log_configuration` to route the **Datadog Agent container's own logs** (not application logs) to a destination like CloudWatch:

```hcl
dd_agent_log_configuration = {
  log_driver = "awslogs"
  options = {
    "awslogs-group"         = "/ecs/datadog-agent-daemon"
    "awslogs-region"        = "us-east-1"
    "awslogs-stream-prefix" = "datadog-agent"
  }
}
```

## Cloud Network Monitoring

Linux only. Enable via:

```hcl
dd_network_monitoring = {
  enabled = true
}
```

This adds `DD_SYSTEM_PROBE_NETWORK_ENABLED=true`, the Linux capabilities Datadog documents for the system-probe (`SYS_ADMIN`, `SYS_RESOURCE`, `SYS_PTRACE`, `NET_ADMIN`, `NET_BROADCAST`, `NET_RAW`, `IPC_LOCK`, `CHOWN`), and a host-mounted `/sys/kernel/debug` volume.

## Process Collection

```hcl
dd_process_collection = {
  enabled = true
}
```

This module sets `DD_PROCESS_CONFIG_PROCESS_COLLECTION_ENABLED` when enabled.

## Deployment Configuration

Controls how the daemon rolls out changes across instances:

```hcl
deployment_configuration = {
  drain_percent        = 25  # % of instances drained/replaced at a time
  bake_time_in_minutes = 10  # wait time between deployment steps
  alarms = {
    alarm_names = ["my-cloudwatch-alarm"]
    enable      = true        # gate rollout progression on alarm state
  }
}
```

This block is write-only on the AWS side - the API does not return these values, so `terraform plan` will always show a diff here. This is expected provider behavior, not a bug.

## Feature Support

| Feature | Status |
|---|---|
| Core infrastructure monitoring | Supported (via containerd socket, `/proc`, `/sys/fs/cgroup` host mounts) |
| DogStatsD / APM over UDS | Supported (default, Datadog-documented) |
| DogStatsD / APM over TCP | Supported - requires a real client library for tagging |
| Process Collection | Supported |
| Cloud Network Monitoring | Supported, Linux only |
| Log Collection (agent-collected app logs) | **Not supported** - blocked via precondition; use FireLens/`awslogs` on the app task instead |
| Agent's own log routing | Supported via `dd_agent_log_configuration` |
| Windows | **Not supported** - `aws_ecs_daemon_task_definition` has no `runtime_platform` field at all; this isn't a "planned" gap, there's genuinely nothing to configure |
| Cloud Workload Security (CWS) | **Deferred** - not implemented pending Datadog documentation for daemon mode. AWS's platform does support privileged mode, Linux capabilities, and host mounts on daemons, so this is technically plausible in the future |
| `dd_docker_labels` | **Not available** - `aws_ecs_daemon_task_definition`'s container definition has no `dockerLabels` field. Note: Docker-label-based Autodiscovery annotations belong on the *application* container per Datadog's docs anyway, which this module doesn't manage, so this gap is largely moot |
| `pid_mode` / `ipc_mode` | **Not exposed** - the underlying AWS API supports these, but the Terraform provider's schema for `aws_ecs_daemon_task_definition` omits them entirely. This is a provider gap, not an AWS limitation |
| `skip_destroy` / `track_latest` | **Not applicable** - every field on this resource forces full replacement; there is no revision-bump semantics like `aws_ecs_task_definition` has |

## IAM Roles (Module-Managed)

### Task Execution Role

Used by ECS to pull container images and access secrets. Auto-created if not provided, including `AmazonECSTaskExecutionRolePolicy` and Secrets Manager access (if using `dd_api_key_secret`).

### Task Role

Used by the Datadog Agent to query ECS and EC2 metadata (for host and container tagging). Auto-created if not provided, with the same permission set as the `ecs_ec2` module (`ecs:ListClusters`, `ecs:ListContainerInstances`, `ecs:DescribeContainerInstances`, `ecs:DescribeTasks`, `ecs:ListTasks`, `ec2:DescribeInstances`, `ec2:DescribeTags`).

## Complete Example

See [examples/ecs_managed_instances](../../examples/ecs_managed_instances) for a complete working example including the capacity provider, infrastructure role, correctly-named instance profile, the daemon, and a sample application task definition wired up over UDS.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.50.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecs_daemon.datadog_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_daemon) | resource |
| [aws_ecs_daemon_task_definition.datadog_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_daemon_task_definition) | resource |
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
| <a name="input_capacity_provider_arns"></a> [capacity\_provider\_arns](#input\_capacity\_provider\_arns) | ARNs of ECS Managed Instances capacity providers the daemon should run on. Required if create\_daemon = true. The module does not create the capacity provider, infrastructure role, or instance profile - those must already exist. | `set(string)` | `[]` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the ECS cluster where the Datadog agent daemon will run. Required if create\_daemon = true. | `string` | `null` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Number of cpu units used by the task, as a string (e.g. "256"). Note this is a string on aws\_ecs\_daemon\_task\_definition, unlike the number type used by aws\_ecs\_task\_definition in the other submodules. | `string` | `null` | no |
| <a name="input_create_daemon"></a> [create\_daemon](#input\_create\_daemon) | Whether to create the aws\_ecs\_daemon resource. If false, only the daemon task definition is created. | `bool` | `true` | no |
| <a name="input_daemon_name"></a> [daemon\_name](#input\_daemon\_name) | Name of the ECS daemon. Defaults to '<family>-datadog-agent' | `string` | `null` | no |
| <a name="input_dd_agent_log_configuration"></a> [dd\_agent\_log\_configuration](#input\_dd\_agent\_log\_configuration) | Log configuration for the Datadog Agent container's OWN logs (not application container logs, which the agent cannot collect in daemon mode on ECS Managed Instances), e.g. routing to CloudWatch via the awslogs driver. Since a failing/unhealthy daemon causes AWS to drain and replace the instance, this is the primary debugging lever available. | <pre>object({<br/>    log_driver = optional(string)<br/>    options    = optional(map(string))<br/>    secret_options = optional(list(object({<br/>      name       = string<br/>      value_from = string<br/>    })))<br/>  })</pre> | `null` | no |
| <a name="input_dd_api_key"></a> [dd\_api\_key](#input\_dd\_api\_key) | Datadog API Key | `string` | `null` | no |
| <a name="input_dd_api_key_secret"></a> [dd\_api\_key\_secret](#input\_dd\_api\_key\_secret) | Datadog API Key Secret ARN | <pre>object({<br/>    arn = string<br/>  })</pre> | `null` | no |
| <a name="input_dd_apm"></a> [dd\_apm](#input\_dd\_apm) | Configuration for Datadog APM. UDS (socket\_enabled) is the default and is Datadog-documented for daemon mode on ECS Managed Instances. TCP (tcp\_enabled) is also supported: daemons on an instance share a static bridge IP (169.254.172.2) reachable over the network. Origin detection over TCP requires a real APM client library, since the client embeds the container ID directly in the request - a hand-rolled sender will produce untagged traces. | <pre>object({<br/>    enabled                       = optional(bool, true)<br/>    socket_enabled                = optional(bool, true)<br/>    tcp_enabled                   = optional(bool, false)<br/>    profiling                     = optional(bool, false)<br/>    trace_inferred_proxy_services = optional(bool, false)<br/>    data_streams                  = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "data_streams": false,<br/>  "enabled": true,<br/>  "profiling": false,<br/>  "socket_enabled": true,<br/>  "tcp_enabled": false,<br/>  "trace_inferred_proxy_services": false<br/>}</pre> | no |
| <a name="input_dd_cgroup_path"></a> [dd\_cgroup\_path](#input\_dd\_cgroup\_path) | Path to cgroup directory on the host. Defaults to /sys/fs/cgroup/. | `string` | `"/sys/fs/cgroup/"` | no |
| <a name="input_dd_checks_cardinality"></a> [dd\_checks\_cardinality](#input\_dd\_checks\_cardinality) | Datadog Agent checks cardinality | `string` | `null` | no |
| <a name="input_dd_cpu"></a> [dd\_cpu](#input\_dd\_cpu) | Datadog Agent container CPU units | `number` | `256` | no |
| <a name="input_dd_cri_socket_path"></a> [dd\_cri\_socket\_path](#input\_dd\_cri\_socket\_path) | Path to the containerd socket on the host. ECS Managed Instances uses containerd, not Docker, so this replaces the docker socket path used by the ecs\_ec2 module. Defaults to /var/run/containerd/containerd.sock | `string` | `"/var/run/containerd/containerd.sock"` | no |
| <a name="input_dd_dogstatsd"></a> [dd\_dogstatsd](#input\_dd\_dogstatsd) | Configuration for Datadog DogStatsD. UDS (socket\_enabled) is the default and is Datadog-documented for daemon mode on ECS Managed Instances. TCP (tcp\_enabled) is also supported: daemons on an instance share a static bridge IP (169.254.172.2) reachable over the network. Origin detection over TCP requires a real DogStatsD client library, since the client embeds the container ID/inode directly in the packet - a hand-rolled socket sender will produce untagged metrics. | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    origin_detection_enabled = optional(bool, true)<br/>    dogstatsd_cardinality    = optional(string, "orchestrator")<br/>    socket_enabled           = optional(bool, true)<br/>    tcp_enabled              = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "dogstatsd_cardinality": "orchestrator",<br/>  "enabled": true,<br/>  "origin_detection_enabled": true,<br/>  "socket_enabled": true,<br/>  "tcp_enabled": false<br/>}</pre> | no |
| <a name="input_dd_environment"></a> [dd\_environment](#input\_dd\_environment) | Datadog Agent container environment variables. Highest precedence and overwrites other environment variables defined by the module. For example, `dd_environment = [ { name = 'DD_VAR', value = 'DD_VAL' } ]`. Defaults to `[]` (not `[{}]` as in the ecs\_ec2/ecs\_fargate modules) because the `environment` block on aws\_ecs\_daemon\_task\_definition is a Terraform Set rather than an ordered list: an empty map would produce an entry with null name/value that passes through into the Set, and precedence must instead be implemented via explicit dedupe-by-name. | `list(map(string))` | `[]` | no |
| <a name="input_dd_essential"></a> [dd\_essential](#input\_dd\_essential) | Whether the Datadog Agent container is essential | `bool` | `true` | no |
| <a name="input_dd_health_check"></a> [dd\_health\_check](#input\_dd\_health\_check) | Datadog Agent health check configuration. Defaults to Datadog's documented health check command for ECS Managed Instances daemon mode (not the same default used by the ecs\_ec2/ecs\_fargate modules). aws\_ecs\_daemon defaults `critical = true` and the Terraform aws\_ecs\_daemon resource does not expose a way to set `critical = false`, so an unhealthy/flapping health check causes AWS to drain and replace the underlying EC2 instance. Using Datadog's own documented command minimizes that risk. | <pre>object({<br/>    command      = optional(list(string))<br/>    interval     = optional(number)<br/>    retries      = optional(number)<br/>    start_period = optional(number)<br/>    timeout      = optional(number)<br/>  })</pre> | <pre>{<br/>  "command": [<br/>    "CMD-SHELL",<br/>    "agent health"<br/>  ],<br/>  "interval": 30,<br/>  "retries": 3,<br/>  "start_period": 15,<br/>  "timeout": 5<br/>}</pre> | no |
| <a name="input_dd_image_version"></a> [dd\_image\_version](#input\_dd\_image\_version) | Datadog Agent image version. ECS Managed Instances daemon mode requires Datadog Agent >= 7.77.0. | `string` | `"latest"` | no |
| <a name="input_dd_log_collection"></a> [dd\_log\_collection](#input\_dd\_log\_collection) | Configuration for Datadog Log Collection. Datadog does NOT support container log collection through the agent in daemon mode on ECS Managed Instances. This variable exists only so the module can fail fast with a clear error if a user tries to enable it (enforced via a precondition on the daemon task definition). Use FireLens or the awslogs log driver configured on the application's own task definition instead. | <pre>object({<br/>    enabled = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_log_level"></a> [dd\_log\_level](#input\_dd\_log\_level) | Set logging verbosity for Datadog agent. Valid values: trace, debug, info, warn, error, critical, off | `string` | `"info"` | no |
| <a name="input_dd_memory_limit_mib"></a> [dd\_memory\_limit\_mib](#input\_dd\_memory\_limit\_mib) | Datadog Agent container memory limit in MiB | `number` | `512` | no |
| <a name="input_dd_network_monitoring"></a> [dd\_network\_monitoring](#input\_dd\_network\_monitoring) | Configuration for Datadog Cloud Network Monitoring. Linux only. When enabled, adds DD\_SYSTEM\_PROBE\_NETWORK\_ENABLED, the linux capabilities required by the system-probe, and a host-mounted /sys/kernel/debug volume. | <pre>object({<br/>    enabled = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_orchestrator_explorer"></a> [dd\_orchestrator\_explorer](#input\_dd\_orchestrator\_explorer) | Configuration for Datadog Orchestrator Explorer | <pre>object({<br/>    enabled = optional(bool, true)<br/>    url     = optional(string)<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_dd_proc_path"></a> [dd\_proc\_path](#input\_dd\_proc\_path) | Path to /proc directory on the host. Defaults to /proc/ | `string` | `"/proc/"` | no |
| <a name="input_dd_process_collection"></a> [dd\_process\_collection](#input\_dd\_process\_collection) | Configuration for Datadog Live Process collection. When enabled, sets DD\_PROCESS\_CONFIG\_PROCESS\_COLLECTION\_ENABLED. | <pre>object({<br/>    enabled = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_dd_registry"></a> [dd\_registry](#input\_dd\_registry) | Datadog Agent image registry | `string` | `"public.ecr.aws/datadog/agent"` | no |
| <a name="input_dd_site"></a> [dd\_site](#input\_dd\_site) | Datadog Site | `string` | `"datadoghq.com"` | no |
| <a name="input_dd_tags"></a> [dd\_tags](#input\_dd\_tags) | Datadog Agent global tags (eg. `key1:value1, key2:value2`) | `string` | `null` | no |
| <a name="input_deployment_configuration"></a> [deployment\_configuration](#input\_deployment\_configuration) | Controls the daemon's rolling deployment behavior across instances. This block is write-only on the AWS side (not readable back from the API), so Terraform plans will always show a diff here - this is expected provider behavior, not a bug. Note: ANY change to the daemon task definition (including something as small as a tag) forces a full replacement and triggers AWS's drain-provision-replace rollout across every instance in the attached capacity providers, so these settings materially affect production availability during that rollout - they are not cosmetic. | <pre>object({<br/>    drain_percent        = optional(number, 25)<br/>    bake_time_in_minutes = optional(number, 0)<br/>    alarms = optional(object({<br/>      alarm_names = optional(list(string), [])<br/>      enable      = optional(bool, false)<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_enable_ecs_managed_tags"></a> [enable\_ecs\_managed\_tags](#input\_enable\_ecs\_managed\_tags) | Enable ECS managed tags for the daemon | `bool` | `true` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Enable ECS Exec for daemon tasks | `bool` | `false` | no |
| <a name="input_execution_role"></a> [execution\_role](#input\_execution\_role) | ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch container and cluster metadata. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_family"></a> [family](#input\_family) | A unique name for your daemon task definition | `string` | n/a | yes |
| <a name="input_memory"></a> [memory](#input\_memory) | Amount (in MiB) of memory used by the task, as a string (e.g. "512"). Note this is a string on aws\_ecs\_daemon\_task\_definition, unlike the number type used by aws\_ecs\_task\_definition in the other submodules. | `string` | `null` | no |
| <a name="input_propagate_tags"></a> [propagate\_tags](#input\_propagate\_tags) | Propagate tags to daemon tasks. Valid values: DAEMON, NONE. Note this differs from the ecs\_ec2 module's TASK\_DEFINITION/SERVICE/NONE options, since aws\_ecs\_daemon only supports DAEMON and NONE. | `string` | `"DAEMON"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of additional tags to add to the daemon task definition/daemon created | `map(string)` | `null` | no |
| <a name="input_task_role"></a> [task\_role](#input\_task\_role) | The ARN of the IAM role that allows your Amazon ECS container task to make calls to other AWS services. Contains:<br/>  - `arn` (string): The ARN of the IAM role.<br/>  - `add_dd_ecs_permissions` (bool): Whether to automatically add Datadog ECS permissions to the role to fetch a provided Datadog API key secret. | <pre>object({<br/>    arn                    = string<br/>    add_dd_ecs_permissions = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | A list of additional host-path volume definitions that containers in your task may use, beyond the ones the module manages. Note: the volume block on aws\_ecs\_daemon\_task\_definition only supports `name` + `host.source_path` - no docker\_volume\_configuration/efs/fsx volume types like the other two submodules, so this type is intentionally simpler. | <pre>list(object({<br/>    name      = string<br/>    host_path = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apm_env_vars"></a> [apm\_env\_vars](#output\_apm\_env\_vars) | Environment variables for APM in user application containers. Provided only when UDS is enabled (dd\_apm.enabled && dd\_apm.socket\_enabled); otherwise an empty list. |
| <a name="output_app_dd_sockets_mount"></a> [app\_dd\_sockets\_mount](#output\_app\_dd\_sockets\_mount) | Mount point for the shared UDS socket directory. Add this to your application container's mountPoints to enable communication with the Datadog Agent daemon over Unix Domain Sockets. |
| <a name="output_app_dd_sockets_volume"></a> [app\_dd\_sockets\_volume](#output\_app\_dd\_sockets\_volume) | Volume definition for the shared UDS socket directory. Add this to your application task definition's volumes to enable UDS communication with the Datadog Agent daemon. |
| <a name="output_arn"></a> [arn](#output\_arn) | Full ARN of the Daemon Task Definition (including both family and revision). |
| <a name="output_container_definition"></a> [container\_definition](#output\_container\_definition) | JSON-encoded representation of the Datadog Agent container definition, provided for testing/inspection convenience since aws\_ecs\_daemon\_task\_definition has no native container\_definitions JSON attribute. |
| <a name="output_daemon_arn"></a> [daemon\_arn](#output\_daemon\_arn) | ARN of the daemon. Only available if create\_daemon = true. |
| <a name="output_daemon_deployment_arn"></a> [daemon\_deployment\_arn](#output\_daemon\_deployment\_arn) | ARN of the daemon's latest deployment. Only available if create\_daemon = true. |
| <a name="output_daemon_status"></a> [daemon\_status](#output\_daemon\_status) | Status of the daemon (ACTIVE or DELETE\_IN\_PROGRESS). Only available if create\_daemon = true. |
| <a name="output_data_streams_env_vars"></a> [data\_streams\_env\_vars](#output\_data\_streams\_env\_vars) | Environment variables for Data Streams Monitoring in user application containers. Only includes values when enabled. |
| <a name="output_dogstatsd_env_vars"></a> [dogstatsd\_env\_vars](#output\_dogstatsd\_env\_vars) | Environment variables for DogStatsD in user application containers. Provided only when UDS is enabled (dd\_dogstatsd.enabled && dd\_dogstatsd.socket\_enabled); otherwise an empty list. |
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | ARN of the task execution role. |
| <a name="output_family"></a> [family](#output\_family) | A unique name for your daemon task definition. |
| <a name="output_revision"></a> [revision](#output\_revision) | Revision of the daemon task definition in a particular family. |
| <a name="output_tags"></a> [tags](#output\_tags) | Key-value map of resource tags. |
| <a name="output_tags_all"></a> [tags\_all](#output\_tags\_all) | Map of tags assigned to the resource, including inherited tags. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services. |
<!-- END_TF_DOCS -->
