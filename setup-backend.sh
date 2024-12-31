#!/bin/bash
set -e

# Generate random suffix
SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
BUCKET_NAME="fabric-course-state-$SUFFIX"

echo "Creating S3 bucket and DynamoDB table for Terraform state..."

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
EOF

echo "Backend setup complete!"
echo "Bucket name: $BUCKET_NAME" 