# CloudFront distribution for the WordPress site
resource "aws_cloudfront_distribution" "main" {
  # Provider for us-east-1
  provider = aws.us-east-1

  # This distribution is managed by Terraform

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "BinarySoftwear CDN Distribution"
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

  # lifecycle block removed to ensure Terraform has full control.
}