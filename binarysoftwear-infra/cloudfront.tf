# CloudFront distribution for the WordPress site - Imported from W3 Total Cache
resource "aws_cloudfront_distribution" "main" {
  # Provider for us-east-1
  provider = aws.us-east-1

  # This distribution is managed both by Terraform and W3 Total Cache
  # Be careful when making changes - W3TC may make its own modifications

  enabled             = true # Enable the distribution
  is_ipv6_enabled     = true
  comment             = "Created by W3-Total-Cache"
  default_root_object = "index.php"
  price_class         = "PriceClass_100"
  aliases             = [var.domain_name, "www.${var.domain_name}"]

  # Origin configuration - pointing to the ALB
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "binarysoftwear-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only" # Ensure CloudFront connects via HTTPS
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
      origin_keepalive_timeout = 5
    }

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
    
    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }
    
    custom_header {
      name  = "X-Forwarded-For"
      value = "*"
    }
  }

  # Default cache behavior - for most WordPress content
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "binarysoftwear-alb-origin"

    # Forward all cookies and query strings for default WordPress operation
    forwarded_values {
      query_string = true
      headers      = ["*"] # Forward all headers to solve compatibility issues

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0 # Don't cache dynamic content by default
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for static assets
  dynamic "ordered_cache_behavior" {
    for_each = [
      "wp-content/uploads/*", "*.css", "*.js", "*.jpg", "*.jpeg", "*.png", 
      "*.gif", "*.svg", "*.woff", "*.woff2", "*.ttf"
    ]
    
    content {
      path_pattern     = ordered_cache_behavior.value
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "binarysoftwear-alb-origin"

      forwarded_values {
        query_string = false
        headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]

        cookies {
          forward = "none"
        }
      }

      min_ttl                = 86400    # 1 day
      default_ttl            = 604800   # 1 week
      max_ttl                = 31536000 # 1 year
      compress               = true
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  # Special WP admin cache behaviors
  dynamic "ordered_cache_behavior" {
    for_each = ["wp-admin/post.php*", "wp-admin/*", "wp-login.php*"]
    
    content {
      path_pattern     = ordered_cache_behavior.value
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "binarysoftwear-alb-origin"

      forwarded_values {
        query_string = true
        headers      = ["*"]

        cookies {
          forward = "all"
        }
      }

      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
      compress               = true
      viewer_protocol_policy = "redirect-to-https"
    }
  }

  # Custom error pages
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 403
    response_page_path = "/403.html"
  }

  # Restrictions - no geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS certificate
  viewer_certificate {
    acm_certificate_arn      = var.alb_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  
  # WAF integration
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf_acl.arn

  # Define external ID for the resource - this must match the W3TC created distribution ID
  # When used with 'terraform import', this ensures Terraform manages the existing resource
  # without trying to create a new one or delete the existing one.
  # lifecycle { # Temporarily commented out to allow enabling the distribution
  #   ignore_changes = [
  #     # W3TC may make changes to these attributes, so we should ignore them
  #     default_cache_behavior,
  #     ordered_cache_behavior,
  #     origin,
  #     aliases,
  #     comment
  #   ]
  # }
}