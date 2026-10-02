# Reusable container-image Lambda module for HEARTBEAT.
# Terraform owns the infra; CI owns image rollouts -> lifecycle ignores image_uri.

locals {
  function_name = "${var.name}-lambda-function"
  in_vpc        = length(var.subnet_ids) > 0
  _             = var.dependency # keep dependency in the graph
}

# ---- IAM execution role ------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = merge(var.tags, { Name = var.iam_role_name })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc" {
  count      = local.in_vpc ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---- Least-privilege inline policy ------------------------------------------
data "aws_iam_policy_document" "access" {
  dynamic "statement" {
    for_each = length(var.dynamodb_table_arns) > 0 ? [1] : []
    content {
      sid    = "DynamoDBAccess"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:BatchWriteItem",
      ]
      resources = var.dynamodb_table_arns
    }
  }

dynamic "statement" {
    for_each = length(var.bedrock_resources) > 0 ? [1] : []
    content {
      sid       = "BedrockAccess"
      effect    = "Allow"
      actions   = ["bedrock:Retrieve", "bedrock:InvokeModel"]
      resources = var.bedrock_resources
    }
  }

  dynamic "statement" {
    for_each = var.enable_s3_lambda_access ? [1] : []
    content {
      sid       = "S3ObjectAccess"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = [for b in var.s3_bucket_name_list : "arn:aws:s3:::${b}/*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_s3_lambda_access ? [1] : []
    content {
      sid       = "S3BucketList"
      effect    = "Allow"
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = [for b in var.s3_bucket_name_list : "arn:aws:s3:::${b}"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_secrets_manager_access ? [1] : []
    content {
      sid       = "SecretsManagerRead"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = var.secrets_manager_secret_arns
    }
  }

  dynamic "statement" {
    for_each = var.enable_kms_access ? [1] : []
    content {
      sid       = "KMSAccess"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      resources = length(var.kms_key_arns) > 0 ? var.kms_key_arns : ["*"]
    }
  }
}

locals {
  has_inline = length(var.dynamodb_table_arns) > 0 || length(var.bedrock_resources) > 0 || var.enable_s3_lambda_access || var.enable_secrets_manager_access || var.enable_kms_access
}

resource "aws_iam_role_policy" "access" {
  count  = local.has_inline ? 1 : 0
  name   = "${var.name}-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.access.json
}

resource "aws_iam_role_policy" "additional" {
  count  = var.additional_policy_json == "" ? 0 : 1
  name   = "${var.name}-additional"
  role   = aws_iam_role.this.id
  policy = var.additional_policy_json
}

# ---- Security group (VPC mode) ----------------------------------------------
resource "aws_security_group" "this" {
  count       = var.create_lambda_sg_group ? 1 : 0
  name        = "${var.name}-lambda-sg"
  description = "Security group for ${local.function_name}."
  vpc_id      = var.vpc_id

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-lambda-sg" })
}

# ---- Logs --------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_in_days
  tags              = merge(var.tags, { Name = "/aws/lambda/${local.function_name}" })
}

# ---- Function ----------------------------------------------------------------
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.this.arn
  package_type  = var.package_type
  image_uri     = var.image_uri
  timeout       = var.timeout
  memory_size   = var.memory_size

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [1] : []
    content {
      variables = var.environment
    }
  }

  dynamic "vpc_config" {
    for_each = local.in_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = concat(var.create_lambda_sg_group ? [aws_security_group.this[0].id] : [], var.additional_security_group_ids)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_cloudwatch_log_group.this,
  ]

  lifecycle {
    ignore_changes = [image_uri]
  }

  tags = merge(var.tags, { Name = local.function_name })
}


resource "aws_lambda_function_url" "example" {
  count = var.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}
