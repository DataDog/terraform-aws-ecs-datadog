provider "aws" {
  region      = "us-east-1"
  retry_mode  = "standard"
  max_retries = 10
}