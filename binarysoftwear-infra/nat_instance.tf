# NAT Instance Configuration
# Created: April 21, 2025
# This file defines the NAT Instance that replaces the NAT Gateway

# Security Group for NAT Instance
resource "aws_security_group" "nat_instance_sg" {
  name        = "binarysoftwear-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP traffic from private subnets
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/24", "10.0.4.0/24"]
    description = "HTTP from private subnets"
  }

  # Allow HTTPS traffic from private subnets
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/24", "10.0.4.0/24"]
    description = "HTTPS from private subnets"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "binarysoftwear-nat-instance-sg"
  }
}

# Latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# NAT Instance (using t3.small for better performance)
resource "aws_instance" "nat_instance" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nat_instance_sg.id]
  source_dest_check      = false
  
  # Ensure instance gets a public IP
  associate_public_ip_address = true
  
  # User data script to enable NAT functionality
  user_data = <<-EOF
    #!/bin/bash
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
    
    # Install iptables services
    yum install -y iptables-services
    
    # Configure NAT functionality
    iptables -t nat -A POSTROUTING -o eth0 -s 10.0.0.0/16 -j MASQUERADE
    
    # Save iptables rules
    service iptables save
    systemctl enable iptables
    systemctl start iptables
  EOF
  
  tags = {
    Name = "binarysoftwear-nat-instance"
  }
}

# Elastic IP for NAT Instance
resource "aws_eip" "nat_instance_eip" {
  domain = "vpc"
  
  tags = {
    Name = "binarysoftwear-nat-instance-eip"
  }
}

# Associate EIP with NAT Instance
resource "aws_eip_association" "nat_instance_eip_assoc" {
  instance_id   = aws_instance.nat_instance.id
  allocation_id = aws_eip.nat_instance_eip.id
}

# The route for private subnets is handled with a local-exec provisioner
# to ensure it replaces any existing route
resource "null_resource" "update_route_table" {
  # This resource will always run
  triggers = {
    always_run = "${timestamp()}"
  }

  # Run AWS CLI command to replace the existing route
  provisioner "local-exec" {
    command = <<-EOT
      echo "Updating route table to use NAT instance..."
      aws ec2 replace-route \
        --route-table-id rtb-0469f52b82adfec87 \
        --destination-cidr-block 0.0.0.0/0 \
        --network-interface-id ${aws_instance.nat_instance.primary_network_interface_id} \
        --region us-east-1
      echo "Route updated successfully"
    EOT
  }

  depends_on = [
    aws_instance.nat_instance,
    aws_eip_association.nat_instance_eip_assoc
  ]
}

# Output values
output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = aws_instance.nat_instance.id
}

output "nat_instance_private_ip" {
  description = "Private IP of the NAT instance"
  value       = aws_instance.nat_instance.private_ip
}

output "nat_instance_public_ip" {
  description = "Public IP of the NAT instance (from EIP)"
  value       = aws_eip.nat_instance_eip.public_ip
}
