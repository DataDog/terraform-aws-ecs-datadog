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

# Opting out must keep tags known when container definitions are only known after apply.
run "opted_out_tags_stay_known" {
  command = plan

  module {
    source = "./tests/unknown_container_definitions"
  }

  assert {
    condition     = !contains(keys(output.tags), "dd_sls_injection_mode")
    error_message = "Tags must be known at plan time and must not carry the injection mode tag."
  }
}
