terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "fail" {
  provisioner "local-exec" {
    command = "echo 'This module is not meant to be used directly. Please use one of the submodules under /modules instead.' && exit 1"
  }
}