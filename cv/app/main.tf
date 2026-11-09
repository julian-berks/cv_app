data "aws_region" "current" {}

locals {
  docs_folder     = "./rag_data"
  rag_bucket_name = var.rag_bucket_name

  app_folder = "./Container"
  app_digest = sha256(join("\n", [
    for f in sort(fileset(local.app_folder, "**")) :
    "${f}:${filesha256("${local.app_folder}/${f}")}"
  ]))
  image_tag = "sha-${local.app_digest}"

  # Include only supported source documents in the Knowledge Base.
  docs_files = sort([
    for f in fileset(local.docs_folder, "**") : f
    if can(regex("(?i)\\.(doc|docx|txt)$", f))
    && !can(regex("(^|/)\\.terraform(/|$)", f))
  ])

  # Hash document paths and contents to trigger uploads and Knowledge Base ingestion.
  docs_hash = md5(join("", [
    for f in local.docs_files :
    "${f}:${filemd5("${local.docs_folder}/${f}")}"
  ]))
}


module "ecr" {
  source               = "./modules/ecr"
  name                 = var.name
  scan_on_push         = true
  image_tag_mutability = "IMMUTABLE"
  max_image_count      = 7
  tags                 = var.tags
}

resource "terraform_data" "build_and_push_image" {
  depends_on       = [module.ecr]
  triggers_replace = local.app_digest

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      cd ${local.app_folder}
      ./push ${module.ecr.repository_url} ${local.image_tag}
    EOT
  }
}

module "function" {
  depends_on                        = [terraform_data.build_and_push_image]
  source                            = "./modules/lambda"
  name                              = var.name
  image_uri                         = "${module.ecr.repository_url}:${local.image_tag}"
  iam_role_name                     = "${var.name}-default_role"
  timeout                           = 30
  memory_size                       = 512
  reserved_concurrent_executions    = var.lambda_reserved_concurrency
  cloudwatch_logs_retention_in_days = 7
  bedrock_resources = [
    "arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/${var.model_id}",
    "arn:aws:bedrock:${data.aws_region.current.region}:594542138399:knowledge-base/${module.knowledge_base.knowledge_base_id}",
    aws_bedrock_guardrail.cv.guardrail_arn
  ]

  environment = {
    KNOWLEDGE_BASE_ID     = module.knowledge_base.knowledge_base_id
    MODEL_ID              = var.model_id
    GUARDRAIL_ID          = aws_bedrock_guardrail.cv.guardrail_id
    GUARDRAIL_VERSION     = aws_bedrock_guardrail_version.cv.version
    DYNAMODB_TABLE        = aws_dynamodb_table.questions.name
    RETENTION_DAYS        = tostring(var.question_retention_days)
    ALLOWED_ORIGIN        = "https://${var.domain_name}"
    RATE_LIMIT_TABLE      = aws_dynamodb_table.rate_limits.name
    RATE_LIMIT_PER_MINUTE = tostring(var.ask_rate_limit_per_minute)
  }
  create_function_url = true

  dynamodb_table_arns     = [aws_dynamodb_table.questions.arn, aws_dynamodb_table.rate_limits.arn]
  dynamodb_actions        = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
  enable_s3_lambda_access = false


  tags       = var.tags
  dependency = "dummy"
}


# Create RAG 
module "rag_bucket" {
  source = "./modules/s3-bucket"
  name   = local.rag_bucket_name
  tags   = var.tags
}

resource "terraform_data" "docs_hash" {
  input = local.docs_hash
}

resource "aws_s3_object" "docs" {
  depends_on = [module.rag_bucket]
  for_each   = toset(local.docs_files)

  bucket = module.rag_bucket.bucket_id
  key    = each.value
  source = "${local.docs_folder}/${each.value}"
  etag   = filemd5("${local.docs_folder}/${each.value}")

  lifecycle {
    replace_triggered_by = [terraform_data.docs_hash]
  }
}

module "knowledge_base" {
  depends_on          = [module.rag_bucket]
  source              = "./modules/knowledge-base"
  knowledge_base_name = "${var.name}_kb"
  rag_bucket_name     = local.rag_bucket_name
  filepath            = "*"
}


resource "terraform_data" "kb_sync" {
  depends_on       = [aws_s3_object.docs]
  triggers_replace = [local.docs_hash, module.knowledge_base.knowledge_base_id, module.knowledge_base.data_source_id]

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent start-ingestion-job \
        --knowledge-base-id ${module.knowledge_base.knowledge_base_id} \
        --data-source-id ${module.knowledge_base.data_source_id} \
        --region ${data.aws_region.current.region}
    EOT
  }

}