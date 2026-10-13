# ECS Fargate Python Automatic APM Instrumentation Example

This example registers an ECS Fargate task definition for a sample Python Flask app, with traces and logs sent to Datadog.

The app image doesn't include the Datadog tracer. The `dd_apm_instrumentation` setting adds the Python tracer to the app container when the task starts. Don't add `ddtrace` to `requirements.txt`: if the image already includes the tracer, the added tracer doesn't load.

## Before you begin

* Create a [Datadog API Key](https://app.datadoghq.com/organization-settings/api-keys).
* Install [Docker](https://docs.docker.com/get-docker/), the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), and [Terraform](https://developer.hashicorp.com/terraform/install).
* Set the AWS Region to deploy to:

  ```bash
  export AWS_REGION=us-east-1
  ```

## 1. Build and push the app image

Build the image in the `src` directory and push it to an Amazon ECR repository. The task runs on ARM64, so build the image for `linux/arm64`.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
IMAGE=$REGISTRY/python-ssi-example:latest

# Skip this command if the repository already exists
aws ecr create-repository --repository-name python-ssi-example

aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY
docker build --platform linux/arm64 -t $IMAGE src
docker push $IMAGE
```

## 2. Set the Terraform variables

Create a `terraform.tfvars` file in this directory:

```hcl
dd_api_key = "<DATADOG_API_KEY>"
dd_site    = "datadoghq.com"
image      = "<ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/python-ssi-example:latest"
```

Optionally, set `dd_service` to change the service name of your traces and logs, `dd_env` and `dd_version` to tag your traces, and `task_family_name` to change the task family name (default: `python-ssi-example`).

## 3. Register the task definition

```bash
terraform init
terraform apply
```

## 4. Run the task and send a request

This example registers the task definition only. To run it, you need an ECS cluster and a public subnet with a security group that allows inbound TCP traffic on port 8080.

```bash
aws ecs run-task \
  --cluster <CLUSTER_NAME> \
  --launch-type FARGATE \
  --task-definition $(terraform output -raw task_definition_arn) \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_ID>],securityGroups=[<SECURITY_GROUP_ID>],assignPublicIp=ENABLED}"
```

When the task is running, find its public IP address on the task's page in the Amazon ECS console, and send a request to the app:

```bash
curl http://<PUBLIC_IP>:8080/
```

Traces appear in [APM](https://app.datadoghq.com/apm/traces) and logs in the [Log Explorer](https://app.datadoghq.com/logs) under the `ecs-fargate-python-ssi` service, or the service name you set in `dd_service`.

## Clean up

Stop the task in the Amazon ECS console, and then run:

```bash
terraform destroy
```
