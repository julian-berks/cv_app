output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Lambda invoke ARN."
  value       = aws_lambda_function.this.invoke_arn
}

output "function_url" {
  description = "Lambda function URL, when enabled."
  value       = try(aws_lambda_function_url.example[0].function_url, null)
}

output "role_arn" {
  description = "Execution role ARN."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Execution role name."
  value       = aws_iam_role.this.name
}

output "security_group_id" {
  description = "Security group id (null when not created)."
  value       = var.create_lambda_sg_group ? aws_security_group.this[0].id : null
}
