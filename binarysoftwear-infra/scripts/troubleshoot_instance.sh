#!/bin/bash
# EC2 Instance Troubleshooting Script
# Run via AWS Systems Manager Run Command 

# Log start
echo "===== Starting troubleshooting script at $(date) ====="
echo "Host: $(hostname)"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Check system resources
echo -e "\n===== System Resources ====="
echo "CPU Usage:"
top -bn1 | head -n 5
echo "Memory Usage:"
free -m
echo "Disk Usage:"
df -h

# Check Apache status
echo -e "\n===== Apache Status ====="
systemctl status httpd
echo "Apache Process Count:"
ps aux | grep -v grep | grep -c httpd

# Check for Apache errors
echo -e "\n===== Apache Error Log (last 20 lines) ====="
if [ -f /var/log/httpd/error_log ]; then
  tail -n 20 /var/log/httpd/error_log
else
  echo "Apache error log not found"
fi

if [ -f /var/log/httpd/wordpress-error.log ]; then
  echo -e "\n===== WordPress Error Log (last 20 lines) ====="
  tail -n 20 /var/log/httpd/wordpress-error.log
else
  echo "WordPress error log not found"
fi

# Check Apache configuration
echo -e "\n===== Apache Configuration Syntax Check ====="
apachectl configtest

# Check PHP status
echo -e "\n===== PHP Status ====="
php -v
echo "PHP Modules:"
php -m

# Check EFS mount
echo -e "\n===== EFS Mount Status ====="
if mount | grep -q "/var/www/html"; then
  echo "EFS is mounted at /var/www/html"
  ls -la /var/www/html | head -n 10
else
  echo "WARNING: EFS is not mounted!"
  echo "Attempting to mount EFS..."
  mount -a
  if mount | grep -q "/var/www/html"; then
    echo "EFS mounted successfully"
  else
    echo "Failed to mount EFS"
  fi
fi

# Check ElastiCache connectivity
echo -e "\n===== ElastiCache Connectivity ====="
if [ -f /var/www/html/memcached-test.php ]; then
  echo "Testing ElastiCache connection..."
  RESULT=$(php /var/www/html/memcached-test.php 2>/dev/null | grep -i "connection status")
  echo "$RESULT"
else
  echo "memcached-test.php not found"
fi

# Check health check endpoint
echo -e "\n===== Health Check Endpoint ====="
if [ -f /var/www/html/health.html ]; then
  echo "health.html file exists:"
  ls -la /var/www/html/health.html
  echo "Content:"
  cat /var/www/html/health.html
  echo "Testing local access:"
  curl -s http://localhost/health.html
else
  echo "health.html file not found, creating it now:"
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
  echo "health.html file created:"
  ls -la /var/www/html/health.html
fi

# Check WordPress configuration
echo -e "\n===== WordPress Configuration ====="
if [ -f /var/www/html/wp-config.php ]; then
  echo "wp-config.php exists"
  # Check for specific WordPress configuration issues (without showing credentials)
  grep -i "define.*wp_debug" /var/www/html/wp-config.php | grep -v "DB_"
else
  echo "wp-config.php not found - WordPress may not be installed"
fi

# Check W3 Total Cache configuration
echo -e "\n===== W3 Total Cache Configuration ====="
if [ -d /var/www/html/wp-content/plugins/w3-total-cache ]; then
  echo "W3 Total Cache plugin is installed"
  if [ -f /var/www/html/wp-content/w3tc-config/master.php ]; then
    echo "W3TC configuration file exists"
    grep -i "memcached" /var/www/html/wp-content/w3tc-config/master.php | grep -i "server"
  else
    echo "W3TC configuration file not found"
  fi
else
  echo "W3 Total Cache plugin not found"
fi

# Network connectivity tests
echo -e "\n===== Network Connectivity Tests ====="
echo "Testing connection to ElastiCache:"
timeout 5 telnet binarysoftwear-memcached.u9tsst.cfg.use1.cache.amazonaws.com 11211 </dev/null
echo "Testing connection to RDS (assuming default port 3306):"
timeout 5 telnet binarysoftwear-db.cluster-xxxxxxx.us-east-1.rds.amazonaws.com 3306 </dev/null
echo "Testing outbound internet connectivity:"
timeout 5 curl -s -o /dev/null -w "%{http_code}" https://www.google.com

# Log finish
echo -e "\n===== Troubleshooting completed at $(date) ====="
