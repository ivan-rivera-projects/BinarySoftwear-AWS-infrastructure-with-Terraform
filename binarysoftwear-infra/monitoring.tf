###############################################
# CloudWatch Alarms for ALB Health Monitoring
###############################################

# Alarm for unhealthy targets in the target group
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts_alarm" {
  alarm_name          = "binarysoftwear-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This alarm monitors for unhealthy hosts in the BinarySoftwear target group"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }
  
  # Optional: Configure SNS notification here
  # alarm_actions     = [aws_sns_topic.alerts.arn]
  # ok_actions        = [aws_sns_topic.alerts.arn]
}

# Alarm for high 5XX error rate
resource "aws_cloudwatch_metric_alarm" "http_5xx_errors" {
  alarm_name          = "binarysoftwear-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This alarm monitors for HTTP 5XX errors from the BinarySoftwear targets"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }
  
  # Optional: Configure SNS notification here
  # alarm_actions     = [aws_sns_topic.alerts.arn]
  # ok_actions        = [aws_sns_topic.alerts.arn]
}

# Alarm for high 4XX error rate
resource "aws_cloudwatch_metric_alarm" "http_4xx_errors" {
  alarm_name          = "binarysoftwear-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "This alarm monitors for excessive HTTP 4XX errors from the BinarySoftwear targets"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }
  
  # Optional: Configure SNS notification here
  # alarm_actions     = [aws_sns_topic.alerts.arn]
  # ok_actions        = [aws_sns_topic.alerts.arn]
}

# Dashboard for BinarySoftwear monitoring
resource "aws_cloudwatch_dashboard" "binarysoftwear" {
  dashboard_name = "BinarySoftwear-Monitoring"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Maximum"
          region = var.aws_region
          title  = "ALB Target Health"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_3XX_Count", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "HTTP Status Codes"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "binarysoftwear-asg"]
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Request Count"
        }
      }
    ]
  })
}
