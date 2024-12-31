#!/bin/bash
set -e  # Exit on error

echo "Starting removal process..."

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Please install it first."
    exit 1
fi

# Check if backend.tf exists
if [ ! -f "backend.tf" ]; then
    echo "No backend.tf found. Nothing to remove."
    exit 1
fi

echo "WARNING: This will destroy all resources, including the S3 state bucket and DynamoDB table."
echo "Type 'yes' to continue:"
read confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Initialize terraform if needed
echo "Initializing Terraform..."
terraform init

# Destroy main infrastructure first
echo "Destroying main infrastructure..."
terraform destroy

# Get bucket name before removing backend
BUCKET_NAME=$(terraform output -raw state_bucket)

# Remove backend configuration and reinitialize
echo "Removing backend configuration..."
rm backend.tf
terraform init -force-copy

# Destroy state bucket and DynamoDB table
echo "Destroying state management resources..."
terraform destroy -target=aws_dynamodb_table.terraform_state_lock \
                 -target=aws_s3_bucket_versioning.terraform_state \
                 -target=aws_s3_bucket.terraform_state \
                 -auto-approve

echo "Cleanup complete!"
echo "Removed state bucket: $BUCKET_NAME"
echo "All resources have been destroyed." 