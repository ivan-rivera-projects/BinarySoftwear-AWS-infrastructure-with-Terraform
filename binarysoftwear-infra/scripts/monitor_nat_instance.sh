#!/bin/bash
# NAT Instance Monitoring Script for BinarySoftwear
# Created: April 21, 2025
# This script monitors the health and performance of the NAT instance

# Exit on error
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check parameters
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <instance-id>${NC}"
    echo "Example: $0 i-0123456789abcdef0"
    exit 1
fi

INSTANCE_ID=$1
AWS_REGION="us-east-1"

# Print header
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}BinarySoftwear NAT Instance Monitoring Tool${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo

# Check instance status
echo -e "${YELLOW}Checking instance status...${NC}"
INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --region $AWS_REGION --query "InstanceStatuses[0].{InstanceState:InstanceState.Name,InstanceStatus:InstanceStatus.Status,SystemStatus:SystemStatus.Status}" --output json)

echo "$INSTANCE_STATUS" | jq .

# Check if the instance is running
INSTANCE_STATE=$(echo "$INSTANCE_STATUS" | jq -r '.InstanceState // "unknown"')
if [ "$INSTANCE_STATE" != "running" ]; then
    echo -e "${RED}Instance is not running! Current state: $INSTANCE_STATE${NC}"
    exit 1
fi

# Verify source/destination check is disabled
echo -e "${YELLOW}Verifying source/destination check is disabled...${NC}"
SOURCE_DEST_CHECK=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query "Reservations[0].Instances[0].SourceDestCheck" --output text)

if [ "$SOURCE_DEST_CHECK" == "true" ]; then
    echo -e "${RED}Source/destination check is enabled! This will prevent the instance from functioning as a NAT.${NC}"
    echo -e "To disable it, run: aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --no-source-dest-check --region $AWS_REGION"
else
    echo -e "${GREEN}Source/destination check is correctly disabled.${NC}"
fi

# Get instance details
echo -e "${YELLOW}Getting instance details...${NC}"
INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query "Reservations[0].Instances[0].{InstanceType:InstanceType,PrivateIP:PrivateIpAddress,SubnetId:SubnetId,VpcId:VpcId,LaunchTime:LaunchTime}" --output json)

echo "$INSTANCE_DETAILS" | jq .

# Get the public IP (could be an EIP)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"

# Check if there's an EIP associated
echo -e "${YELLOW}Checking for associated Elastic IP...${NC}"
EIP_ALLOCATION=$(aws ec2 describe-addresses --region $AWS_REGION --filters "Name=instance-id,Values=$INSTANCE_ID" --query "Addresses[0].{AllocationId:AllocationId,PublicIp:PublicIp}" --output json)

if [ "$EIP_ALLOCATION" == "null" ]; then
    echo -e "${YELLOW}No Elastic IP is associated with this instance.${NC}"
    echo -e "${YELLOW}It's recommended to associate an Elastic IP for stable outbound connectivity.${NC}"
else
    echo "$EIP_ALLOCATION" | jq .
fi

# Check CPU utilization
echo -e "${YELLOW}Checking CPU utilization (last 15 minutes)...${NC}"
CPU_UTIL=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=$INSTANCE_ID --statistics Average --start-time $(date -u -v -15M +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --region $AWS_REGION --output json)

echo "$CPU_UTIL" | jq .

# Extract the most recent CPU utilization value
RECENT_CPU=$(echo "$CPU_UTIL" | jq -r '.Datapoints | sort_by(.Timestamp) | last | .Average // "N/A"')

if [ "$RECENT_CPU" != "N/A" ]; then
    if (( $(echo "$RECENT_CPU > 80" | bc -l) )); then
        echo -e "${RED}High CPU utilization detected: $RECENT_CPU%. Consider upgrading instance type.${NC}"
    elif (( $(echo "$RECENT_CPU > 60" | bc -l) )); then
        echo -e "${YELLOW}Moderate CPU utilization: $RECENT_CPU%. Monitor for trends.${NC}"
    else
        echo -e "${GREEN}CPU utilization looks good: $RECENT_CPU%.${NC}"
    fi
