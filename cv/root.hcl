# ------------------------------------------------------------------------------------------
# This is the root configuration for all infrastructure
#
#  - Generate a provider block for AWS
#  - Generate a state block for s3
#  - Define any global input values that may be needed
#  
#  Every terragrunt module should call this file
# ------------------------------------------------------------------------------------------
 
# ------------------------------------------------------------------------------------------
# Load common values
# ------------------------------------------------------------------------------------------
locals {
  common_vars     = read_terragrunt_config("./common.hcl")
 
  account_id   = "594542138399"
  common_tags = jsonencode(local.common_vars.locals.common_tags)
  folder_name = basename(get_terragrunt_dir())
  project_name = "julian-cv"
 
}
 
# ------------------------------------------------------------------------------------------
#  Generate Provider Block
# ------------------------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
 
  provider "aws" {
  region    = "eu-west-2"
  default_tags {
    tags = ${local.common_tags}
  }
  }
 

  terraform {
  required_version = ">= 1.16.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.00.0"
    }
  }
  }
 
EOF
}
 
# ------------------------------------------------------------------------------------------
#  Generate Remote State Block
# ------------------------------------------------------------------------------------------
remote_state {
  #disable_init = true
  backend = "s3"
  config = {
    bucket         = "${local.account_id}-tfstate"
    use_lockfile   = true
    encrypt        = true
    region         = "eu-west-2"
    key            = "${local.project_name}/terraform.tfstate"
  }
  generate = {
    path      = "remote_state.tf"
    if_exists = "overwrite_terragrunt"
  }
}