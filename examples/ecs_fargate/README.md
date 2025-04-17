# ECS Fargate Example

This example showcases a simple ECS Fargate Task Definition with out of the box Datadog instrumentation.

## Usage

* Create a [Datadog API Key](https://app.datadoghq.com/organization-settings/api-keys)
* Create a `terraform.tfvars` file
  * Set the `dd_api_key` to the Datadog API Key (required)
  * Set the `dd_service` to the name of the service you want to use to filter for the resource in Datadog
  * Set the `dd_site` to the [Datadog destination site](https://docs.datadoghq.com/getting_started/site/) for your metrics, traces, and logs
* Run the following commands:

```bash
terraform init
terraform plan
terraform apply
```

### Example Module

```hcl
module "datadog_ecs_fargate_task" {
  source = "DataDog/ecs-datadog/aws//modules/ecs_fargate"

  # Configure Datadog
  dd_api_key                       = var.dd_api_key
  dd_site                          = var.dd_site
  dd_service                       = var.dd_service
  dd_tags                          = "team:cont-p, owner:container-monitoring"
  dd_essential                     = true
  dd_is_datadog_dependency_enabled = true

  dd_dogstatsd = {
    enabled                  = true
    dogstatsd_cardinality    = "high",
    origin_detection_enabled = true,
  }

  dd_apm = {
    enabled = true,
  }

  dd_log_collection = {
    enabled = true,
  }

  # Configure Task Definition
  family = "datadog-terraform-app"
  container_definitions = jsonencode([
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
      essential = false,
    },
    {
      name      = "datadog-apm-app",
      image     = "ghcr.io/datadog/apps-tracegen:main",
      essential = true,
    },
  ])
  volumes = [
    {
      name = "app-volume"
    }
  ]
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  requires_compatibilities = ["FARGATE"]
}
```
