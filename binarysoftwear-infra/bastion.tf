resource "aws_security_group" "bastion_sg" {
  name        = "binarysoftwear-bastion-sg"
  description = "Security group for Bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "binarysoftwear-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = "ami-04aa00acb1165b32a" # Amazon Linux 2 AMI
  instance_type               = "t3.micro"
  key_name                    = "MyVPC-KeyPair1"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "binarysoftwear-bastion"
  }

  user_data = <<-EOF
#!/bin/bash
yum update -y
EOF
}

output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The public IP of the Bastion host"
} 