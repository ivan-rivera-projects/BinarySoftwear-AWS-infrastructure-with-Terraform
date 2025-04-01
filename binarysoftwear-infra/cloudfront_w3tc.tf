# CloudFront distribution created by W3 Total Cache plugin and imported to Terraform
resource "aws_cloudfront_distribution" "w3tc_cdn" {
  # Distribution details
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Distribution managed by W3 Total Cache"
  price_class         = "PriceClass_100"  # Use only North America and Europe (cheapest option)
  
  # The CloudFront domain name
  # d1yi6dtz2qg5ym.cloudfront.net
  
  # Origin configuration
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "binarysoftwear-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "binarysoftwear-alb-origin"

    forwarded_values {
      query_string = false
      
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400    # 1 day
    max_ttl                = 31536000 # 1 year
    compress               = true
  }

  # Restrictions - no geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS certificate - using the CloudFront default certificate
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  # Lifecycle configuration to prevent Terraform from making changes
  # that could conflict with W3 Total Cache management
  lifecycle {
    ignore_changes = [
      # W3TC may make changes to these attributes, so we should ignore them
      default_cache_behavior,
      ordered_cache_behavior,
      origin,
      comment,
      custom_error_response,
      web_acl_id
    ]
  }

  # Add an output to track this resource
  depends_on = [aws_lb.main]
}

# Output the W3TC CloudFront Distribution details
output "w3tc_cloudfront_domain" {
  value       = aws_cloudfront_distribution.w3tc_cdn.domain_name
  description = "The domain name of the CloudFront distribution created by W3 Total Cache"
}

output "w3tc_cloudfront_id" {
  value       = aws_cloudfront_distribution.w3tc_cdn.id
  description = "The ID of the CloudFront distribution created by W3 Total Cache"
}
