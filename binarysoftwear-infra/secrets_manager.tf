resource "aws_secretsmanager_secret" "db_secret" {
  name = "binarysoftwear-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_secret_v" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = var.db_name
    endpoint = aws_db_instance.main.endpoint
    port     = 3306
  })
}

# Must make sure to retrieve these secrets on your EC2 at boot time or via plugin
