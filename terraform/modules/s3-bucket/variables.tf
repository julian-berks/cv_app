variable "name" {
  description = "Bucket name."
  type        = string
}

variable "versioning" {
  description = "Enable object versioning."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Optional lifecycle rules (e.g. expire raw payloads for housekeeping)."
  type = list(object({
    id                         = string
    enabled                    = optional(bool, true)
    prefix                     = optional(string, "")
    expiration_days            = optional(number)
    noncurrent_expiration_days = optional(number)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
