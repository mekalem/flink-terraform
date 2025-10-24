#!/bin/bash
set -e  # Exit on any error

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading environment variables from .env..."
    set -a  # Export all variables
    source .env
    set +a  # Stop exporting
else
    echo "Warning: .env file not found"
    exit 1
fi

# Run terraform apply with loaded variables
echo "Deploying with variables:"
echo "  Harbor Registry: $HARBOR_REGISTRY"
echo "  Harbor Project: $HARBOR_PROJECT"
echo "  Image: $IMAGE_NAME:$IMAGE_TAG"

echo "  S3 Bucket: $S3_BUCKET_NAME"
echo "  S3 Endpoint: $S3_ENDPOINT_URL"

terraform apply \
  -var="harbor_registry=$HARBOR_REGISTRY" \
  -var="harbor_project=$HARBOR_PROJECT" \
  -var="image_name=$IMAGE_NAME" \
  -var="image_tag=$IMAGE_TAG" \
  -var="s3_bucket_name=$S3_BUCKET_NAME" \
  -var="s3_model_key=$S3_MODEL_KEY" \
  -var="s3_endpoint_url=$S3_ENDPOINT_URL" \
  -var="s3_access_key_id=$AWS_ACCESS_KEY_ID" \
  -var="s3_secret_access_key=$AWS_SECRET_ACCESS_KEY" \
  -var="aws_region=$AWS_REGION" \
  "$@"  # Pass any additional arguments

# terraform apply \
#   -var="harbor_registry=$HARBOR_REGISTRY" \
#   -var="harbor_project=$HARBOR_PROJECT" \
#   -var="image_name=$IMAGE_NAME" \
#   -var="image_tag=$IMAGE_TAG" \
#   "$@"  # Pass any additional arguments