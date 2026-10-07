data "aws_region" "current" {}

module "ecr" {
  source          = "../modules/ecr"
  name            = "${var.name}"
  scan_on_push    = true
  max_image_count = 7
 tags            = var.tags
}

#module "dummy_image" {
#  source              = "../../../../modules/ecr-dummy-image"
#  ecr_repository_url  = module.ecr.repository_url
#  ecr_repository_name = module.ecr.repository_name
#  ecr_image_tag       = var.image_tag
#  region              = var.region
#  dependency          = module.ecr.repository_arn
#}


module "function" {
  count = var.container_deployed?1:0
  source                            = "../modules/lambda"
  name                              = "${var.name}"
  image_uri                         = "${module.ecr.repository_url}:latest"
  iam_role_name                     = "${var.name}-default_role"
  timeout                           = 30
  memory_size                       = 512
  cloudwatch_logs_retention_in_days = 7
  bedrock_resources                  = [
				"arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/${var.model_id}",
				"arn:aws:bedrock:${data.aws_region.current.region}:594542138399:knowledge-base/${module.knowledge_base.knowledge_base_id}"
			]

  environment = {
    KNOWLEDGE_BASE_ID       = module.knowledge_base.knowledge_base_id
    MODEL_ID                = var.model_id
  }
  create_function_url                 = true
  #create_lambda_sg_group = true
  #vpc_id                 = var.vpc_id
  #vpc_cidr_block         = var.vpc_cidr_block
  #subnet_ids             = var.subnet_ids

  #enable_dynamodb_access = true
  #dynamodb_table_arns = concat(
   # var.controls_table_arns,
    #[var.current_status_table_arn, var.history_table_arn],
  #)
  enable_s3_lambda_access = false


  tags       = var.tags
  dependency = "dummy"


}

  module "knowledge_base" {
    source = "../modules/knowledge-base"
    knowledge_base_name = "${var.name}_kb"
    rag_bucket_name     = "594542138399-rag-bucket"
    filepath            = "*"
  }



