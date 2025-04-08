# Reference existing hosted zone for the domain
data "aws_route53_zone" "main" {
  name         = "binarysoftwear.com"
  private_zone = false
}

# Alias record to ALB (bypassing CloudFront for troubleshooting)
resource "aws_route53_record" "root_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false # Cannot evaluate ALB health directly in Route 53 alias
  }
}

# WWW alias record to ALB (bypassing CloudFront for troubleshooting)
resource "aws_route53_record" "www_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false # Cannot evaluate ALB health directly in Route 53 alias
  }
}
