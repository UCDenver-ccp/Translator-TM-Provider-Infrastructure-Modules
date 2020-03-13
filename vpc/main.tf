# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A CPU IN GOOGLE CLOUD PLATFORM
# ---------------------------------------------------------------------------------------------------------------------


terraform {

  # Partial configuration for the backend: https://www.terraform.io/docs/backends/config.html#partial-configuration
  # In this case, the backend configuration will be filled in by Terragrunt
  backend "gcs" {}

  # Only allow this Terraform version. Note that if you upgrade to a newer version, Terraform won't allow you to use an
  # older version, so when you upgrade, you should upgrade everyone on your team and your CI servers all at once.
  required_version = ">= 0.12.19"

  required_providers {
    google = "~> 2.20.2"
  }
}


module "vpc_network" {
  source = "github.com/gruntwork-io/terraform-google-network.git//modules/vpc-network?ref=v0.2.9"

  name_prefix = "${var.cluster_name}-network-${random_string.suffix.result}"
  project     = var.project
  region      = var.region

  cidr_block           = var.vpc_cidr_block
  secondary_cidr_block = var.vpc_secondary_cidr_block

  enable_flow_logging = false
}

# Use a random suffix to prevent overlap in network names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}



