#!/bin/bash
set -e

# Disable AWS CLI pager
export AWS_PAGER=""

# Get bucket name from backend.tf
BUCKET_NAME=""
if [ -f backend.tf ]; then
    BUCKET_NAME=$(grep 'bucket' backend.tf | awk -F'"' '{print $2}')
fi

echo "Forcefully cleaning up all resources..."

# List and delete all EC2 instances with tag "Name=fabric-course"
echo "Terminating EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=fabric-course" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ ! -z "$INSTANCE_IDS" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS || true
    echo "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS || true
fi

# Delete VPC and related resources
echo "Cleaning up VPC resources..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=fabric-course" --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" != "None" ] && [ ! -z "$VPC_ID" ]; then
    # Delete Internet Gateway
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ "$IGW_ID" != "None" ] && [ ! -z "$IGW_ID" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID || true
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID || true
    fi

    # Delete Subnets
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
    for SUBNET_ID in $SUBNET_IDS; do
        aws ec2 delete-subnet --subnet-id $SUBNET_ID || true
    done

    # Delete Security Groups (except default)
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=!default" --query 'SecurityGroups[].GroupId' --output text)
    for SG_ID in $SG_IDS; do
        aws ec2 delete-security-group --group-id $SG_ID || true
    done

    # Delete Route Tables (except main)
    RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main != `true`].RouteTableId' --output text)
    for RT_ID in $RT_IDS; do
        aws ec2 delete-route-table --route-table-id $RT_ID || true
    done

    # Finally delete the VPC
    aws ec2 delete-vpc --vpc-id $VPC_ID || true
fi

# Clean up S3 bucket if it exists
if [ ! -z "$BUCKET_NAME" ]; then
    echo "Cleaning up S3 bucket $BUCKET_NAME..."
    aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
    aws s3api delete-bucket --bucket ${BUCKET_NAME} --region us-east-1 2>/dev/null || true
fi

# Delete DynamoDB table
echo "Cleaning up DynamoDB table..."
aws dynamodb delete-table --table-name fabric-course-state-lock --region us-east-1 2>/dev/null || true

# Remove backend configuration and create empty one
echo "Removing backend configuration..."
rm -f backend.tf
cat > backend.tf << EOF
terraform {
}
EOF

echo "Cleanup complete!" 