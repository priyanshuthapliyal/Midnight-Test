terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.9.0"
    }
  }

  # Local backend for single-host Docker target.
  # Isolate environments via `terraform workspace select -or-create <preview|preprod|mainnet>`.
  backend "local" {}
}
