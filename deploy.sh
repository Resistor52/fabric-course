#!/bin/bash
set -e  # Exit on error

echo "Checking for existing backend configuration..."

if [ -f "backend.tf" ]; then
    echo "Backend already configured, proceeding with normal terraform apply..."
    terraform init
    terraform apply
else
    echo "No backend configuration found. Starting initial deployment process..."

    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        echo "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Initialize terraform without backend
    echo "Initializing Terraform..."
    terraform init

    # Create state bucket and DynamoDB table
    echo "Creating state bucket and DynamoDB table..."
    terraform apply -target=random_string.bucket_suffix \
                   -target=aws_s3_bucket.terraform_state \
                   -target=aws_s3_bucket_versioning.terraform_state \
                   -target=aws_dynamodb_table.terraform_state_lock \
                   -auto-approve

    # Get the bucket name
    BUCKET_NAME=$(terraform output -raw state_bucket)
    echo "Created state bucket: $BUCKET_NAME"

    # Create backend config file
    echo "Configuring backend..."
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

    # Reinitialize with backend
    echo "Reinitializing Terraform with S3 backend..."
    if ! terraform init -force-copy; then
        echo "Error initializing backend. Cleaning up..."
        rm backend.tf
        terraform destroy -target=aws_dynamodb_table.terraform_state_lock \
                        -target=aws_s3_bucket_versioning.terraform_state \
                        -target=aws_s3_bucket.terraform_state \
                        -auto-approve
        exit 1
    fi
fi

# Deploy/update the infrastructure
echo "Deploying/updating infrastructure..."
terraform apply -auto-approve

echo "Deployment complete!"
if [ ! -f "backend.tf" ]; then
    echo "State bucket: $BUCKET_NAME"
fi
echo "You can now use 'terraform plan' and 'terraform apply' normally" 