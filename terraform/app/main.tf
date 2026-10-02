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
				"arn:aws:bedrock:eu-west-2::foundation-model/amazon.nova-micro-v1:0",
				"arn:aws:bedrock:eu-west-2:594542138399:knowledge-base/WVOCVIUTT0"
			]
  create_function_url                 = true
  #create_lambda_sg_group = true
  #vpc_id                 = var.vpc_id
  #vpc_cidr_block         = var.vpc_cidr_block
  #subnet_ids             = var.subnet_ids

  enable_dynamodb_access = true
  #dynamodb_table_arns = concat(
   # var.controls_table_arns,
    #[var.current_status_table_arn, var.history_table_arn],
  #)
  enable_s3_lambda_access = false
  #s3_bucket_name_list     = [var.payloads_bucket_name]

  environment = {}

  tags       = var.tags
  dependency = "dummy"

  # Ensure the dummy :latest image is pushed before the function is created
  # (image_uri does not reference it, so an explicit dependency is required).
  #depends_on = [module.dummy_image]
}
