# module: lambda

Reusable container-image (`package_type = "Image"`) Lambda module (BUILT).
`lifecycle { ignore_changes = [image_uri] }` — Terraform owns infra, CI owns image
rollouts via `aws lambda update-function-code`.

Inputs: `name`, `image_uri`, `timeout`, `memory_size`, `reserved_concurrent_executions`, `environment`,
`cloudwatch_logs_retention_in_days`, `iam_role_name`; VPC:
`create_lambda_sg_group`, `vpc_id`, `vpc_cidr_block`, `subnet_ids`,
`additional_security_group_ids`; least-privilege flags:
`enable_dynamodb_access`+`dynamodb_table_arns`+`dynamodb_actions`, `enable_s3_lambda_access`+
`s3_bucket_name_list`, `enable_secrets_manager_access`+`secrets_manager_secret_arns`,
`enable_kms_access`+`kms_key_arns`, `additional_policy_json`; `tags`, `dependency`.
Outputs: `function_name`, `function_arn`, `invoke_arn`, `role_arn`, `role_name`,
`security_group_id`.
