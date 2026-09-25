# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

# Plan-only tests: the provider never calls AWS, so no credentials are needed.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

variables {
  dd_api_key = "test-api-key"
  family     = "apm-instrumentation-test"
}

################################################################################
# Instrumentation
################################################################################

run "disabled_by_default" {
  command = plan

  variables {
    container_definitions = <<-EOT
      [{"name": "app", "image": "python:3.12-slim", "essential": true}]
    EOT
  }

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added unless dd_apm_instrumentation is set."
  }

  assert {
    condition     = !contains(keys(aws_ecs_task_definition.this.tags), "dd_sls_injection_mode")
    error_message = "The injection mode tag must not be set unless dd_apm_instrumentation is set."
  }
}

run "python_extends_existing_settings" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python", container_name = "app" }
    container_definitions  = <<-EOT
      [
        {"name": "sidecar", "image": "busybox", "essential": false},
        {"name": "app", "image": "python:3.12-slim", "essential": true, "environment": [
          {"name": "PYTHONPATH", "value": "/app"},
          {"name": "DD_TAGS", "value": "team:serverless"},
          {"name": "DD_TRACE_ENABLED", "value": "false"}
        ]}
      ]
    EOT
  }

  assert {
    condition = {
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.name => env.value if contains(["PYTHONPATH", "DD_TAGS", "DD_TRACE_ENABLED"], env.name)
      } == {
      PYTHONPATH       = "/app:/datadog-lib"
      DD_TAGS          = "_dd.injection.mode:serverless-single-lang,team:serverless"
      DD_TRACE_ENABLED = "false"
    }
    error_message = "The tracer settings must extend the existing values and leave DD_TRACE_ENABLED alone."
  }

  assert {
    condition = one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "datadog-tracer"]) == {
      name           = "datadog-tracer"
      image          = "public.ecr.aws/datadog/dd-lib-python-init:latest"
      essential      = false
      user           = "0"
      entryPoint     = ["/datadog-init/copy-lib.sh"]
      command        = ["/datadog-lib"]
      mountPoints    = [{ sourceVolume = "datadog-tracer", containerPath = "/datadog-lib", readOnly = false }]
      dependsOn      = []
      dockerLabels   = {}
      portMappings   = []
      systemControls = []
      volumesFrom    = []
    }
    error_message = "Unexpected datadog-tracer container definition."
  }

  assert {
    condition = alltrue([
      contains(one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).mountPoints, { sourceVolume = "datadog-tracer", containerPath = "/datadog-lib", readOnly = false }),
      contains(one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).dependsOn, { containerName = "datadog-tracer", condition = "SUCCESS" }),
    ])
    error_message = "The instrumented container must mount the tracer volume and wait for the copy to succeed."
  }

  assert {
    condition = alltrue([
      !contains([for m in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "sidecar"]).mountPoints : m.sourceVolume], "datadog-tracer"),
      !contains([for d in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "sidecar"]).dependsOn : d.containerName], "datadog-tracer"),
      !contains([for e in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "sidecar"]).environment : e.name], "PYTHONPATH"),
    ])
    error_message = "Only the selected container may be instrumented."
  }

  assert {
    condition     = aws_ecs_task_definition.this.tags["dd_sls_injection_mode"] == "single_language"
    error_message = "The injection mode tag must be set."
  }
}

run "java_appends_and_logs_through_firelens" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "java" }
    dd_log_collection = {
      enabled          = true
      fluentbit_config = { is_log_router_dependency_enabled = true }
    }
    container_definitions = <<-EOT
      [{"name": "app", "image": "eclipse-temurin:21", "essential": true, "environment": [
        {"name": "JAVA_TOOL_OPTIONS", "value": "-Xmx512m"}
      ]}]
    EOT
  }

  assert {
    condition = [
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.value if env.name == "JAVA_TOOL_OPTIONS"
    ] == ["-Xmx512m -javaagent:/datadog-lib/dd-java-agent.jar -XX:+IgnoreUnrecognizedVMOptions"]
    error_message = "The Java agent must be appended to JAVA_TOOL_OPTIONS."
  }

  assert {
    condition = alltrue([
      one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "datadog-tracer"]).logConfiguration.logDriver == "awsfirelens",
      one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "datadog-tracer"]).dependsOn == [{ containerName = "datadog-log-router", condition = "HEALTHY" }],
    ])
    error_message = "With log collection enabled, the tracer container must log through FireLens."
  }
}

