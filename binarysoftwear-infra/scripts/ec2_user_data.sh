#!/bin/bash
# Enable error handling and logging
set -e # Exit on error
set -o pipefail # Exit if any command in a pipe fails
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Function for error handling
handle_error() {
  local exit_code=$?
  local line_number=$1
  echo "Error on line $line_number: Command exited with status $exit_code"
  # Optional: add AWS SNS notification or other alerts here
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Log start time and instance information
echo "===== Starting EC2 instance configuration at $(date) ====="
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "Instance ID: $INSTANCE_ID"
echo "Instance Type: $INSTANCE_TYPE"
echo "Availability Zone: $AVAILABILITY_ZONE"
yum update -y
amazon-linux-extras enable php8.2
yum install -y httpd php php-mysqlnd php-json php-gd php-mbstring php-xml php-intl php-soap php-zip mariadb amazon-efs-utils jq aws-cli php-opcache php-apcu php-curl

# Install ImageMagick and the PHP imagick extension properly
yum install -y ImageMagick ImageMagick-devel php-pear gcc make
pecl channel-update pecl.php.net
printf "\n" | pecl install imagick
echo "extension=imagick.so" > /etc/php.d/20-imagick.ini

# Install Memcached PHP extension
yum install -y zlib-devel libmemcached-devel
printf "\n" | pecl install memcached
echo "extension=memcached.so" > /etc/php.d/40-memcached.ini

# Enable mod_rewrite and other required modules
sed -i '/#LoadModule rewrite_module/s/^#//g' /etc/httpd/conf.modules.d/00-base.conf
sed -i '/#LoadModule deflate_module/s/^#//g' /etc/httpd/conf.modules.d/00-base.conf
sed -i '/#LoadModule expires_module/s/^#//g' /etc/httpd/conf.modules.d/00-base.conf

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
post_max_size = 64M
max_execution_time = 300
memory_limit = 256M
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

# Create Apache configuration directory if it doesn't exist
mkdir -p /etc/httpd/conf.d

# Configure main Apache settings
cat >/etc/httpd/conf/httpd.conf<<EOT
ServerRoot "/etc/httpd"
Listen 80
Include conf.modules.d/*.conf
User apache
Group apache
ServerAdmin root@localhost
ServerName binarysoftwear.com
<Directory />
    AllowOverride none
    Require all denied
</Directory>
DocumentRoot "/var/www/html"
<Directory "/var/www">
    AllowOverride None
    Require all granted
</Directory>
<Directory "/var/www/html">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
<IfModule dir_module>
    DirectoryIndex index.html index.php
</IfModule>
<Files ".ht*">
    Require all denied
</Files>
ErrorLog "logs/error_log"
LogLevel warn
<IfModule log_config_module>
    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    <IfModule logio_module>
        LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %I %O" combinedio
    </IfModule>
    CustomLog "logs/access_log" combined
</IfModule>
<IfModule mime_module>
    TypesConfig /etc/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
    AddType application/x-httpd-php .php
    AddType application/x-httpd-php-source .phps
</IfModule>
EnableSendfile on
IncludeOptional conf.d/*.conf
EOT

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

EFS_ID="fs-071a3a3b04b1c1f17"
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

# Create a clean, separate WordPress Apache configuration
# Create Apache configuration directory if it doesn't exist
mkdir -p /etc/httpd/conf.d

# Create WordPress Apache configuration
# Use 'cat' with a heredoc for clean Apache configuration
echo "Creating Apache configuration for WordPress..."
cat > /etc/httpd/conf.d/wordpress.conf << 'APACHE_CONFIG'
<VirtualHost *:80>
    ServerName binarysoftwear.com
    ServerAlias www.binarysoftwear.com
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        <FilesMatch \.php$>
            SetHandler application/x-httpd-php
        </FilesMatch>
    </Directory>

    # Handle WordPress-specific requirements
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteBase /
    </IfModule>

    ErrorLog /var/log/httpd/wordpress-error.log
    CustomLog /var/log/httpd/wordpress-access.log combined
</VirtualHost>
APACHE_CONFIG

# Ensure Apache configuration is valid
echo "Validating Apache configuration..."
if ! apachectl configtest; then
    echo "ERROR: Apache configuration test failed!"
    echo "Contents of wordpress.conf:"
    cat /etc/httpd/conf.d/wordpress.conf
    exit 1
else
    echo "Apache configuration is valid."
fi

# Create and configure .htaccess
cat >/var/www/html/.htaccess<<EOT
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:${HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress

# Security Headers
<IfModule mod_headers.c>
    Header set X-Content-Type-Options "nosniff"
    Header set X-XSS-Protection "1; mode=block"
    Header set X-Frame-Options "SAMEORIGIN"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
    
    # HSTS (uncomment if SSL is properly configured)
    # Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</IfModule>

# Prevent directory browsing
Options -Indexes

# Prevent access to sensitive files
<FilesMatch "^\.">
    Order allow,deny
    Deny from all
</FilesMatch>

<FilesMatch "^(wp-config\.php|php\.ini|\.htaccess)$">
    Order allow,deny
    Deny from all
</FilesMatch>

# Handle forwarded headers
SetEnvIf X-Forwarded-Proto https HTTPS=on
SetEnvIf X-Forwarded-Host .+ HTTP_HOST=${X-Forwarded-Host}
EOT

# Create the Memcached test file to verify connectivity
cat > /var/www/html/memcached-test.php << 'EOT'
<?php
$memcached = new Memcached();
$memcached->addServer('binarysoftwear-memcached.u9tsst.cfg.use1.cache.amazonaws.com', 11211);

// Test set
$memcached->set('test_key', 'Hello from ElastiCache: ' . date('Y-m-d H:i:s'));

// Test get
$value = $memcached->get('test_key');

echo "<h1>ElastiCache Test</h1>";
echo "<p>Connection status: " . ($memcached->getStats() ? "Connected" : "Failed") . "</p>";
echo "<p>Test value: " . $value . "</p>";

// Display stats
echo "<h2>Server Stats</h2><pre>";
print_r($memcached->getStats());
echo "</pre>";
?>
EOT

# Create a static health check file for ALB health checks
cat > /var/www/html/health.html << 'EOT'
<!DOCTYPE html>
<html>
<head>
    <title>BinarySoftwear - Health Check</title>
</head>
<body>
    <h1>OK</h1>
    <p>Server is healthy</p>
</body>
</html>
EOT

# Configure W3TC to use Memcached
# First, check if wp-config.php exists and W3TC is active
if [ -f "/var/www/html/wp-config.php" ] && [ -d "/var/www/html/wp-content/plugins/w3-total-cache" ]; then
  # Define path to W3TC configuration
  W3TC_CONFIG="/var/www/html/wp-content/w3tc-config/master.php"
  
  # Check if W3TC config file exists
  if [ -f "$W3TC_CONFIG" ]; then
    # Make a backup of the original config
    cp "$W3TC_CONFIG" "$W3TC_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    
    # Update the config to use ElastiCache for object and database caching
    sed -i 's/"dbcache.engine":\s*"[^"]*"/"dbcache.engine":"memcached"/g' "$W3TC_CONFIG"
    sed -i 's/"objectcache.engine":\s*"[^"]*"/"objectcache.engine":"memcached"/g' "$W3TC_CONFIG"
    sed -i 's/"dbcache.memcached.servers":\s*\[[^\]]*\]/"dbcache.memcached.servers":["binarysoftwear-memcached.u9tsst.cfg.use1.cache.amazonaws.com:11211"]/g' "$W3TC_CONFIG"
    sed -i 's/"objectcache.memcached.servers":\s*\[[^\]]*\]/"objectcache.memcached.servers":["binarysoftwear-memcached.u9tsst.cfg.use1.cache.amazonaws.com:11211"]/g' "$W3TC_CONFIG"
    
    # Enable both caching mechanisms
    sed -i 's/"dbcache.enabled":\s*false/"dbcache.enabled":true/g' "$W3TC_CONFIG"
    sed -i 's/"objectcache.enabled":\s*false/"objectcache.enabled":true/g' "$W3TC_CONFIG"
    
    echo "W3TC configuration updated to use ElastiCache."
  else
    echo "W3TC config file not found. W3 Total Cache may need to be configured manually."
  fi
else
  echo "WordPress or W3 Total Cache not detected. ElastiCache will need to be configured manually."
fi

# Set proper permissions
chown -R apache:apache /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Restart Apache to apply all changes
systemctl restart httpd

# Verify Apache is running and health check file is accessible
if systemctl is-active --quiet httpd; then
  echo "Apache is running successfully."
  
  # Test if health.html is accessible via localhost
  if curl -s http://localhost/health.html | grep -q "Server is healthy"; then
    echo "Health check file is accessible."
  else
    echo "WARNING: Health check file is not accessible!"
    # Create it again if it's missing
    cat > /var/www/html/health.html << 'EOT'
<!DOCTYPE html>
<html>
<head>
    <title>BinarySoftwear - Health Check</title>
</head>
<body>
    <h1>OK</h1>
    <p>Server is healthy</p>
</body>
</html>
EOT
    chown apache:apache /var/www/html/health.html
    chmod 644 /var/www/html/health.html
    echo "Health check file recreated."
  fi
else
  echo "ERROR: Apache failed to start! Check logs for details."
  cat /var/log/httpd/error_log | tail -n 20
fi

echo "===== EC2 user data script completed at $(date) ====="