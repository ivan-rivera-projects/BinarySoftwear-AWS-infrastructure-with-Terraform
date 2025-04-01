# Filename: generate_mermaid_diagram.py

import textwrap
import os

def generate_diagram_to_file(output_filename="binarysoftwear_architecture.md"):
    """
    Generates a Mermaid diagram definition for the BinarySoftwear AWS architecture
    and writes it to the specified output file.
    """
    mermaid_definition = """
```mermaid
graph TD
    subgraph UserSpace ["User Space"]
        User[("User / Browser")]:::admin
    end

    subgraph AWSCloud ["AWS Cloud (us-east-1)"]
        direction LR

        Route53[("Route 53<br/>binarysoftwear.com<br/>(aws_route53_zone.main)")]:::dns
        CloudFront[("CloudFront<br/>(d1yi6dtz2qg5ym.cloudfront.net)<br/>(Managed via W3TC)")]:::cdn
        WAFGlobal[("WAF Global<br/>(aws_wafv2_web_acl.cloudfront_waf_acl)<br/>Common, WP-Admin Allow, Rate Limit")]:::sec -- "Protects" --> CloudFront

        subgraph VPC ["VPC (aws_vpc.main: 10.0.0.0/16)"]
            direction TB

            subgraph PublicSubnets ["Public Subnets (AZ-a, AZ-b)"]
                direction TB
                ALB[/"ALB<br/>(aws_lb.main)"/]:::lb
                Bastion[("Bastion Host<br/>(aws_instance.bastion)<br/>t3.micro")]:::compute_mgmt
                NATGW[/"NAT Gateway<br/>(aws_nat_gateway.nat_gw)"/]:::gw
                IGW[/"Internet Gateway<br/>(aws_internet_gateway.igw)"/]:::gw

                ALB -- "HTTPS/80" --> TG[("Target Group<br/>(aws_lb_target_group.main)")]:::tg
                Bastion -- "SSH (TCP/22)" ---> EC2SG[(EC2 SG)]:::sg

                %% Public Subnet Routing: -> IGW
            end

            subgraph PrivateSubnets ["Private Subnets (AZ-a, AZ-b)"]
                direction TB
                ASG["ASG<br/>(aws_autoscaling_group.main)<br/>Min:2, Desired:2, Max:6<br/>(t3.small + Spot)"]:::asg
                EC2Instance["EC2 Instances<br/>(WordPress / PHP 8.2 / Apache)"]:::compute
                RDSSG[(RDS SG)]:::sg --> RDS
                ElastiCacheSG[(ElastiCache SG)]:::sg --> ElastiCache
                EC2SG -- "NFS (TCP/2049)" --> EFS

                subgraph DataStores ["Data Stores & Services"]
                    RDS[("RDS MySQL 8.0<br/>(aws_db_instance.main)<br/>db.t3.small Multi-AZ")]:::db
                    ElastiCache[("ElastiCache Memcached<br/>(aws_elasticache_cluster.memcached)<br/>cache.t3.micro")]:::cache
                    EFS[/"EFS<br/>(aws_efs_file_system.main)<br/>maxIO / Provisioned<br/>(Mounts in Private Subnets)"/]:::storage
                    SecretsManager[("Secrets Manager<br/>(aws_secretsmanager_secret.db_secret)")]:::sec
                end

                %% Private Subnet Routing: -> NATGW
            end

            %% Security Groups & Connections
            ALBSG[(ALB SG)]:::sg --> ALB
            TG -- "Registers Instances" --> ASG
            ASG -- "Launches Instances" --> EC2Instance

            EC2SG[(EC2 SG)]:::sg --> EC2Instance
            EC2Instance -- "MySQL (TCP/3306)" --> RDSSG
            EC2Instance -- "Memcached (TCP/11211)" --> ElastiCacheSG
            EC2Instance -- "Reads Credentials" --> SecretsManager
            EC2Instance -- "Outbound Internet" --> NATGW

        end

        WAFRegional[("WAF Regional<br/>(aws_wafv2_web_acl.waf_acl)<br/>Common Rules")]:::sec -- "Protects" --> ALB

    end

    %% Overall Flow (Reflecting Active CloudFront)
    User --> Route53
    Route53 -- "Alias Record" --> CloudFront
    CloudFront -- "Origin Request" --> ALB
    ALBSG -- "Allow HTTPS/80 from CloudFront IPs (Implicitly via Origin Config)" --x CloudFront %% Simplified view of SG interaction
    ALBSG -- "(Egress Allowed)" --> EC2SG

    %% Bastion Access Flow
    AdminUser[("Admin User")]:::admin --> BastionSG[(Bastion SG)]:::sg
    BastionSG -- "Allow SSH from 0.0.0.0/0" --x Internet[("Internet")]
    BastionSG --> Bastion

    %% Style Definitions
    classDef dns fill:#cff,stroke:#333,stroke-width:2px;
    classDef cdn fill:#ffcc99,stroke:#333,stroke-width:2px;
    classDef lb fill:#f90,stroke:#333,stroke-width:2px;
    classDef tg fill:#ff9,stroke:#333,stroke-width:2px;
    classDef asg fill:#adf,stroke:#333,stroke-width:2px;
    classDef compute fill:#9cf,stroke:#333,stroke-width:2px;
    classDef compute_mgmt fill:#aef,stroke:#333,stroke-width:2px;
    classDef db fill:#f9d,stroke:#333,stroke-width:2px;
    classDef cache fill:#f9f,stroke:#333,stroke-width:2px;
    classDef storage fill:#9fc,stroke:#333,stroke-width:2px;
    classDef gw fill:#ccc,stroke:#333,stroke-width:2px;
    classDef sec fill:#fcc,stroke:#333,stroke-width:2px;
    classDef sg fill:#ddd,stroke:#666,stroke-width:1px,color:#666;
    classDef admin fill:#ffc,stroke:#333,stroke-width:1px;

    %% Note: Diagram reflects active state confirmed by user/docs,
    %% which may differ from Terraform state for Route53/CloudFront enablement
    %% due to external management (e.g., W3 Total Cache plugin).
```
    """
    # Dedent the multi-line string to remove leading whitespace
    dedented_definition = textwrap.dedent(mermaid_definition).strip()

    try:
        with open(output_filename, 'w') as f:
            f.write(dedented_definition)
        print(f"Successfully generated Mermaid diagram definition to: {os.path.abspath(output_filename)}")
    except IOError as e:
        print(f"Error writing diagram to file {output_filename}: {e}")

if __name__ == "__main__":
    generate_diagram_to_file() # Call the function to write to file