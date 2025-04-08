# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name   = "binarysoftwear-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Security Group
resource "aws_security_group" "ec2_sg" {
  name   = "binarysoftwear-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Removed incorrect rule allowing HTTPS from ALB (ALB sends HTTP to instances)

  ingress {
    description     = "SSH access from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # NFS for EFS
  ingress {
    description = "NFS from EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "binarysoftwear-ec2-sg" }
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name   = "binarysoftwear-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2 SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "binarysoftwear-rds-sg" }
}

# EFS Security Group
resource "aws_security_group" "efs_sg" {
  name   = "binarysoftwear-efs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "NFS from EC2 SG"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] # Allow from EC2 instances
  }

  # Egress can be restrictive if needed, but default allow all is often fine
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "binarysoftwear-efs-sg" }
}

# Regional WAFv2 Web ACL for ALB
resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "binarysoftwear-waf"
  scope       = "REGIONAL"
  description = "WAF rules for ALB protection"
  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 1
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    override_action {
      none {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "commonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "binarysoftwear-waf"
    sampled_requests_enabled   = true
  }
}

# Global WAFv2 Web ACL for CloudFront
resource "aws_wafv2_web_acl" "cloudfront_waf_acl" {
  name        = "binarysoftwear-cloudfront-waf"
  scope       = "CLOUDFRONT"
  description = "WAF rules for CloudFront protection"
  provider    = aws.us-east-1 # Ensure this is using the us-east-1 region provider

  default_action {
    allow {}
  }
  
  # WordPress Admin Exclusion Rule - Allow rule for wp-admin/post.php requests
  rule {
    name     = "WordPressAdminExclusionRule"
    priority = 0  # Lower priority to run before other rules
    
    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/wp-admin"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        
        statement {
          byte_match_statement {
            search_string         = "post.php"
            positional_constraint = "CONTAINS"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    
    action {
      allow {}
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "WordPressAdminExclusionRule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 1
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    override_action {
      none {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CFCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Add additional rules for CloudFront-specific protection
  rule {
    name     = "RateLimitRule"
    priority = 2
    statement {
      rate_based_statement {
        limit              = 3000 # Requests per 5 minutes
        aggregate_key_type = "IP"
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "binarysoftwear-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

# WAF association is defined in alb_cloudfront.tf