else
    echo -e "${YELLOW}No recent CPU data available. The instance might be new or CloudWatch metrics are not enabled.${NC}"
fi

# Check network traffic
echo -e "${YELLOW}Checking network traffic (last hour)...${NC}"
NETWORK_OUT=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name NetworkOut --dimensions Name=InstanceId,Value=$INSTANCE_ID --statistics Sum --start-time $(date -u -v -1H +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --region $AWS_REGION --output json)

echo "$NETWORK_OUT" | jq .

# Calculate average network out in KB/s over the last hour
TOTAL_NETWORK_OUT=$(echo "$NETWORK_OUT" | jq -r '.Datapoints | map(.Sum) | add // 0')
NUM_PERIODS=$(echo "$NETWORK_OUT" | jq -r '.Datapoints | length')

if [ "$NUM_PERIODS" -gt 0 ]; then
    AVG_NETWORK_OUT_BYTES=$(echo "$TOTAL_NETWORK_OUT / $NUM_PERIODS" | bc -l)
    AVG_NETWORK_OUT_KBS=$(echo "$AVG_NETWORK_OUT_BYTES / 300 / 1024" | bc -l)
    printf "${GREEN}Average network output: %.2f KB/s${NC}\n" $AVG_NETWORK_OUT_KBS
    
    if (( $(echo "$AVG_NETWORK_OUT_KBS > 5000" | bc -l) )); then
        echo -e "${YELLOW}High network traffic detected. Monitor for potential bottlenecks.${NC}"
    fi
else
    echo -e "${YELLOW}No network data available for the last hour.${NC}"
fi

# Check route table
echo -e "${YELLOW}Checking route tables using this NAT instance...${NC}"
ROUTE_TABLES=$(aws ec2 describe-route-tables --region $AWS_REGION --filters "Name=route.instance-id,Values=$INSTANCE_ID" --query "RouteTables[*].{RouteTableId:RouteTableId,Routes:Routes[?InstanceId=='$INSTANCE_ID'],AssociatedSubnets:Associations[*].SubnetId}" --output json)

echo "$ROUTE_TABLES" | jq .

RT_COUNT=$(echo "$ROUTE_TABLES" | jq -r 'length')
if [ "$RT_COUNT" -eq 0 ]; then
    echo -e "${RED}No route tables are using this NAT instance!${NC}"
    echo -e "${YELLOW}To set up a route, run:${NC}"
    echo -e "aws ec2 create-route --route-table-id YOUR_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --instance-id $INSTANCE_ID --region $AWS_REGION"
else
    echo -e "${GREEN}NAT instance is being used by $RT_COUNT route table(s).${NC}"
fi

# Check NAT functionality if we have SSH access via a bastion
echo -e "${YELLOW}Do you want to check NAT functionality via SSH? (y/n)${NC}"
read -p "This requires SSH access to the NAT instance via bastion: " CHECK_NAT

if [[ "$CHECK_NAT" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}To check NAT configuration on the instance, SSH to bastion first:${NC}"
    echo -e "ssh -i /path/to/key.pem ec2-user@50.19.12.40"
    echo
    echo -e "${YELLOW}Then SSH to NAT instance:${NC}"
    PRIVATE_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
    echo -e "ssh -i /home/ec2-user/MyVPC-KeyPair1.pem ec2-user@$PRIVATE_IP"
    echo
    echo -e "${YELLOW}On the NAT instance, run these commands to verify NAT configuration:${NC}"
    echo -e "sudo sysctl net.ipv4.ip_forward  # Should be 1"
    echo -e "sudo iptables -t nat -L -n -v  # Should show MASQUERADE rules"
    echo -e "grep ip_forward /etc/sysctl.conf  # Should contain net.ipv4.ip_forward = 1"
fi

echo
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}NAT Instance monitoring completed${NC}"
echo -e "${GREEN}=========================================================${NC}"
