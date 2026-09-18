# ECS Managed Instances Full Example

This example demonstrates a complete deployment of the Datadog Agent as an ECS Managed Daemon on an ECS Managed Instances cluster, along with a sample application that sends metrics and traces to the agent over Unix Domain Sockets (UDS).

## What This Example Includes

1. **ECS cluster and Managed Instances capacity provider**
   - `aws_ecs_cluster`
   - `aws_ecs_capacity_provider` with a `managed_instances_provider` block
   - The ECS infrastructure role (`AmazonECSInfrastructureRolePolicyForManagedInstances`) and the EC2 instance profile role (`AmazonECSInstanceRolePolicyForManagedInstances`) that Managed Instances requires - **note the instance role's name is a hardcoded literal starting with `ecsInstanceRole`, see the comment in `main.tf`**

2. **Datadog Agent Managed Daemon** (`modules/ecs_managed_instances`)
   - DogStatsD and APM enabled over UDS
   - Orchestrator Explorer and Live Process Collection enabled
   - API key passed directly (see Prerequisites for a Secrets Manager alternative)

3. **Sample Application** (`ghcr.io/datadog/apps-dogstatsd:main`)
   - Connects to the daemon over the shared `dd-sockets` UDS volume using the module's `dogstatsd_env_vars`/`apm_env_vars`/`app_dd_sockets_volume`/`app_dd_sockets_mount` outputs
   - Demonstrates the app-side wiring this module does not manage for you

## Prerequisites

1. **A VPC, subnets, and security group** in a region where ECS Managed Instances is available.
2. **A Datadog API key.**

## Usage

```hcl
# terraform.tfvars
region              = "us-east-1"
vpc_id              = "vpc-0123456789abcdef0"
subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
security_group_ids  = ["sg-0123456789abcdef0"]
datadog_api_key     = "your-datadog-api-key"
dd_site             = "datadoghq.com"
environment         = "dev"
```

```bash
terraform init
terraform plan
terraform apply
```

## Important Operational Notes

- **Any change to the Datadog Agent's configuration recycles the fleet.** `aws_ecs_daemon_task_definition` forces full replacement on nearly every field, and AWS's daemon deployment model drains and replaces every EC2 instance in the attached capacity providers when the daemon is pointed at a new task definition revision. This is heavier than a rolling ECS service update - budget for it, and tune `deployment_configuration` (`drain_percent`, `bake_time_in_minutes`) accordingly.
- **`aws_ecs_daemon` defaults `critical = true`** and the Terraform provider does not expose a way to override it: if the Datadog Agent container becomes unhealthy, AWS drains and replaces the underlying EC2 instance. The module's default health check uses Datadog's own documented command to minimize this risk, but a persistent problem (e.g. a bad API key) can still cause instance churn.
- **Container log collection through the agent is not supported** in daemon mode on ECS Managed Instances. Use FireLens or the `awslogs` driver directly on your application task definitions instead (see `aws_ecs_task_definition.dogstatsd_app` for the `awslogs` pattern).
- IMDS reachability from inside the daemon's network namespace is not confirmed by AWS documentation - avoid depending on it without testing in your own account first.

## Clean Up

```bash
terraform destroy
```
