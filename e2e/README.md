# E2E tests

The suite runs the `ecs_fargate` module against a temporary ECS Fargate service:

1. Apply [the fixture](fixture/main.tf), which uses the module with automatic APM instrumentation to register a Node.js service and one task definition for each other tracer language.
2. Verify each registered revision: the Datadog Agent and log router containers, the API key reference, and the injected tracer.
3. Send requests to the service and wait for its spans and logs in Datadog.
4. Confirm that `terraform plan` reports no changes.
5. Run `terraform destroy` and verify that the service and task definitions are gone.

The language task definitions are registered but never run, so only the Node.js service proves that an injected tracer loads and sends traces.

The `shared` directory is synced from `serverless-ci`. Don't edit it here.

## Resources

The suite deploys into resources that are provisioned outside this repository. Set these variables:

| Variable | Description |
| --- | --- |
| `AWS_ECS_CLUSTER` | The ECS cluster that runs the service. |
| `AWS_ECS_SUBNETS` | Comma-separated public subnets of one VPC. |
| `AWS_ECS_SECURITY_GROUP` | A security group that allows inbound traffic on port 8080. |
| `AWS_ECS_EXECUTION_ROLE_ARN` | The task execution role. It must be able to pull the fixture images and read the API key secret. |
| `AWS_ECS_TASK_ROLE_ARN` | The task role. |
| `AWS_ECS_APP_IMAGE_REGISTRY` | The registry that hosts the `node-ssi`, `dotnet-ssi`, `java-ssi`, `php-ssi`, `python-ssi`, and `ruby-ssi` fixture images. |
| `AWS_ECS_API_KEY_SECRET_ARN` | The complete ARN of a Secrets Manager secret that holds a Datadog API key, optionally followed by `:<json-field>::`. The key must belong to the organization whose telemetry the suite queries. |
| `AWS_ECS_LOG_GROUP` | The CloudWatch Logs group for the language task definitions. |

The suite defaults to `eu-central-1` and `datadoghq.com`. Set `AWS_REGION` or `DD_SITE` to override them. To test another Agent version than the pinned one, set `E2E_AGENT_IMAGE_VERSION`.

## Run locally

You need Go, Terraform 1.5 or later, the AWS CLI, AWS credentials for the account, and Datadog API and application keys for the organization.

```bash
cd e2e
aws-vault exec sso-serverless-sandbox-account-admin -- \
  dd-auth --domain ddserverless.datadoghq.com -- bash -c '
    export DATADOG_API_KEY="$DD_API_KEY" DATADOG_APP_KEY="$DD_APP_KEY"
    go test -count=1 -v -timeout 50m .
  '
```

To check only the verifier, which needs no credentials, run `go test -run TestVerify .`.

## CI

[The E2E workflow](../.github/workflows/e2e.yaml) runs the suite when the module or the suite changes, once the `AWS_ECS_*_E2E` repository variables are set. It assumes the `AWS_ROLE_ARN_E2E` role through GitHub OIDC and reads the Datadog API and application keys from the `DATADOG_API_KEY_E2E` and `DATADOG_APP_KEY_E2E` secrets.

The role needs the shared `ecs-fargate-e2e` policy from `serverless-ci/e2e/terraform/aws/oidc-roles.tf`.

## Resource cleanup

Each run names its service and task definition families after `one-e2e-tf-ecs-<runid>`, and tags them with its run ID and creation time. The suite always runs `terraform destroy` at the end, and the `serverless-ci` sweeper deletes what a cancelled run leaves behind. To delete a run's service yourself:

```bash
aws ecs delete-service --cluster "$AWS_ECS_CLUSTER" --service one-e2e-tf-ecs-<runid> --force --region eu-central-1
```
