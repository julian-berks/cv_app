output "acm_dns_validation_records" {
  description = "Create these DNS records externally to validate the ACM certificate."
  value = var.container_deployed ? [
    for option in aws_acm_certificate.cv[0].domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ] : []
}

output "cloudfront_domain_name" {
  description = "CloudFront hostname to point the application domain at in external DNS."
  value       = var.container_deployed ? aws_cloudfront_distribution.cv[0].domain_name : null
}