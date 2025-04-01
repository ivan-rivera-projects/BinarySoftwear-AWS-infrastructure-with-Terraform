resource "aws_lb" "main" {
  name               = "binarysoftwear-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  ip_address_type    = "ipv4"

  tags = {
    Name = "binarysoftwear-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# HTTPS listener for secure connections
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Path pattern rule for wp-admin access - attached to HTTPS listener
resource "aws_lb_listener_rule" "wp_admin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    path_pattern {
      values = ["/wp-admin*", "/wp-login.php*"]
    }
  }
}

resource "aws_lb_target_group" "main" {
  name     = "binarysoftwear-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Add sticky session configuration
  stickiness {
    type            = "app_cookie"
    cookie_name     = "PHPSESSID"
    enabled         = true
    cookie_duration = 86400
  }

  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    unhealthy_threshold = 3
    healthy_threshold   = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-499"
  }
  tags = {
    Name = "binarysoftwear-tg"
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "waf_assoc" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.waf_acl.arn
}

# CloudFront distribution temporarily removed
# See cloudfront.tf.bak for the original configuration
