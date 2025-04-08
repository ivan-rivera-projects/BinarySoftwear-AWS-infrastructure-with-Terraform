resource "aws_secretsmanager_secret" "db_secret" {
  name = "binarysoftwear-db-credentials"
}

# The secret version (the actual username/password) should be managed
# directly in AWS Secrets Manager, not created by Terraform based on variables.
# Terraform will now read the existing secret value.
# Must make sure to retrieve these secrets on your EC2 at boot time or via plugin
