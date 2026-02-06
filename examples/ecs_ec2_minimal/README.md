# ECS on EC2 Minimal Example

This example demonstrates the simplest possible deployment of the Datadog Agent daemon for ECS on EC2. It creates only the task definition, allowing you to create the daemon service separately if desired.

## What This Example Includes

- Datadog Agent task definition
- Default configuration (core monitoring only)
- Optional service creation (disabled by default)

## Usage

### Option 1: Task Definition Only

1. **Set Variables**
   ```bash
   export TF_VAR_dd_api_key="your-datadog-api-key"
   export TF_VAR_dd_site="datadoghq.com"
   ```

2. **Apply**
   ```bash
   terraform init
   terraform apply
   ```

3. **Create Service Manually**
   ```bash
   aws ecs create-service \
     --cluster my-cluster \
     --service-name datadog-agent \
     --task-definition datadog-agent-daemon \
     --scheduling-strategy DAEMON
   ```

### Option 2: With Service Creation

1. **Create terraform.tfvars**
   ```hcl
   dd_api_key     = "your-datadog-api-key"
   dd_site        = "datadoghq.com"
   cluster_arn    = "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"
   create_service = true
   ```

2. **Apply**
   ```bash
   terraform init
   terraform apply
   ```

## What Gets Created

- **Task Definition Only Mode**: Just the Datadog Agent task definition
- **With Service Mode**: Task definition + ECS daemon service

## Next Steps

After deploying the agent:

1. Configure your application tasks to send metrics to the agent:
   ```hcl
   environment = [
     {
       name  = "DD_AGENT_HOST"
       value = "169.254.170.2"
     },
     {
       name  = "DD_DOGSTATSD_PORT"
       value = "8125"
     }
   ]
   ```

2. For more advanced configuration, see the [full example](../ecs_ec2/)

## Clean Up

```bash
terraform destroy
```
