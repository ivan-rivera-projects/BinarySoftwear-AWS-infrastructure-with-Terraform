# Binary Softwear Infrastructure

This repository contains the Terraform infrastructure code for the Binary Softwear project.

## Directory Structure

- **Root directory**: Contains all Terraform (`.tf`) configuration files
- **scripts/**: Shell scripts for deployment, configuration, and maintenance
- **docs/**: Documentation files including architecture diagrams and guides
- **database/**: SQL scripts for database operations and fixes
- **backups/**: Backup files of previous configurations
- **logs/**: Log outputs and result files
- **plans/**: Saved Terraform plan files
- **secure/**: Sensitive files like key pairs (not committed to source control)

## Getting Started

1. Initialize Terraform:
   ```
   terraform init
   ```

2. Plan changes:
   ```
   terraform plan -out=plans/tfplan
   ```

3. Apply changes:
   ```
   terraform apply plans/tfplan
   ```

## Infrastructure Components

- VPC with public and private subnets
- Application Load Balancer
- Auto Scaling Group for EC2 instances
- RDS MySQL database (Multi-AZ)
- ElastiCache (Memcached)
- CloudFront CDN integration
- Route53 DNS configuration
- EFS for shared storage
- WAF for security

## Setup & Deployment

The primary setup involves provisioning the AWS infrastructure using Terraform.

**Prerequisites:**

*   [Terraform](https://developer.hashicorp.com/terraform/downloads) installed.
*   [AWS CLI](https://aws.amazon.com/cli/) installed and configured with appropriate AWS credentials.
*   Access to the relevant Route 53 Hosted Zone and an existing SSH Key Pair in AWS `us-east-1`.

**Deployment Steps:**

1.  Navigate to the infrastructure directory:
    ```bash
    cd binarysoftwear-infra
    ```
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Plan the deployment:
    ```bash
    terraform plan -out=tfplan
    ```
4.  Apply the plan:
    ```bash
    terraform apply "tfplan"
    ```

This will provision all necessary AWS resources. The WordPress application itself is deployed and configured automatically via the EC2 User Data scripts defined within the Terraform configuration, pulling necessary components and mounting the shared EFS volume.

## Contributing

While this is primarily a portfolio project, contributions or suggestions are welcome. Please feel free to open an issue or submit a pull request.

## License

Distributed under the MIT License. See `LICENSE` file for more information.

## Contact

*   **Author:** [Ivan Rivera]
*   **LinkedIn:** []
*   **Portfolio:** [iam-ivan.com]
*   **Email:** [ivan.rivera.email@gmail.com](mailto:ivan.rivera.email@gmail.com)
