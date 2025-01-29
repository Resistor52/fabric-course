#!/bin/bash
set -e

# Disable AWS CLI pager
export AWS_PAGER=""

# Generate random suffix
SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
BUCKET_NAME="fabric-course-state-$SUFFIX"

echo "Creating S3 bucket, DynamoDB table, and Elastic IP for Terraform state..."

# Create S3 bucket
aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Create DynamoDB table
aws dynamodb create-table \
    --table-name fabric-course-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1

# Allocate Elastic IP
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids $ALLOCATION_ID --query 'Addresses[0].PublicIp' --output text)

echo "Allocated Elastic IP: $ELASTIC_IP (Allocation ID: $ALLOCATION_ID)"

# Create backend config
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "${BUCKET_NAME}"
    key            = "fabric-course/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "fabric-course-state-lock"
  }
}

# Import the existing Elastic IP
import {
  to = aws_eip.fabric_course
  id = "${ALLOCATION_ID}"
}

# Store Elastic IP information
resource "aws_eip" "fabric_course" {
  domain = "vpc"

  tags = {
    Name = "fabric-course-eip"
  }

  lifecycle {
    prevent_destroy = true
  }
}
EOF

# Create import configuration
cat > import.tf << EOF
resource "aws_eip" "fabric_course" {
  domain = "vpc"
  tags = {
    Name = "fabric-course-eip"
  }
}
EOF

echo "Backend setup complete!"
echo "Bucket name: $BUCKET_NAME"
echo "Elastic IP: $ELASTIC_IP"
echo ""
echo "Next steps:"
echo "1. Run: terraform init"
echo "2. Run: terraform import aws_eip.fabric_course ${ALLOCATION_ID}"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply" 