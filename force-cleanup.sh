#!/bin/bash
set -e

echo "WARNING: This will forcefully delete all resources."
echo "Type 'yes' to continue:"
read confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# Get the bucket name from backend.tf if it exists
if [ -f "backend.tf" ]; then
    BUCKET_NAME=$(grep 'bucket' backend.tf | cut -d'"' -f2)
    echo "Found bucket: $BUCKET_NAME"
    
    # Initialize with current backend to ensure we can access state
    terraform init
    
    # Destroy infrastructure while we still have access to the state
    echo "Destroying infrastructure..."
    terraform destroy -auto-approve
    
    # Empty and delete the bucket
    echo "Removing all versions from bucket..."
    # Delete all versions
    versions=$(aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --output json \
        --query 'Versions[].{Key:Key,VersionId:VersionId}')
    
    if [ "$versions" != "[]" ] && [ -n "$versions" ]; then
        echo "$versions" | jq -c '.[]' | while read -r object; do
            key=$(echo "$object" | jq -r '.Key')
            version_id=$(echo "$object" | jq -r '.VersionId')
            echo "Deleting $key version $version_id"
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id"
        done
    fi
    
    # Delete all delete markers
    markers=$(aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --output json \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}')
    
    if [ "$markers" != "[]" ] && [ -n "$markers" ]; then
        echo "$markers" | jq -c '.[]' | while read -r object; do
            key=$(echo "$object" | jq -r '.Key')
            version_id=$(echo "$object" | jq -r '.VersionId')
            echo "Deleting delete marker $key version $version_id"
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id"
        done
    fi
    
    echo "Deleting bucket..."
    aws s3api delete-bucket --bucket "$BUCKET_NAME"
    
    # Delete DynamoDB table
    aws dynamodb delete-table \
        --table-name fabric-course-state-lock \
        --region us-east-1
fi

# Remove backend config
echo "Removing backend configuration..."
rm -f backend.tf

# Initialize terraform locally
echo "Reinitializing Terraform locally..."
terraform init -migrate-state -force-copy

# Clean up local files
echo "Cleaning up local files..."
rm -rf .terraform* terraform.tfstate*

echo "Cleanup complete!" 