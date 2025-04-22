# COMMENTED OUT: NAT Gateway has been replaced with NAT Instance
# See nat_instance.tf for the new implementation

# Private Route Table for each private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# NOTE: Default route for private subnets now uses NAT Instance
# The route is defined in nat_instance.tf
