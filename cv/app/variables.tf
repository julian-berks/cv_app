
variable "name" {
  type        = string
  description = "Name of the CV application"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to resources"
}

variable "model_id" {
  type        = string
  description = "ID of the model to use"
}

variable "domain_name" {
  type        = string
  description = "Domain name for the application"
}

variable "lambda_reserved_concurrency" {
  type        = number
  default     = 5
  description = "Maximum concurrent Lambda executions, which caps how many Bedrock calls can run at once. -1 removes the limit"

  validation {
    condition     = var.lambda_reserved_concurrency == -1 || var.lambda_reserved_concurrency >= 1
    error_message = "lambda_reserved_concurrency must be -1 (no limit) or at least 1."
  }
}

variable "ask_rate_limit_per_minute" {
  type        = number
  default     = 10
  description = "Maximum questions one IP address can ask per minute"

  validation {
    condition     = var.ask_rate_limit_per_minute >= 1
    error_message = "ask_rate_limit_per_minute must be at least 1."
  }
}

variable "waf_requests_per_5_minutes" {
  type        = number
  default     = 100
  description = "Maximum requests of any kind one IP address can make in 5 minutes before WAF blocks it (minimum 10)"

  validation {
    condition     = var.waf_requests_per_5_minutes >= 10
    error_message = "waf_requests_per_5_minutes must be at least 10, the WAF minimum."
  }
}

variable "question_retention_days" {
  type        = number
  description = "Days to keep recorded questions (and viewer IPs) before DynamoDB deletes them"

  validation {
    condition     = var.question_retention_days >= 1
    error_message = "question_retention_days must be at least 1."
  }
}


variable "base_filepath" {
  type        = string
  description = "Base filesystem path for the project"
}


variable "plan_tier" {
  type        = string
  default     = "FREE"
  description = "Plan tier for the CloudFront pricing plan"
}

variable "rag_bucket_name" {
  type        = string
  description = "Name of the RAG S3 bucket"
}