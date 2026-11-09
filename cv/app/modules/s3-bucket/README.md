# module: s3-bucket

Reusable S3 bucket module (BUILT): versioning, AES256 SSE, optional lifecycle rules.

Inputs: `name`, `versioning`, `force_destroy`, `lifecycle_rules`
(`id`/`enabled`/`prefix`/`expiration_days`/`noncurrent_expiration_days`), `tags`.
Outputs: `bucket_id`, `bucket_arn`, `bucket_domain_name`.

NOTE: Does NOT create an `aws_s3_bucket_public_access_block` — public access is
blocked ACCOUNT-WIDE by an Organizations SCP that denies
`s3:PutBucketPublicAccessBlock`. Used for: payload storage (lifecycle expiry ~395d
for housekeeping) and frontend static assets.