run "js_keeps_existing_fragment" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "js" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "node:22", "essential": true, "environment": [
        {"name": "NODE_OPTIONS", "value": "--require /datadog-lib/node_modules/dd-trace/init.js --max-old-space-size=512"}
      ]}]
    EOT
  }

  assert {
    condition = [
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.value if env.name == "NODE_OPTIONS"
    ] == ["--require /datadog-lib/node_modules/dd-trace/init.js --max-old-space-size=512"]
    error_message = "An existing tracer fragment must not be added twice."
  }
}

run "dotnet_sets_profiler_and_prepends_ld_preload" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "dotnet", tracer_version = "v3.10.0" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "mcr.microsoft.com/dotnet/aspnet:8.0", "essential": true, "environment": [
        {"name": "LD_PRELOAD", "value": "/usr/lib/libfoo.so"},
        {"name": "CORECLR_ENABLE_PROFILING", "value": "1"}
      ]}]
    EOT
  }

  assert {
    condition = {
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.name => env.value if startswith(env.name, "CORECLR_") || contains(["DD_DOTNET_TRACER_HOME", "LD_PRELOAD"], env.name)
      } == {
      CORECLR_ENABLE_PROFILING = "1"
      CORECLR_PROFILER         = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
      CORECLR_PROFILER_PATH    = "/datadog-lib/Datadog.Trace.ClrProfiler.Native.so"
      DD_DOTNET_TRACER_HOME    = "/datadog-lib"
      LD_PRELOAD               = "/datadog-lib/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so /usr/lib/libfoo.so"
    }
    error_message = "Unexpected .NET tracer settings."
  }

  assert {
    condition     = one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "datadog-tracer"]).image == "public.ecr.aws/datadog/dd-lib-dotnet-init:v3.10.0"
    error_message = "The tracer image must use the requested version."
  }
}

run "ruby_prepends_and_keeps_space_separated_tags" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "ruby" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "ruby:3.3", "essential": true, "environment": [
        {"name": "RUBYOPT", "value": "-W0"},
        {"name": "DD_TAGS", "value": "team:serverless env:prod"}
      ]}]
    EOT
  }

  assert {
    condition = {
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.name => env.value if contains(["RUBYOPT", "DD_TAGS"], env.name)
      } == {
      RUBYOPT = "-r/datadog-lib/auto_inject -W0"
      DD_TAGS = "_dd.injection.mode:serverless-single-lang team:serverless env:prod"
    }
    error_message = "RUBYOPT must be prepended, and space-separated DD_TAGS must stay space-separated."
  }
}

run "php_musl_keeps_default_scan_dir" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "php", tracer_libc = "musl", container_name = "  " }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "php:8.3-fpm-alpine", "essential": true, "environment": [
        {"name": "DD_TAGS", "value": "team:serverless _dd.injection.mode:serverless-single-lang"}
      ]}]
    EOT
  }

  assert {
    condition = {
      for env in one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "app"]).environment :
      env.name => env.value if contains(["PHP_INI_SCAN_DIR", "DD_LOADER_PACKAGE_PATH", "DD_TAGS"], env.name)
      } == {
      PHP_INI_SCAN_DIR       = ":/datadog-lib/linux-musl/loader"
      DD_LOADER_PACKAGE_PATH = "/datadog-lib"
      DD_TAGS                = "team:serverless _dd.injection.mode:serverless-single-lang"
    }
    error_message = "Unexpected PHP tracer settings, or the injection mode tag was added twice."
  }
}

run "tracer_logs_borrow_awslogs" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "python:3.12-slim", "essential": true, "logConfiguration": {
        "logDriver": "awslogs",
        "options": {"awslogs-group": "/ecs/app", "awslogs-region": "us-east-1", "awslogs-stream-prefix": "app"}
      }}]
    EOT
  }

  assert {
    condition = one([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "datadog-tracer"]).logConfiguration == {
      logDriver = "awslogs"
      options   = { awslogs-group = "/ecs/app", awslogs-region = "us-east-1", awslogs-stream-prefix = "app" }
    }
    error_message = "Without FireLens, the tracer container must reuse the application's awslogs configuration."
  }
}

