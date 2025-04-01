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

resource "aws_launch_template" "main" {
  name_prefix   = "binarysoftwear-lt-"
  image_id      = "ami-04aa00acb1165b32a" # Amazon Linux 2 AMI
  instance_type = var.ec2_instance_type
  key_name      = "MyVPC-KeyPair1"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
yum update -y
amazon-linux-extras enable php8.2
yum install -y httpd php php-mysqlnd php-json php-gd php-mbstring php-xml php-intl php-soap php-zip mariadb amazon-efs-utils jq aws-cli php-opcache php-apcu php-curl php-memcached

# Install ImageMagick and the PHP imagick extension
yum install -y ImageMagick ImageMagick-devel ghostscript
cd /tmp && pecl download imagick && tar -xf imagick-*.tgz && cd imagick-* && phpize && ./configure && make && make install
echo "extension=imagick.so" > /etc/php.d/20-imagick.ini

cat >/etc/php.d/10-opcache.ini<<EOT
[opcache]
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=2
opcache.fast_shutdown=1
EOT

cat >/etc/php.d/20-apcu.ini<<EOT
[apcu]
extension=apcu.so
apc.enabled=1
apc.shm_size=64M
apc.ttl=7200
apc.enable_cli=0
EOT

# Add specific WordPress PHP settings to increase limits
cat >/etc/php.d/30-wordpress.ini<<EOT
upload_max_filesize = 64M
post_max_size = 128M
max_execution_time = 300
max_input_vars = 3000
EOT

# Ensure mod_headers is enabled
echo "LoadModule headers_module modules/mod_headers.so" >> /etc/httpd/conf.modules.d/00-base.conf

# Add required headers in httpd conf
cat >/etc/httpd/conf.d/headers.conf<<EOT
<IfModule mod_headers.c>
   RequestHeader set X-Forwarded-Proto "https" env=HTTPS
   RequestHeader set X-Forwarded-SSL "on" env=HTTPS
</IfModule>
EOT

if ! php -m | grep -q apcu; then
  yum install -y php-pear php-devel gcc make
  pecl channel-update pecl.php.net
  printf "\n" | pecl install apcu
fi

systemctl enable httpd
systemctl start httpd

mkdir -p /var/www/html
yum install -y python3-pip
pip3 install boto3

AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=$(echo $AZ | sed 's/.$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SUBNET_ID=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].SubnetId" --output text)
VPC_ID=$(aws ec2 describe-subnets --region $REGION --subnet-ids $SUBNET_ID --query "Subnets[0].VpcId" --output text)

EFS_ID="${aws_efs_file_system.main.id}"
MT_IP=$(aws efs describe-mount-targets --region $REGION --file-system-id $EFS_ID --query "MountTargets[?SubnetId=='$SUBNET_ID'].IpAddress" --output text)

if [ -z "$MT_IP" ]; then
  SUBNET_AZ=$(aws ec2 describe-subnets --region $REGION --subnet-ids $SUBNET_ID --query "Subnets[0].AvailabilityZone" --output text)
  OTHER_SUBNETS=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$SUBNET_AZ" --query "Subnets[].SubnetId" --output text)
  
  for OTHER_SUBNET in $OTHER_SUBNETS; do
    MT_IP=$(aws efs describe-mount-targets --region $REGION --file-system-id $EFS_ID --query "MountTargets[?SubnetId=='$OTHER_SUBNET'].IpAddress" --output text)
    if [ ! -z "$MT_IP" ]; then break; fi
  done
fi

if [ ! -z "$MT_IP" ]; then
  mount -t nfs4 $MT_IP:/ /var/www/html
  echo "$MT_IP:/ /var/www/html nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
else
  mount -t efs -o tls $EFS_ID:/ /var/www/html
  echo "$EFS_ID:/ /var/www/html efs defaults,_netdev,tls 0 0" >> /etc/fstab
fi

cat >/etc/httpd/conf.d/wordpress.conf<<EOT
<VirtualHost *:80>
    ServerName binarysoftwear.com
    ServerAlias www.binarysoftwear.com
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        <FilesMatch \\.php$>
            SetHandler application/x-httpd-php
        </FilesMatch>
    </Directory>
    ErrorLog /var/log/httpd/wordpress-error.log
    CustomLog /var/log/httpd/wordpress-access.log combined
</VirtualHost>
EOT

sed -i 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf

if [ ! -f /var/www/html/wp-config.php ]; then
    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -r wordpress/* /var/www/html/
    cd /var/www/html
    cp wp-config-sample.php wp-config.php
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "binarysoftwear-db-credentials" --region ${var.aws_region} --query SecretString --output text)
    DB_HOST=$(echo $SECRET_JSON | jq -r '.endpoint' | cut -d':' -f1)
    DB_NAME=$(echo $SECRET_JSON | jq -r '.dbname')
    DB_USER=$(echo $SECRET_JSON | jq -r '.username')
    DB_PASS=$(echo $SECRET_JSON | jq -r '.password')
    sed -i "s/database_name_here/$DB_NAME/g" wp-config.php
    sed -i "s/username_here/$DB_USER/g" wp-config.php
    sed -i "s/password_here/$DB_PASS/g" wp-config.php
    sed -i "s/localhost/$DB_HOST/g" wp-config.php
    
    cat >/tmp/wp-configs<<EOT
define('WP_HOME','https://binarysoftwear.com');
define('WP_SITEURL','https://binarysoftwear.com');
define('FORCE_SSL_ADMIN',true);
if(isset(\$_SERVER['HTTP_X_FORWARDED_PROTO'])&&\$_SERVER['HTTP_X_FORWARDED_PROTO']==='https'){\$_SERVER['HTTPS']='on';\$_SERVER['SERVER_PORT']=443;}
define('WP_CACHE',true);
define('WP_MEMORY_LIMIT','512M');
define('AUTOSAVE_INTERVAL',300);
define('WP_POST_REVISIONS',3);
define('DISALLOW_FILE_EDIT',true);
define('EMPTY_TRASH_DAYS',7);
define('MEDIA_TRASH',true);
EOT
    sed -i "/That's all, stop editing/e cat /tmp/wp-configs" wp-config.php
    chown -R apache:apache /var/www/html
    echo "OK" > /var/www/html/health.html
    chmod 644 /var/www/html/health.html
    chown apache:apache /var/www/html/health.html
fi

cat >/var/www/html/.htaccess<<EOT
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:\$\{HTTP:Authorization\}]
RewriteBase /
RewriteRule ^index\\.php$ - [L]
RewriteCond %%{REQUEST_FILENAME} !-f
RewriteCond %%{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]

# Proxy and SSL fixes
SetEnvIf X-Forwarded-Proto https HTTPS=on
SetEnvIf X-Forwarded-Host .+ HTTP_HOST=\$\{X-Forwarded-Host\}e

# Special handling for post.php to prevent admin issues
<Files "post.php">
  # Set higher limits for post.php
  php_value max_execution_time 300
  php_value post_max_size 128M
  php_value upload_max_filesize 64M
  php_value memory_limit 256M
  
  # Explicitly allow all methods
  <LimitExcept GET POST PUT DELETE>
    Order deny,allow
    Allow from all
  </LimitExcept>
</Files>
</IfModule>
# END WordPress

# Redirect ELB and ALB domains to main domain
RewriteCond %%{HTTP_HOST} ^binarysoftwear-alb [NC,OR]
RewriteCond %%{HTTP_HOST} elb\\.amazonaws\\.com [NC,OR]
RewriteCond %%{HTTP_HOST} cloudfront\\.net [NC]
RewriteRule ^(.*)$ https://binarysoftwear.com/$1 [L,R=301]
EOT

# Add a script to disable the problematic plugin (All-in-One SEO)
cat >/tmp/disable-aioseo.php<<EOT
<?php
// Script to disable All-in-One SEO if it's found
\$plugin_dir = '/var/www/html/wp-content/plugins/';
\$aioseo_dir = \$plugin_dir . 'all-in-one-seo-pack';

if (is_dir(\$aioseo_dir)) {
    // Rename the directory to disable the plugin
    rename(\$aioseo_dir, \$aioseo_dir . '.disabled');
    echo "All-in-One SEO plugin has been disabled.\n";
}
EOT

# Execute the script
php /tmp/disable-aioseo.php
EOT

chmod 644 /var/www/html/.htaccess
chown apache:apache /var/www/html/.htaccess
chmod -R 755 /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
chown -R apache:apache /var/www/html
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

if [ -f /var/www/html/wp-config.php ] && [ -d /var/www/html/wp-content/uploads ]; then
  cd /var/www/html
  wp plugin install autoptimize --activate --allow-root
  chown -R apache:apache /var/www/html/wp-content w3-total-cache --activate --allow-root
  wp w3-total-cache config set pgcache.enabled true --type=boolean --allow-root
  wp w3-total-cache config set minify.enabled true --type=boolean --allow-root
  wp w3-total-cache config set dbcache.enabled true --type=boolean --allow-root
  wp w3-total-cache config set objectcache.enabled true --type=boolean --allow-root
  wp w3-total-cache config set browsercache.enabled true --type=boolean --allow-root
  wp plugin install autoptimize --activate --allow-root
  chown -R apache:apache /var/www/html/wp-content
fi

systemctl restart httpd
chmod 640 /var/www/html/wp-config.php
echo "0 3 * * 0 root cd /var/www/html && wp plugin update --all --allow-root" > /etc/cron.d/wp-updates
EOF
  )
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