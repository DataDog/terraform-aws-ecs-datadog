# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Task Definition: All Task Parameters Example
################################################################################

resource "aws_efs_file_system" "fs" {
  creation_token   = "my-efs-file-system"
  performance_mode = "generalPurpose"
  tags = {
    Name = "MyEFSFileSystem"
  }
}

resource "aws_efs_access_point" "fs" {
  file_system_id = aws_efs_file_system.fs.id
  posix_user {
    uid = 1000
    gid = 1000
  }
  root_directory {
    path = "/example"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_task_policy" {
  name        = "ecs_task_policy"
  description = "Policy for ECS task role to access EFS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEFSMountAndWrite"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.fs.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# Tests that the module is able to create a task
# with all the AWS task definition parameters
module "ecs_task_all_task_features" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  dd_service = var.dd_service

  family = "all-task-features"
  container_definitions = jsonencode([
    {
      name      = "datadog-dummy-app",
      image     = "public.ecr.aws/ubuntu/ubuntu:22.04_stable",
      essential = true,
      entryPoint = [
        "/usr/bin/bash",
        "-c",
        "cp /usr/bin/bash /tmp/malware; chmod u+s /tmp/malware; apt update;apt install -y curl wget; /tmp/malware -c 'while true; do wget https://google.com; sleep 60; done'"
      ],
    }
  ])
  cpu                    = 256
  memory                 = 512
  enable_fault_injection = false
  ephemeral_storage = {
    size_in_gib = 40
  }
  network_mode = "awsvpc"
  pid_mode     = "task"
  proxy_configuration = {
    type           = "APPMESH"
    container_name = "datadog-dummy-app"
    properties = {
      AppPorts         = "8080"
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = "1337"
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }
  task_role_arn = aws_iam_role.ecs_task_role.arn
  volumes = [
    {
      name = "docker-storage"
      # Not supported on FARGATE:
      # docker_volume_configuration = {
      #   scope         = "shared"
      #   autoprovision = true
      #   driver        = "local"
      #   driver_opts = {
      #     "type"   = "nfs"
      #     "device" = "${aws_efs_file_system.fs.dns_name}:/"
      #     "o"      = "addr=${aws_efs_file_system.fs.dns_name},rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
      #   }
      # }
    },
    {
      name = "efs-storage"
      efs_volume_configuration = {
        file_system_id          = aws_efs_file_system.fs.id
        root_directory          = "/"
        transit_encryption      = "ENABLED"
        transit_encryption_port = 2999
        authorization_config = {
          access_point_id = aws_efs_access_point.fs.id
          iam             = "ENABLED"
        }
      }
    }
  ]
  skip_destroy          = false
  inference_accelerator = null
  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

# Tests that the Datadog agent configuration on Windows is correct
# In particular, we are checking APM, Dogstatsd, and `ecs.fargate` metrics
module "ecs_fargate_task_windows" {
  source = "../../modules/ecs_fargate"

  dd_api_key = var.dd_api_key
  dd_site    = var.dd_site
  dd_service = var.dd_service

  dd_apm = {
    enabled = true
  }

  dd_dogstatsd = {
    enabled = true
  }

  family = "windows-features"
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
  cpu    = 1024
  memory = 2048
  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "WINDOWS_SERVER_2022_CORE"
  }
}
