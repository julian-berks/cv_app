variable "knowledge_base_name" {
  type        = string
  description = "Name of the knowledge base"
}

variable "rag_bucket_name" {
  type        = string
  description = "Name of the RAG S3 bucket"
}


variable "filepath" {
  type        = string
  description = "File path within the RAG S3 bucket"
  default = "*"
}