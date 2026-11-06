data "aws_region" "current" {}

module "ecr" {
  source          = "../modules/ecr"
  name            = "${var.name}"
  scan_on_push    = true
  max_image_count = 7
 tags            = var.tags
}


# Compute MD5 hash of all files in the Container folder to trigger rebuilds when any file changes
locals {
  docs_folder = "../../rag_data"
  rag_bucket_name = "594542138399-rag-bucket"

  app_folder = "../../Container"
  files  = sort(fileset(local.app_folder, "**"))
  app_md5 = md5(join("", [
    for f in local.files : filemd5("${local.app_folder}/${f}")
  ]))

  # Compute MD5 hash of all files in the docs folder to trigger KB resync when any file changes
  docs_hash = md5(join("", [
    for f in sort(fileset(local.docs_folder, "**")) :
    "${f}:${filemd5("${local.docs_folder}/${f}")}"
  ]))
}


resource "terraform_data" "build_and_push_image" {
  depends_on       = [module.ecr]
  triggers_replace = local.app_md5

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      cd ${local.app_folder}
      ./push ${module.ecr.repository_url}
    EOT
  }
}

module "function" {
  depends_on = [terraform_data.build_and_push_image]
  source                            = "../modules/lambda"
  name                              = "${var.name}"
  image_uri                         = "${module.ecr.repository_url}:latest"
  iam_role_name                     = "${var.name}-default_role"
  timeout                           = 30
  memory_size                       = 512
  reserved_concurrent_executions    = var.lambda_reserved_concurrency
  cloudwatch_logs_retention_in_days = 7
  bedrock_resources                  = [
				"arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/${var.model_id}",
				"arn:aws:bedrock:${data.aws_region.current.region}:594542138399:knowledge-base/${module.knowledge_base.knowledge_base_id}",
				aws_bedrock_guardrail.cv.guardrail_arn
			]

  environment = {
    KNOWLEDGE_BASE_ID       = module.knowledge_base.knowledge_base_id
    MODEL_ID                = var.model_id
    GUARDRAIL_ID            = aws_bedrock_guardrail.cv.guardrail_id
    GUARDRAIL_VERSION       = aws_bedrock_guardrail_version.cv.version
    DYNAMODB_TABLE          = aws_dynamodb_table.questions.name
    RETENTION_DAYS          = tostring(var.question_retention_days)
    ALLOWED_ORIGIN          = "https://${var.domain_name}"
    RATE_LIMIT_TABLE        = aws_dynamodb_table.rate_limits.name
    RATE_LIMIT_PER_MINUTE   = tostring(var.ask_rate_limit_per_minute)
  }
  create_function_url                 = true

  dynamodb_table_arns = [aws_dynamodb_table.questions.arn, aws_dynamodb_table.rate_limits.arn]
  dynamodb_actions    = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
  enable_s3_lambda_access = false


  tags       = var.tags
  dependency = "dummy"
}


# Create RAG 
module "rag_bucket" {
  source = "../modules/s3-bucket"
  name = local.rag_bucket_name
  tags = var.tags
}   

resource "aws_s3_object" "docs" {
  depends_on = [module.rag_bucket]
  for_each = fileset(local.docs_folder, "**")

  bucket = module.rag_bucket.bucket_id
  key    = each.value
  source = "${local.docs_folder}/${each.value}"
  etag   = filemd5("${local.docs_folder}/${each.value}")
}

  module "knowledge_base" {
    depends_on = [module.rag_bucket]
    source = "../modules/knowledge-base"
    knowledge_base_name = "${var.name}_kb"
    rag_bucket_name     = local.rag_bucket_name
    filepath            = "*"
  }



resource "terraform_data" "kb_sync" {
  depends_on = [aws_s3_object.docs]
  triggers_replace = local.docs_hash

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent start-ingestion-job \
        --knowledge-base-id ${module.knowledge_base.knowledge_base_id} \
        --data-source-id ${module.knowledge_base.data_source_id} \
        --region ${var.region}
    EOT
  }

}