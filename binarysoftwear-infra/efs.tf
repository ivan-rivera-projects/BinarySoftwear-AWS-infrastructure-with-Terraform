resource "aws_efs_file_system" "main" {
  creation_token   = "binarysoftwear-efs"
  performance_mode = "maxIO"
  encrypted        = true

  # Add provisioned throughput for better performance
  provisioned_throughput_in_mibps = 10
  throughput_mode                 = "provisioned"

  tags = {
    Name = "binarysoftwear-efs"
  }
}

# A mount target in each private subnet
resource "aws_efs_mount_target" "private_mt" {
  count           = length(var.private_subnets)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.ec2_sg.id]

  depends_on = [aws_vpc.main]
}
