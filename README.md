# Datadog Terraform Modules for AWS ECS Tasks

[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/DataDog/terraform-aws-lambda-datadog/blob/main/LICENSE)

Use this [Terraform module](https://registry.terraform.io/modules/DataDog/ecs-datadog/aws/latest) to install Datadog monitoring for AWS Elastic Container Service tasks.

This Terraform module wraps the [aws_ecs_task_definition](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) resource and automatically configures your task definition for Datadog monitoring.

For more information on the ECS Fargate module, reference the submodule [documentation](https://github.com/DataDog/terraform-ecs-datadog/blob/main/modules/ecs_fargate/README.md).

If you encounter any issues, please open a GitHub issue to let us know.

## Usage

### ECS Fargate

```hcl
module "datadog_ecs_fargate_task" {
  source  = "DataDog/ecs-datadog/aws//modules/ecs_fargate"

  # Datadog Configuration
  dd_api_key_secret = {
    arn = "arn:aws:secretsmanager:us-east-1:0000000000:secret:example-secret"
  }
  dd_tags = "team:cont-p, owner:container-monitoring"

  # Task Configuration
  family = "example-app"
  container_definitions = jsonencode([
    {
      name      = "datadog-dogstatsd-app",
      image     = "ghcr.io/datadog/apps-dogstatsd:main",
    }
  ])
}
```
