from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import Route53, CloudFront, ALB, NATGateway
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS, ElastiCache
from diagrams.aws.security import WAF, SecretsManager
from diagrams.aws.storage import EFS
from diagrams.aws.general import Users
from diagrams.custom import Custom

with Diagram("BinarySoftwear Architecture", show=False, direction="LR"):
    # User accessing the system
    user = Users("Users")
    
    # AWS Networking
    route53 = Route53("Route 53 (DNS)")
    
    with Cluster("AWS Network"):
        with Cluster("Public Subnet(s)"):
            cloudfront = CloudFront("CloudFront (CDN)")
            waf = WAF("AWS WAF")
            alb = ALB("Application Load Balancer")
            
            # Add bastion host
            bastion = EC2("Bastion Host")
            
            # Add NAT Gateway
            nat = NATGateway("NAT Gateway")
            
        with Cluster("Private Subnet(s)"):
            with Cluster("Web Servers"):
                ec2 = EC2("EC2 Auto-Scaling Instances")
                
                # Add EFS instead of S3
                efs = EFS("EFS (Shared Filesystem)")
                
                # Add ElastiCache Memcached
                memcached = ElastiCache("ElastiCache (Memcached)")
                
            with Cluster("Database"):
                primary_db = RDS("RDS MySQL (Primary)")
                secondary_db = RDS("RDS MySQL (Secondary)")
                primary_db >> Edge(label="Async Replication", color="black", penwidth="2.5") >> secondary_db
            
            # Add Secrets Manager with corrected import
            secrets = SecretsManager("AWS Secrets Manager")
    
    # Connections with thicker lines
    user >> Edge(label="HTTPS", color="black", penwidth="2.5") >> route53
    route53 >> Edge(label="DNS Resolution", color="black", penwidth="2.5") >> cloudfront
    cloudfront >> Edge(label="HTTPS", color="black", penwidth="2.5") >> waf
    waf >> Edge(label="HTTPS", color="black", penwidth="2.5") >> alb
    alb >> Edge(label="HTTP/HTTPS", color="black", penwidth="2.5") >> ec2
    
    # Private subnet connections
    ec2 >> Edge(label="MySQL", color="black", penwidth="2.5") >> primary_db
    ec2 >> Edge(label="NFS", color="black", penwidth="2.5") >> efs
    ec2 >> Edge(label="Fetch Secrets", color="black", penwidth="2.5") >> secrets
    
    # Add ElastiCache Connection
    ec2 >> Edge(label="Memcached (11211)", color="blue", penwidth="2.5") >> memcached
    
    # Bastion and NAT connections
    user >> Edge(label="SSH", style="dashed", color="black") >> bastion
    bastion >> Edge(label="SSH", style="dashed", color="black") >> ec2
    nat >> Edge(label="Internet Access", style="dashed", color="black") >> ec2