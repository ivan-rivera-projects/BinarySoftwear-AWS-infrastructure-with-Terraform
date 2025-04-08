resource "aws_db_subnet_group" "main" {
  name       = "binarysoftwear-rds-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = { Name = "binarysoftwear-rds-subnet-group" }
}
# Data source to retrieve the secret value from Secrets Manager
data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_secret.id # Reference the secret created in secrets_manager.tf
}

resource "aws_db_instance" "main" {
  identifier             = "binarysoftwear-rds"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  multi_az               = true
  storage_type           = "gp3"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  db_name  = var.db_name
  # Use credentials directly from Secrets Manager
  username = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["username"]
  password = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)["password"]

  # Performance optimizations
  max_allocated_storage = 100
  parameter_group_name  = aws_db_parameter_group.main.name

  # Backup and maintenance
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  skip_final_snapshot = true

  tags = {
    Name = "binarysoftwear-rds"
  }
}

# Create a parameter group for performance optimization
resource "aws_db_parameter_group" "main" {
  name   = "binarysoftwear-mysql-params"
  family = "mysql8.0"

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "268435456" # 256MB in bytes
  }

  parameter {
    name  = "innodb_file_per_table"
    value = "1"
  }

  parameter {
    name  = "innodb_flush_log_at_trx_commit"
    value = "2"
  }

  parameter {
    name  = "max_connections"
    value = "150"
  }

  # MySQL 8.0 no longer supports query cache parameters

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }
}
