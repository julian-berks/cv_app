output "acm_dns_validation_records" {
  description = "Create these DNS records externally to validate the ACM certificate."
  value = [
    for option in aws_acm_certificate.cv.domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ] 
}

output "cloudfront_domain_name" {
  description = "CloudFront hostname to point the application domain at in external DNS."
  value       =  aws_cloudfront_distribution.cv.domain_name
}


