resource "aws_efs_file_system" "main" {
  creation_token   = "binarysoftwear-efs"
  performance_mode = "maxIO"
  encrypted        = true

  throughput_mode = "bursting"

  tags = {
    Name = "binarysoftwear-efs"
  }
}

# A mount target in each private subnet
resource "aws_efs_mount_target" "private_mt" {
  count           = length(var.private_subnets)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs_sg.id] # Use the dedicated EFS SG

  depends_on = [aws_vpc.main]
}
