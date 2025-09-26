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

terraform apply \
  -var="harbor_registry=$HARBOR_REGISTRY" \
  -var="harbor_project=$HARBOR_PROJECT" \
  -var="image_name=$IMAGE_NAME" \
  -var="image_tag=$IMAGE_TAG" \
  "$@"  # Pass any additional arguments