output "knowledge_base_id" {
  description = "Knowledge base ID."
  value       = aws_bedrockagent_knowledge_base.kb.id
}


output "data_source_id" {
  description = "Data source ID."
  value       = aws_bedrockagent_data_source.s3datasource.data_source_id
} 