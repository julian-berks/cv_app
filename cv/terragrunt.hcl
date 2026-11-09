# ------------------------------------------------------------------------------------------
# Set source terraform module
# ------------------------------------------------------------------------------------------

terraform {

  source = "./app"

}
 
 
# ------------------------------------------------------------------------------------------
# Run Default terragrunt (create providers and define remote state)
# ------------------------------------------------------------------------------------------
 
include "root" {
  path = "./root.hcl"
}


locals {
  common         = read_terragrunt_config("./common.hcl")
  common_tags    = local.common.locals.common_tags
}

inputs = {
    tags                    = local.common_tags
    name                    = "julian-cv"
    model_id                = "amazon.nova-micro-v1:0"
    domain_name             = "cv.julianberks.com"
    question_retention_days =  5
    rag_bucket_name         = "594542138399-rag-bucket"
    }