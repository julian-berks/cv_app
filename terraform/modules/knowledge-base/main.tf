data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


resource "aws_bedrockagent_knowledge_base" "kb" {
  name     = var.knowledge_base_name
  role_arn = aws_iam_role.kbrole.arn

  knowledge_base_configuration {
    type = "MANAGED"

    managed_knowledge_base_configuration {
      embedding_model_type = "MANAGED"
    }
  }
}




data "aws_iam_policy_document" "knowledgebase_access" {

  statement {
            sid =  "CloudWatchWritePermissionStatement"
            effect = "Allow"
            actions = [
                "cloudwatch:PutMetricData"
            ]
            resources =  ["*"]
            condition   {
                test = "StringEquals"
                variable = "cloudwatch:namespace"
                values = ["AWS/Bedrock/KnowledgeBases"]
            }
        }

    statement {
            sid =  "S3ListBucketStatement"
            effect = "Allow"
            actions = [
                "s3:ListBucket"
            ]
            resources =  ["arn:aws:s3:::${var.rag_bucket_name}"]
            condition   {
                test = "StringEquals"
                variable = "aws:ResourceAccount"
                values = [data.aws_caller_identity.current.account_id]
            }
        }

            statement {
            sid =  "S3GetObjectStatement"
            effect = "Allow"
            actions = [
                "s3:GetObject"
            ]
            resources =  ["arn:aws:s3:::${var.rag_bucket_name}/${var.filepath}"]
            condition   {
                test = "StringEquals"
                variable = "aws:ResourceAccount"
                values = [data.aws_caller_identity.current.account_id]
            }
        }
}

data "aws_iam_policy_document" "knowledgebaseassume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
                test = "StringEquals"
                variable = "aws:SourceAccount"
                values = [data.aws_caller_identity.current.account_id]
              }
    condition {
                test = "ArnLike"
                variable = "aws:SourceArn"
                values = ["arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
              }
  }
}


resource "aws_iam_role" "kbrole" {
  name               = "${var.knowledge_base_name}_role"
  assume_role_policy = data.aws_iam_policy_document.knowledgebaseassume.json    
}
 
resource "aws_iam_role_policy" "access" {
  name   = "${var.knowledge_base_name}-access"
  role   = aws_iam_role.kbrole.id
  policy = data.aws_iam_policy_document.knowledgebase_access.json
}




resource "aws_bedrockagent_data_source" "s3datasource" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "${var.knowledge_base_name}-s3-managed"

  data_source_configuration {
    type = "MANAGED_KNOWLEDGE_BASE_CONNECTOR"

    managed_knowledge_base_connector_configuration {
      connector_parameters = jsonencode({
        type    = "S3"
        version = "1"
        connectionConfiguration = {
          bucketName           = var.rag_bucket_name
          bucketOwnerAccountId = data.aws_caller_identity.current.account_id
        }
        aclEnabled = false
        filterConfiguration = {
          maxFileSizeInMegaBytes = "500"
        }
      })

      media_extraction_configuration {
        image_extraction_configuration {
          image_extraction_status = "DISABLED"
        }
      }
    }
  }

  vector_ingestion_configuration {
    parsing_configuration {
      parsing_strategy = "SMART_PARSING"
    }
  }
}





