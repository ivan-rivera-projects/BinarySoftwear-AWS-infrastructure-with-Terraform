# ElastiCache Security Group
resource "aws_security_group" "elasticache_sg" {
  name        = "binarysoftwear-elasticache-sg"
  description = "Security group for ElastiCache Memcached"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Memcached access from EC2 instances"
    from_port       = 11211
    to_port         = 11211
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "binarysoftwear-elasticache-sg"
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "elasticache_subnet_group" {
  name        = "binarysoftwear-elasticache-subnet-group"
  description = "ElastiCache subnet group for BinarySoftwear"
  subnet_ids  = aws_subnet.private[*].id
}

# ElastiCache Memcached Cluster
resource "aws_elasticache_cluster" "memcached" {
  cluster_id           = "binarysoftwear-memcached"
  engine               = "memcached"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = var.elasticache_num_cache_nodes
  parameter_group_name = "default.memcached1.6"
  engine_version       = var.elasticache_engine_version
  port                 = 11211
  subnet_group_name    = aws_elasticache_subnet_group.elasticache_subnet_group.name
  security_group_ids   = [aws_security_group.elasticache_sg.id]

  # Maintenance and backup window settings
  maintenance_window = "sun:05:00-sun:06:00"

  # Apply Azure auto-minor version upgrade
  apply_immediately = true

  # Add tags
  tags = {
    Name        = "binarysoftwear-memcached"
    Environment = "production"
    Project     = "binarysoftwear"
  }
}

# Output for ElastiCache Endpoint
output "elasticache_endpoint" {
  value       = aws_elasticache_cluster.memcached.configuration_endpoint
  description = "The endpoint for the ElastiCache Memcached cluster"
}