################################################################################
# Configurations the module skips with a warning
################################################################################

run "skips_without_application_container" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python" }
    container_definitions  = "[]"
  }

  expect_failures = [check.apm_target_container_exists]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_unknown_container_name" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python", container_name = "missing" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "python:3.12-slim", "essential": true}]
    EOT
  }

  expect_failures = [check.apm_target_container_known]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_ambiguous_container" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python" }
    container_definitions  = <<-EOT
      [
        {"name": "a", "image": "busybox", "essential": false},
        {"name": "b", "image": "python:3.12-slim", "essential": true}
      ]
    EOT
  }

  expect_failures = [check.apm_target_container_not_ambiguous]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_secret_backed_setting" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "python:3.12-slim", "essential": true, "secrets": [
        {"name": "PYTHONPATH", "valueFrom": "arn:aws:ssm:us-east-1:123456789012:parameter/pythonpath"}
      ]}]
    EOT
  }

  expect_failures = [check.apm_env_not_secret_backed]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_duplicated_setting" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "python" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "python:3.12-slim", "essential": true, "environment": [
        {"name": "PYTHONPATH", "value": "/a"},
        {"name": "PYTHONPATH", "value": "/b"}
      ]}]
    EOT
  }

  expect_failures = [check.apm_env_not_duplicated]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_conflicting_setting" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "dotnet" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "mcr.microsoft.com/dotnet/aspnet:8.0", "essential": true, "environment": [
        {"name": "CORECLR_ENABLE_PROFILING", "value": "0"}
      ]}]
    EOT
  }

  expect_failures = [check.apm_env_set_if_absent_compatible]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_ld_preload_over_byte_limit" {
  command = plan

  # Under 1024 characters but over 1024 bytes once merged, so only a byte count exceeds the limit.
  variables {
    dd_apm_instrumentation = { language = "dotnet" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "mcr.microsoft.com/dotnet/aspnet:8.0", "essential": true, "environment": [
        {"name": "LD_PRELOAD", "value": "/ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé.so"}
      ]}]
    EOT
  }

  expect_failures = [check.apm_env_within_max_length]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_taken_volume_name" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "java" }
    volumes                = [{ name = "datadog-tracer" }]
    container_definitions  = <<-EOT
      [{"name": "app", "image": "eclipse-temurin:21", "essential": true}]
    EOT
  }

  expect_failures = [check.apm_tracer_name_available]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

run "skips_conflicting_mount" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "java" }
    volumes                = [{ name = "shared" }]
    container_definitions  = <<-EOT
      [{"name": "app", "image": "eclipse-temurin:21", "essential": true, "mountPoints": [
        {"sourceVolume": "shared", "containerPath": "/datadog-lib", "readOnly": false}
      ]}]
    EOT
  }

  expect_failures = [check.apm_tracer_mounts_available]

  assert {
    condition     = !contains([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.name], "datadog-tracer")
    error_message = "The tracer container must not be added."
  }
}

################################################################################
# Configurations the module rejects
################################################################################

run "rejects_windows" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "dotnet" }
    runtime_platform       = { operating_system_family = "WINDOWS_SERVER_2022_CORE", cpu_architecture = "X86_64" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "busybox", "essential": true}]
    EOT
  }

  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_dotnet_on_arm64" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "dotnet" }
    runtime_platform       = { operating_system_family = "LINUX", cpu_architecture = "ARM64" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "busybox", "essential": true}]
    EOT
  }

  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_ruby_on_musl" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "ruby", tracer_libc = "musl" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "busybox", "essential": true}]
    EOT
  }

  expect_failures = [var.dd_apm_instrumentation]
}

run "rejects_dotnet_before_3" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "dotnet", tracer_version = "2.49.0" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "busybox", "essential": true}]
    EOT
  }

  expect_failures = [var.dd_apm_instrumentation]
}

run "rejects_go" {
  command = plan

  variables {
    dd_apm_instrumentation = { language = "go" }
    container_definitions  = <<-EOT
      [{"name": "app", "image": "busybox", "essential": true}]
    EOT
  }

  expect_failures = [var.dd_apm_instrumentation]
}
