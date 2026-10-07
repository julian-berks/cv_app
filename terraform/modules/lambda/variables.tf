variable "name" {
  description = "Base name; the function is <name>-lambda-function."
  type        = string
}

variable "image_uri" {
  description = "ECR image URI (repo_url:tag). Terraform provisions against this; CI updates code out-of-band."
  type        = string
}

variable "package_type" {
  description = "Lambda package type."
  type        = string
  default     = "Image"
}

variable "timeout" {
  description = "Function timeout (seconds)."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Function memory (MB)."
  type        = number
  default     = 512
}

variable "environment" {
  description = "Environment variables passed to the function."
  type        = map(string)
  default     = {}
}

variable "cloudwatch_logs_retention_in_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 7
}

variable "iam_role_name" {
  description = "Name for the function's IAM execution role."
  type        = string
}

# ---- VPC ---------------------------------------------------------------------
variable "create_lambda_sg_group" {
  description = "Create a dedicated security group for the function (VPC mode)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC id (required when create_lambda_sg_group)."
  type        = string
  default     = null
}

variable "vpc_cidr_block" {
  description = "VPC CIDR used for the SG egress/ingress rules."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnet ids for the function's VPC config. Empty = no VPC."
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Extra security group ids to attach in VPC mode."
  type        = list(string)
  default     = []
}

# ---- Least-privilege feature flags ------------------------------------------
variable "enable_dynamodb_access" {
  description = "Grant scoped DynamoDB access."
  type        = bool
  default     = false
}

variable "dynamodb_table_arns" {
  description = "DynamoDB table (and index) ARNs to scope access to."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "dynamodb_actions" {
  description = "DynamoDB actions allowed on dynamodb_table_arns."
  type        = list(string)
  default = [
    "dynamodb:GetItem",
    "dynamodb:BatchGetItem",
    "dynamodb:Query",
    "dynamodb:Scan",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:BatchWriteItem",
  ]
  nullable = false
}

variable "enable_s3_lambda_access" {
  description = "Grant scoped S3 object access."
  type        = bool
  default     = false
}

variable "s3_bucket_name_list" {
  description = "S3 bucket names to scope object access to."
  type        = list(string)
  default     = []
}

variable "enable_secrets_manager_access" {
  description = "Grant scoped Secrets Manager read access."
  type        = bool
  default     = false
}

variable "secrets_manager_secret_arns" {
  description = "Secret ARNs to scope access to."
  type        = list(string)
  default     = []
}

variable "enable_kms_access" {
  description = "Grant KMS decrypt/encrypt/generate-data-key."
  type        = bool
  default     = false
}

variable "kms_key_arns" {
  description = "KMS key ARNs to scope access to (empty = *)."
  type        = list(string)
  default     = []
}

variable "additional_policy_json" {
  description = "Optional extra IAM policy document (JSON) attached to the role."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}

variable "dependency" {
  description = "Arbitrary value to force ordering (e.g. dummy image seed)."
  type        = any
  default     = null
}


variable "bedrock_resources" {
  description = "List of Bedrock resources to scope access to."
  type        = list(string)
  default     = []
  nullable    = false
}


variable "create_function_url" {
  description = "Whether to create a Lambda function URL."
  type        = bool
  default     = false
}

variable "reserved_concurrent_executions" {
  description = "Maximum concurrent executions for the function. -1 means no limit."
  type        = number
  default     = -1
}