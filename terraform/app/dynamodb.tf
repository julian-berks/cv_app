resource "aws_dynamodb_table" "questions" {
  name         = "${var.name}-questions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  tags         = var.tags

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "rate_limits" {
  name         = "${var.name}-rate-limits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "bucket"
  tags         = var.tags

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  attribute {
    name = "bucket"
    type = "S"
  }
}
