# Create IAM role for EC2 instances to access Secrets Manager
resource "aws_iam_role" "ec2_role" {
  name = "binarysoftwear-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Create policy for accessing Secrets Manager
resource "aws_iam_policy" "secrets_access" {
  name        = "binarysoftwear-secrets-access"
  description = "Allow access to RDS secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_secret.arn
      }
    ]
  })
}

# Create policy for EFS access
resource "aws_iam_policy" "efs_access" {
  name        = "binarysoftwear-efs-access"
  description = "Allow EC2 instances to access EFS and mount targets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeFileSystems",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "secrets_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "efs_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.efs_access.arn
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "binarysoftwear-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Launch template with external user data script
resource "aws_launch_template" "main" {
  name_prefix   = "binarysoftwear-lt-"
  image_id      = "ami-04aa00acb1165b32a" # Amazon Linux 2 AMI
  instance_type = var.ec2_instance_type
  key_name      = "MyVPC-KeyPair1"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # Use external file for user data to avoid Terraform syntax issues
  user_data = filebase64("${path.module}/scripts/ec2_user_data.sh")
}

resource "aws_autoscaling_group" "main" {
  name                = "binarysoftwear-asg"
  max_size            = 6
  min_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]

  # Use mixed instances policy instead of a single launch template
  mixed_instances_policy {
    # Define the base launch template
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.main.id
        version            = "$Latest"
      }

      # Configure the mix of instance types
      override {
        instance_type = var.ec2_instance_type
      }

      # Add alternative instance types for better spot availability
      dynamic "override" {
        for_each = var.ec2_instance_alternatives
        content {
          instance_type = override.value
        }
      }
    }

    # Set on-demand vs spot instance distribution
    instances_distribution {
      on_demand_base_capacity                  = 0                    # Use all spot instances
      on_demand_percentage_above_base_capacity = 0                    # Use spot instances for everything
      spot_allocation_strategy                 = "capacity-optimized" # Optimizes for availability
      spot_instance_pools                      = 0                    # When using capacity-optimized, set to 0
      spot_max_price                           = ""                   # Empty string means the on-demand price
    }
  }

  target_group_arns = [aws_lb_target_group.main.arn]

  # Instance refreshes automatically occur when the launch template changes
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Enable capacity rebalancing to proactively replace Spot Instances at risk of interruption
  capacity_rebalance = true

  # Enable group metrics collection
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity"
  ]

  tag {
    key                 = "Name"
    value               = "binarysoftwear-ec2"
    propagate_at_launch = true
  }

  # Default instance warmup for scaling policies
  default_instance_warmup = 300
}

# CloudWatch alarm for high CPU to trigger scale-out
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-utilization-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 85.0
  alarm_description   = "Scale out when CPU utilization is >= 85% for 5 consecutive minutes"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

# CloudWatch alarm for low CPU to trigger scale-in
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-utilization-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 20.0
  alarm_description   = "Scale in when CPU utilization is <= 20% for 5 consecutive minutes"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}

# Scale out policy - Add 1 instance when CPU is high
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

# Scale in policy - Remove 1 instance when CPU is low
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale-in-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}