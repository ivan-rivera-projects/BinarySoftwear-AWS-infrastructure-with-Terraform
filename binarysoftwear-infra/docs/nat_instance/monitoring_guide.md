# NAT Instance Monitoring Guide

## Overview
This guide provides instructions for monitoring and maintaining the NAT instance deployed as a replacement for the AWS NAT Gateway in the BinarySoftwear infrastructure.

## NAT Instance Details
- **Instance ID**: i-002b650d6b499fa5d
- **Type**: t3.small
- **Role**: Provides internet access to resources in private subnets
- **Location**: First public subnet in the VPC

## Recommended Monitoring Metrics

### Key Performance Indicators
1. **CPU Utilization**
   - **Concern Threshold**: >80% sustained
   - **Critical Threshold**: >90% sustained
   - **Mitigation**: Consider upgrading instance type

2. **Network Traffic**
   - **NetworkIn/NetworkOut**
   - **Baseline**: ~4.5 MB out, 398 MB in per day (from initial assessment)
   - **Concern Threshold**: 2x baseline
   - **Mitigation**: Investigate traffic patterns, potential upgrade

3. **Status Checks**
   - **Expected**: Pass both system and instance status checks
   - **Critical**: Any failed status check
   - **Mitigation**: Restart instance, restore from backup if necessary

4. **Credit Balance** (t3 instance)
   - **Concern Threshold**: <25% of maximum credits
   - **Critical Threshold**: <10% of maximum credits
   - **Mitigation**: Consider upgrading to a non-burstable instance type

## Monitoring Commands

### Basic Health Check
```bash
# Get basic instance details
aws ec2 describe-instances \
  --instance-ids i-002b650d6b499fa5d \
  --query "Reservations[0].Instances[0].{State:State.Name,StatusChecks:MonitoringState,Type:InstanceType,LaunchTime:LaunchTime}" \
  --output table
```

### CPU Utilization
```bash
# Get CPU utilization for the last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-002b650d6b499fa5d \
  --statistics Average Maximum \
  --start-time $(date -v -1H -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300
```

### Network Traffic
```bash
# Get network traffic for the last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkOut \
  --dimensions Name=InstanceId,Value=i-002b650d6b499fa5d \
  --statistics Sum \
  --start-time $(date -v -1H -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300
```

### Credit Balance
```bash
# Check CPU credit balance (for t3 instances)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUCreditBalance \
  --dimensions Name=InstanceId,Value=i-002b650d6b499fa5d \
  --statistics Average \
  --start-time $(date -v -1H -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300
```

### NAT Functionality
```bash
# SSH to NAT instance (via bastion)
ssh -i /path/to/key.pem ec2-user@50.19.12.40
ssh -i /home/ec2-user/MyVPC-KeyPair1.pem ec2-user@<NAT-PRIVATE-IP>

# Check IP forwarding
sudo sysctl net.ipv4.ip_forward

# Check NAT rules
sudo iptables -t nat -L -n -v

# Check network connections
sudo netstat -tulpn

# Check system load
uptime
```

## Setting Up CloudWatch Alarms

### CPU Utilization Alarm
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "NAT-Instance-High-CPU" \
  --alarm-description "Alarm when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-002b650d6b499fa5d \
  --evaluation-periods 2 \
  --alarm-actions <SNS-TOPIC-ARN>
```

### Status Check Alarm
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "NAT-Instance-Status-Check" \
  --alarm-description "Alarm when status check fails" \
  --metric-name StatusCheckFailed \
  --namespace AWS/EC2 \
  --statistic Maximum \
  --period 60 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-002b650d6b499fa5d \
  --evaluation-periods 1 \
  --alarm-actions <SNS-TOPIC-ARN>
```

## Troubleshooting

### Loss of Internet Access from Private Instances
1. Verify NAT instance is running
2. Confirm IP forwarding is enabled
   ```
   sudo sysctl net.ipv4.ip_forward
   ```
3. Check NAT rules are in place
   ```
   sudo iptables -t nat -L -n -v
   ```
4. Verify route table is correctly pointing to NAT instance
   ```
   aws ec2 describe-route-tables --route-table-ids rtb-0469f52b82adfec87
   ```
5. Check security group rules allow necessary traffic

### High CPU or Network Usage
1. Check what processes are consuming resources
   ```
   top
   ```
2. Check network connections
   ```
   netstat -anp
   ```
3. Consider upgrading instance type if consistently high

## Maintenance Procedures

### Upgrading Instance Type
1. Stop the NAT instance
2. Change instance type via AWS Console or CLI
3. Start the instance
4. Verify route table configuration

### Security Updates
1. Connect to the NAT instance
2. Run system updates
   ```
   sudo yum update -y
   ```
3. Reboot if necessary
   ```
   sudo reboot
   ```
4. Verify NAT functionality after reboot

## Automated Monitoring Script
The monitoring script located at `/Users/ivanrivera/Downloads/AWS/binarysoftwear/binarysoftwear-infra/scripts/monitor_nat_instance.sh` can be used to perform regular health checks on the NAT instance.

Usage:
```bash
./scripts/monitor_nat_instance.sh i-002b650d6b499fa5d
```
