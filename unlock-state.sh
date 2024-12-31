#!/bin/bash
set -e

# Get the bucket name from backend.tf
if [ ! -f "backend.tf" ]; then
    echo "No backend.tf found."
    exit 1
fi

BUCKET_NAME=$(grep 'bucket' backend.tf | cut -d'"' -f2)
echo "Found bucket: $BUCKET_NAME"

# Remove the lock from DynamoDB
aws dynamodb put-item \
    --table-name fabric-course-state-lock \
    --item '{ 
        "LockID": {"S": "'$BUCKET_NAME'/fabric-course/terraform.tfstate"},
        "Info": {"S": ""},
        "Digest": {"S": "d41d8cd98f00b204e9800998ecf8427e"}
    }' \
    --region us-east-1

echo "Lock removed!" 