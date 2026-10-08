# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"
  tags = var.tags
}

################################################################################
# ECS Infrastructure Role
#
# Allows Amazon ECS to manage the lifecycle of Managed Instances on your
# behalf. Not managed by the ecs_managed_instances module - the daemon module
# only manages the Datadog Agent's own task definition and daemon resource.
################################################################################

resource "aws_iam_role" "ecs_infrastructure" {
  name = "${var.name_prefix}-ecs-infrastructure-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances"
}

################################################################################
# EC2 Instance Profile
#
# IMPORTANT: the AmazonECSInstanceRolePolicyForManagedInstances managed policy
# scopes iam:PassRole to role names matching "ecsInstanceRole*". The role name
# below is therefore a hardcoded literal starting with "ecsInstanceRole",
# NOT a name_prefix or module-computed name like most other resources in this
# repo's examples - a Terraform-generated or differently-prefixed name causes
# task launches to fail at runtime with a ResourceInitializationError /
# iam:PassRole authorization error.
################################################################################

resource "aws_iam_role" "ecs_instance" {
  name = "ecsInstanceRole-${var.name_prefix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInstanceRolePolicyForManagedInstances"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = aws_iam_role.ecs_instance.name
  role = aws_iam_role.ecs_instance.name

  tags = var.tags
}

################################################################################
# ECS Managed Instances Capacity Provider
#
# The module does not create this - callers are expected to bring an existing
# ECS Managed Instances cluster/capacity provider, the same boundary ecs_ec2
# uses for cluster_arn.
################################################################################

resource "aws_ecs_capacity_provider" "managed_instances" {
  name = "${var.name_prefix}-mi-cp"
  # The managed_instances_provider CustomizeDiff validator wants the cluster
  # NAME here, not its ARN - passing the ARN fails apply with "invalid value
  # for cluster (The cluster name must consist of alphanumerics, hyphens,
  # and underscores.)", confirmed against live AWS.
  cluster = aws_ecs_cluster.this.name

  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.ecs_infrastructure.arn
    propagate_tags          = "CAPACITY_PROVIDER"

    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.ecs_instance.arn
      monitoring               = "BASIC"

      network_configuration {
        subnets         = var.subnet_ids
        security_groups = var.security_group_ids
      }

      instance_requirements {
        memory_mib {
          min = 1024
          max = 8192
        }

        vcpu_count {
          min = 1
          max = 4
        }
      }
    }
  }

  tags = var.tags
}

################################################################################
# Datadog Agent Managed Daemon
################################################################################

module "datadog_agent" {
  source = "../../modules/ecs_managed_instances"

  # Datadog Configuration
  dd_api_key = var.datadog_api_key
  dd_site    = var.dd_site

  dd_dogstatsd = {
    enabled                  = true
    origin_detection_enabled = true
    dogstatsd_cardinality    = "orchestrator"
  }

  dd_apm = {
    enabled                       = true
    profiling                     = true
    trace_inferred_proxy_services = false
    data_streams                  = false
  }

  dd_orchestrator_explorer = {
    enabled = true
  }

  dd_process_collection = {
    enabled = true
  }

  # Task Definition
  family = "${var.name_prefix}-datadog-agent"

  # Daemon
  create_daemon          = true
  cluster_arn            = aws_ecs_cluster.this.arn
  daemon_name            = "${var.name_prefix}-datadog-agent"
  capacity_provider_arns = [aws_ecs_capacity_provider.managed_instances.arn]

  deployment_configuration = {
    drain_percent        = 25
    bake_time_in_minutes = 5
  }

  tags = var.tags
}

################################################################################
# Example Application Task (connects to the daemon over UDS)
#
# This task definition is entirely separate from the Datadog module - the
# module only manages the daemon. Every application that wants to send
# metrics/traces must mount the shared dd-sockets volume and set the
# DD_DOGSTATSD_URL/DD_TRACE_AGENT_URL environment variables itself, using the
# module's helper outputs below.
################################################################################

resource "aws_iam_role" "app_task_role" {
  name = "${var.name_prefix}-app-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role" "app_execution_role" {
  name = "${var.name_prefix}-app-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "app_execution_role_policy" {
  role       = aws_iam_role.app_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "dogstatsd_app" {
  name              = "/ecs/${var.name_prefix}-dogstatsd-app"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_ecs_task_definition" "dogstatsd_app" {
  family = "${var.name_prefix}-dogstatsd-app"
  # bridge is not a valid network mode for MANAGED_INSTANCES - the only
  # valid values are host and awsvpc, confirmed against live AWS
  # ("Network mode of MANAGED_INSTANCES must be one of [host, awsvpc]").
  network_mode             = "host"
  task_role_arn            = aws_iam_role.app_task_role.arn
  execution_role_arn       = aws_iam_role.app_execution_role.arn
  requires_compatibilities = ["MANAGED_INSTANCES"]

  container_definitions = jsonencode([{
    name      = "dogstatsd-app"
    image     = "ghcr.io/datadog/apps-dogstatsd:main"
    essential = true

    # Use the module's helper outputs to point at the Datadog Agent daemon
    # over the shared UDS sockets.
    environment = concat(
      module.datadog_agent.dogstatsd_env_vars,
      module.datadog_agent.apm_env_vars,
      [
        {
          name  = "DD_SERVICE"
          value = "dogstatsd-app"
        },
        {
          name  = "DD_ENV"
          value = var.environment
        },
        {
          name  = "DD_VERSION"
          value = "1.0.0"
        }
      ]
    )

    mountPoints = [module.datadog_agent.app_dd_sockets_mount]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.dogstatsd_app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "dogstatsd-app"
      }
    }

    memory = 256
    cpu    = 256
  }])

  volume {
    name      = module.datadog_agent.app_dd_sockets_volume.name
    host_path = module.datadog_agent.app_dd_sockets_volume.host_path
  }

  tags = var.tags
}

resource "aws_ecs_service" "dogstatsd_app" {
  name            = "${var.name_prefix}-dogstatsd-app"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = aws_ecs_task_definition.dogstatsd_app.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.managed_instances.name
    weight            = 1
  }

  # Ensure Datadog agent daemon is deployed before application tasks
  depends_on = [module.datadog_agent]

  tags = var.tags
}
