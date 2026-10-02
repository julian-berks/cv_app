# module: ecr

Private ECR repository (BUILT). Creates `<name>-ecr` with AES256 encryption,
scan-on-push, and a lifecycle policy keeping the last N images.

Inputs: `name`, `scan_on_push`, `image_tag_mutability`, `max_image_count`,
`force_delete`, `tags`.
Outputs: `repository_url`, `repository_name`, `repository_arn`.
