# ECS on EC2 Full Example

This example demonstrates a complete deployment of the Datadog Agent as a daemon service on ECS EC2, along with a sample application that sends metrics and traces to the agent.

## What This Example Includes

1. **Datadog Agent Daemon Service**
   - All features enabled (DogStatsD, APM, Log Collection, Orchestrator Explorer)
   - Unified Service Tagging configured
   - API key stored in AWS Secrets Manager

2. **Sample Application (nginx)**
   - Configured to send metrics via DogStatsD
   - Configured to send traces via APM
   - Uses module helper outputs for easy configuration
   - Runs with 2 instances by default

3. **IAM Roles**
   - Task execution role for pulling images
   - Task role for application permissions

4. **CloudWatch Logs**
   - Application logs sent to CloudWatch
   - Agent also collects container logs

## Prerequisites

Before running this example, you need:

1. **ECS Cluster on EC2**
   - An existing ECS cluster with EC2 container instances
   - Container instances must have Docker running
   - Instances must have the `AmazonEC2ContainerServiceforEC2Role` policy attached

2. **Datadog API Key in Secrets Manager**
   ```bash
   aws secretsmanager create-secret \
     --name datadog-api-key \
     --secret-string "your-datadog-api-key" \
     --region us-east-1
   ```

3. **AWS Credentials**
   - Configured AWS CLI or environment variables

## Usage

1. **Set Required Variables**

   Create a `terraform.tfvars` file:
   ```hcl
   cluster_name           = "my-ecs-cluster"
   cluster_arn            = "arn:aws:ecs:us-east-1:123456789012:cluster/my-ecs-cluster"
   dd_api_key_secret_arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:datadog-api-key-AbCdEf"
   dd_site                = "datadoghq.com"
   environment            = "dev"
   region                 = "us-east-1"
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Review the Plan**
   ```bash
   terraform plan
   ```

4. **Apply**
   ```bash
   terraform apply
   ```

5. **Verify Deployment**
   - Check ECS console for running Datadog Agent daemon service
   - Check ECS console for running application tasks
   - Verify metrics and traces in Datadog UI

## What Gets Created

- Datadog Agent ECS task definition
- Datadog Agent ECS daemon service (one agent per EC2 instance)
- Application ECS task definition
- Application ECS service (2 instances)
- IAM roles and policies for both agent and application
- CloudWatch log group for application logs

## Architecture

```
┌─────────────────────────────────────────────────┐
│ EC2 Instance #1                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ Datadog Agent Container (Daemon)         │  │
│  │ - Listens on 0.0.0.0:8125 (DogStatsD)   │  │
│  │ - Listens on 0.0.0.0:8126 (APM)         │  │
│  │ - Accesses /var/run/docker.sock         │  │
│  └──────────────────────────────────────────┘  │
│                     ▲                           │
│                     │ Send metrics/traces       │
│  ┌──────────────────┴───────────────────────┐  │
│  │ App Container #1                         │  │
│  │ DD_AGENT_HOST=169.254.170.2             │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ EC2 Instance #2                                 │
│  ┌──────────────────────────────────────────┐  │
│  │ Datadog Agent Container (Daemon)         │  │
│  └──────────────────────────────────────────┘  │
│                     ▲                           │
│                     │                           │
│  ┌──────────────────┴───────────────────────┐  │
│  │ App Container #2                         │  │
│  │ DD_AGENT_HOST=169.254.170.2             │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Outputs

After deployment, you'll see:

- `datadog_agent_task_definition_arn`: ARN of the agent task definition
- `datadog_agent_service_name`: Name of the daemon service
- `app_task_definition_arn`: ARN of the application task definition
- `app_service_name`: Name of the application service
- `dd_agent_env_vars_example`: Example environment variables for integration

## Customization

### Change Application Count

```hcl
app_desired_count = 4
```

### Disable Certain Features

```hcl
module "datadog_agent" {
  # ...

  dd_log_collection = {
    enabled = false
  }

  dd_apm = {
    enabled = false
  }
}
```

### Use Different Network Mode

```hcl
module "datadog_agent" {
  # ...
  network_mode = "host"
}

# Also update application task
resource "aws_ecs_task_definition" "app" {
  # ...
  network_mode = "host"

  container_definitions = jsonencode([{
    # ...
    environment = [
      {
        name  = "DD_AGENT_HOST"
        value = "127.0.0.1"  # localhost for host mode
      },
      # ... rest of environment
    ]
  }])
}
```

## Clean Up

```bash
terraform destroy
```

## Troubleshooting

### Agent Not Running
- Check ECS console for service events
- Verify IAM roles have correct permissions
- Check that Secrets Manager secret is accessible

### Application Not Sending Metrics
- Verify `DD_AGENT_HOST` environment variable is set correctly
- Check security groups allow traffic on ports 8125 and 8126
- Review application container logs

### Logs Not Collected
- Ensure agent has access to `/var/run/docker.sock`
- Verify `DD_LOGS_ENABLED=true` in agent environment
- Check agent logs for errors

## Next Steps

- Add more application containers with Datadog integration
- Configure custom metrics and traces in your applications
- Set up Datadog monitors and alerts
- Explore advanced agent configuration options
