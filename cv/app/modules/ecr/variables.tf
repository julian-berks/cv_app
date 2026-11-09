variable "name" {
  description = "ECR repository name (typically <common_name>)."
  type        = string
}

variable "enable_private_ecr" {
  description = "Reserved flag for parity with the provisioning repo (private ECR is always used)."
  type        = bool
  default     = true
}

variable "scan_on_push" {
  description = "Enable image scanning on push (security)."
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Image tag mutability."
  type        = string
  default     = "MUTABLE"
}

variable "max_image_count" {
  description = "Lifecycle policy: keep only the most recent N images."
  type        = number
  default     = 7
}

variable "force_delete" {
  description = "Allow deleting the repo even if it contains images."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
