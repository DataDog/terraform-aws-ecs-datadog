# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

################################################################################
# Automatic APM Instrumentation
################################################################################

locals {
  apm_requested            = var.dd_apm_instrumentation != null
  tracer_container_name    = "datadog-tracer"
  tracer_volume_name       = "datadog-tracer"
  tracer_volume_mount_path = "/datadog-lib"
  injection_mode_tag       = "_dd.injection.mode:serverless-single-lang"
  apm_is_arm64             = try(upper(var.runtime_platform.cpu_architecture), "") == "ARM64"
  php_loader_platform      = try(var.dd_apm_instrumentation.tracer_libc, null) == "musl" ? "linux-musl" : "linux-gnu"

  # Tracer startup settings merged into the instrumented container's environment.
  # mode: append or prepend at a separator boundary, or set-if-absent.
  # preserve_leading_empty: a leading separator keeps PHP's default scan directory.
  apm_env_fragments_by_language = {
    java = [
      {
        name                   = "JAVA_TOOL_OPTIONS"
        value                  = "-javaagent:${local.tracer_volume_mount_path}/dd-java-agent.jar -XX:+IgnoreUnrecognizedVMOptions"
        mode                   = "append"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    js = [
      {
        name                   = "NODE_OPTIONS"
        value                  = "--require ${local.tracer_volume_mount_path}/node_modules/dd-trace/init.js"
        mode                   = "append"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    dotnet = [
      {
        name                   = "CORECLR_ENABLE_PROFILING"
        value                  = "1"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "CORECLR_PROFILER"
        value                  = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "CORECLR_PROFILER_PATH"
        value                  = "${local.tracer_volume_mount_path}/Datadog.Trace.ClrProfiler.Native.so"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "DD_DOTNET_TRACER_HOME"
        value                  = local.tracer_volume_mount_path
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "LD_PRELOAD"
        value                  = "${local.tracer_volume_mount_path}/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so"
        mode                   = "prepend"
        separator              = " "
        preserve_leading_empty = false
        max_length             = 1024
      },
    ]
    python = [
      {
        name                   = "PYTHONPATH"
        value                  = local.tracer_volume_mount_path
        mode                   = "append"
        separator              = ":"
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    ruby = [
      {
        name                   = "RUBYOPT"
        value                  = "-r${local.tracer_volume_mount_path}/auto_inject"
        mode                   = "prepend"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    php = [
      {
        name                   = "PHP_INI_SCAN_DIR"
        value                  = "${local.tracer_volume_mount_path}/${local.php_loader_platform}/loader"
        mode                   = "append"
        separator              = ":"
        preserve_leading_empty = true
        max_length             = null
      },
      {
        name                   = "DD_LOADER_PACKAGE_PATH"
        value                  = local.tracer_volume_mount_path
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
    ]
  }
  apm_env_fragments    = local.apm_requested ? local.apm_env_fragments_by_language[var.dd_apm_instrumentation.language] : []
  apm_loader_env_names = [for fragment in local.apm_env_fragments : fragment.name]
  apm_owned_env_names  = concat(local.apm_loader_env_names, ["DD_TAGS"])

  # Application container selection
  apm_reserved_container_names = ["datadog-agent", "datadog-log-router", local.tracer_container_name]
  # Opted-out plans must not read `container_definitions`, which can be unknown until apply.
  apm_candidates = local.apm_requested ? [
    for index, container in local.application_containers : { index = index, name = try(container.name, "") }
    if !contains(local.apm_reserved_container_names, try(container.name, ""))
  ] : []
  apm_candidate_names = [for candidate in local.apm_candidates : candidate.name]
  apm_container_name  = local.apm_requested ? try(trimspace(var.dd_apm_instrumentation.container_name), "") : ""
  apm_named_candidates = [
    for candidate in local.apm_candidates : candidate if candidate.name == local.apm_container_name
  ]
  # Never fall back to list order: several candidates require `container_name`.
  apm_target_index = !local.apm_requested ? null : (
    local.apm_container_name != "" ? try(local.apm_named_candidates[0].index, null) : (
      length(local.apm_candidates) == 1 ? local.apm_candidates[0].index : null
    )
  )
  apm_target_container = local.apm_target_index == null ? null : local.application_containers[local.apm_target_index]

  # Environment of the selected container, which the tracer settings merge into
  apm_target_env = [
    for env in try(local.apm_target_container.environment, []) : {
      name  = try(env.name, null)
      value = try(env.value, null)
    }
  ]
  apm_target_env_names    = [for env in local.apm_target_env : env.name]
  apm_target_secret_names = [for secret in try(local.apm_target_container.secrets, []) : try(secret.name, null)]
  apm_target_literal_env = {
    for env in local.apm_target_env : env.name => env.value
    if env.name != null && env.value != null && length([for name in local.apm_target_env_names : name if name == env.name]) == 1
  }
  apm_existing_env = {
    for fragment in local.apm_env_fragments : fragment.name => lookup(local.apm_target_literal_env, fragment.name, "")
  }

  apm_merged_loader_env = {
    for fragment in local.apm_env_fragments : fragment.name => (
      fragment.mode == "set-if-absent" ? (
        local.apm_existing_env[fragment.name] != "" ? local.apm_existing_env[fragment.name] : fragment.value
        ) : (
        strcontains(
          "${fragment.separator}${local.apm_existing_env[fragment.name]}${fragment.separator}",
          "${fragment.separator}${fragment.value}${fragment.separator}",
          ) ? local.apm_existing_env[fragment.name] : (
          local.apm_existing_env[fragment.name] == "" ? (
            fragment.preserve_leading_empty ? "${fragment.separator}${fragment.value}" : fragment.value
            ) : (
            fragment.mode == "append"
            ? "${local.apm_existing_env[fragment.name]}${fragment.separator}${fragment.value}"
            : "${fragment.value}${fragment.separator}${local.apm_existing_env[fragment.name]}"
          )
        )
      )
    )
  }
  # length() counts characters, but the limit is in bytes.
  apm_merged_loader_env_bytes = {
    for name, value in local.apm_merged_loader_env :
    name => length(base64encode(value)) / 4 * 3 - length(regexall("=", base64encode(value)))
  }

  apm_existing_dd_tags = lookup(local.apm_target_literal_env, "DD_TAGS", "")
  # Tracers split DD_TAGS on commas when one is present, otherwise on whitespace.
  apm_dd_tags_separator = !strcontains(local.apm_existing_dd_tags, ",") && length(regexall("\\s", local.apm_existing_dd_tags)) > 0 ? " " : ","
  apm_dd_tags = contains(split(local.apm_dd_tags_separator, local.apm_existing_dd_tags), local.injection_mode_tag) ? local.apm_existing_dd_tags : (
    local.apm_existing_dd_tags == "" ? local.injection_mode_tag : "${local.injection_mode_tag}${local.apm_dd_tags_separator}${local.apm_existing_dd_tags}"
  )

  # Configurations the module cannot safely instrument
  apm_secret_env_names = [
    for name in local.apm_owned_env_names : name if contains(local.apm_target_secret_names, name)
  ]
  apm_duplicate_env_names = [
    for name in local.apm_owned_env_names : name
    if length([for env_name in local.apm_target_env_names : env_name if env_name == name]) > 1
  ]
  apm_set_if_absent_conflicts = [
    for fragment in local.apm_env_fragments : fragment.name
    if fragment.mode == "set-if-absent" && !contains(["", fragment.value], local.apm_existing_env[fragment.name])
  ]
  apm_env_exceeding_max_length = [
    for fragment in local.apm_env_fragments : fragment.name
    if fragment.max_length == null ? false : local.apm_merged_loader_env_bytes[fragment.name] > fragment.max_length
  ]
  apm_tracer_name_taken = local.apm_requested ? anytrue(concat(
    [for container in local.application_containers : try(container.name, "") == local.tracer_container_name],
    [for volume in coalesce(var.volumes, []) : volume.name == local.tracer_volume_name],
  )) : false
  apm_conflicting_mounts = !local.apm_requested ? [] : flatten([
    for index, container in local.application_containers : [
      for mount in try(container.mountPoints, []) : "${try(container.name, "")}:${try(mount.containerPath, "")}"
      if try(mount.sourceVolume, "") == local.tracer_volume_name || (
        index == local.apm_target_index && try(mount.containerPath, "") == local.tracer_volume_mount_path
      )
    ]
  ])

  apm_enabled = (
    local.apm_requested &&
    local.apm_target_index != null &&
    length(local.apm_secret_env_names) == 0 &&
    length(local.apm_duplicate_env_names) == 0 &&
    length(local.apm_set_if_absent_conflicts) == 0 &&
    length(local.apm_env_exceeding_max_length) == 0 &&
    !local.apm_tracer_name_taken &&
    length(local.apm_conflicting_mounts) == 0
  )
  apm_instrumented_index = local.apm_enabled ? local.apm_target_index : null

  # Contributions to the instrumented container
  apm_target_env_vars = [
    for name, value in merge({ DD_TAGS = local.apm_dd_tags }, local.apm_merged_loader_env) : { name = name, value = value }
  ]
  tracer_mount = {
    sourceVolume  = local.tracer_volume_name
    containerPath = local.tracer_volume_mount_path
    readOnly      = false
  }
  tracer_dependency = {
    containerName = local.tracer_container_name
    condition     = "SUCCESS"
  }

  # First awslogs configuration of an application container
  apm_borrowed_log_configuration = try([
    for container in local.application_containers : container.logConfiguration
    if try(container.logConfiguration.logDriver, null) == "awslogs"
  ][0], null)

  # Datadog tracer copy container definition
  dd_tracer_container = local.apm_enabled ? [
    merge(
      {
        name  = local.tracer_container_name
        image = "public.ecr.aws/datadog/dd-lib-${var.dd_apm_instrumentation.language}-init:${var.dd_apm_instrumentation.tracer_version}"
        # SUCCESS dependencies require a non-essential container.
        essential = false
        # The image's default user cannot write to the root-owned task volume.
        user           = "0"
        entryPoint     = ["/datadog-init/copy-lib.sh"]
        command        = [local.tracer_volume_mount_path]
        mountPoints    = [local.tracer_mount]
        dependsOn      = local.log_router_dependency
        dockerLabels   = var.dd_docker_labels
        portMappings   = []
        systemControls = []
        volumesFrom    = []
      },
      # Without FireLens, borrow the application's awslogs settings so a failed copy still leaves logs.
      local.dd_firelens_log_configuration != null ? { logConfiguration = local.dd_firelens_log_configuration } : {},
      local.dd_firelens_log_configuration == null && local.apm_borrowed_log_configuration != null ? { logConfiguration = local.apm_borrowed_log_configuration } : {},
    )
  ] : []

  tracer_volume = local.apm_enabled ? [{ name = local.tracer_volume_name }] : []

  apm_tags = local.apm_enabled ? { dd_sls_injection_mode = "single_language" } : {}
}

check "apm_target_container_exists" {
  assert {
    condition     = !local.apm_requested || length(local.apm_candidates) > 0
    error_message = "Automatic APM instrumentation found no application container in `container_definitions`. Add one to instrument. The module doesn't add the tracer."
  }
}

check "apm_target_container_known" {
  assert {
    condition     = !local.apm_requested || local.apm_container_name == "" || length(local.apm_named_candidates) > 0
    error_message = "`dd_apm_instrumentation.container_name` is '${local.apm_container_name}', but no application container has that name. Choose one of: ${join(", ", local.apm_candidate_names)}. The module doesn't add the tracer."
  }
}

check "apm_target_container_not_ambiguous" {
  assert {
    condition     = !local.apm_requested || local.apm_container_name != "" || length(local.apm_candidates) <= 1
    error_message = "The task definition has several application containers: ${join(", ", local.apm_candidate_names)}. Set `dd_apm_instrumentation.container_name` to the one to instrument. The module doesn't add the tracer."
  }
}

check "apm_env_not_secret_backed" {
  assert {
    condition     = !local.apm_requested || length(local.apm_secret_env_names) == 0
    error_message = "The container to instrument sets ${join(", ", local.apm_secret_env_names)} from `secrets`, so the module can't add the tracer settings. Set these variables in `environment` instead, or remove them. The module doesn't add the tracer."
  }
}

check "apm_env_not_duplicated" {
  assert {
    condition     = !local.apm_requested || length(local.apm_duplicate_env_names) == 0
    error_message = "The container to instrument sets ${join(", ", local.apm_duplicate_env_names)} more than once in `environment`. Remove the duplicates. The module doesn't add the tracer."
  }
}

check "apm_env_set_if_absent_compatible" {
  assert {
    condition     = !local.apm_requested || length(local.apm_set_if_absent_conflicts) == 0
    error_message = "The container to instrument sets ${join(", ", local.apm_set_if_absent_conflicts)} to values that conflict with the tracer. Remove these variables, or set them to the tracer's values. The module doesn't add the tracer."
  }
}

check "apm_env_within_max_length" {
  assert {
    condition     = !local.apm_requested || length(local.apm_env_exceeding_max_length) == 0
    error_message = "Adding the tracer settings to ${join(", ", local.apm_env_exceeding_max_length)} on the container to instrument exceeds the length limit. Shorten the existing value. The module doesn't add the tracer."
  }
}

check "apm_tracer_name_available" {
  assert {
    condition     = !local.apm_requested || !local.apm_tracer_name_taken
    error_message = "The task definition already has a container or volume named '${local.tracer_container_name}', which the module uses to add the tracer. Rename it. The module doesn't add the tracer."
  }
}

check "apm_tracer_mounts_available" {
  assert {
    condition     = !local.apm_requested || length(local.apm_conflicting_mounts) == 0
    error_message = "These mount points conflict with the tracer volume: ${join(", ", local.apm_conflicting_mounts)}. Don't mount the '${local.tracer_volume_name}' volume, or anything at '${local.tracer_volume_mount_path}' on the container to instrument. The module doesn't add the tracer."
  }
}
