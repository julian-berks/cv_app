variable "ecr_repository_url" {
  description = "Target ECR repository URL."
  type        = string
}

variable "ecr_repository_name" {
  description = "Target ECR repository name."
  type        = string
}

variable "ecr_image_tag" {
  description = "Tag to seed (typically 'latest')."
  type        = string
  default     = "latest"
}

variable "base_image" {
  description = "Public base image seeded as the dummy (a valid Lambda image so the function can be created before CI pushes real code)."
  type        = string
  default     = "public.ecr.aws/lambda/python:3.12"
}

variable "region" {
  description = "AWS region for ECR login."
  type        = string
  default     = "eu-west-1"
}

variable "dependency" {
  description = "Arbitrary value to force ordering after the ECR repo is created."
  type        = any
  default     = null
}
