terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend block on purpose: this folder creates the backend, so it must run on LOCAL state first.
  # (See README "chicken-and-egg".)
}
