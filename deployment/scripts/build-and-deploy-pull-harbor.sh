#!/bin/bash

set -e

# Load environment variables from .env file
if [ -f .env ]; then
    echo "📋 Loading configuration from .env file..."
    export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)
    echo "✅ Environment variables loaded"
else
    echo "❌ .env file not found! Please create one with your Harbor configuration."
    echo "Example .env file:"
    echo "HARBOR_REGISTRY=your-harbor-url.com"
    echo "HARBOR_PROJECT=your-project-name"
    echo "NAMESPACE=sasktel-data-team-flink"
    exit 1
fi

JOB_NAME=$1
ENVIRONMENT=${2:-${ENVIRONMENT:-dev}}  # Use .env ENVIRONMENT or default to dev
AUTO_DEPLOY=${3:-false}

# Use environment variables from .env
HARBOUR_REGISTRY=${HARBOR_REGISTRY}
HARBOUR_PROJECT=${HARBOR_PROJECT}
REPOSITORY="$JOB_NAME"
TAG="latest"

if [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <job-name> [environment] [auto-deploy]"
    echo "Available jobs: customer-analytics, ml-inference, etc."
    exit 1
fi

# Validate Harbor configuration
if [ -z "$HARBOUR_REGISTRY" ] || [ -z "$HARBOUR_PROJECT" ] || [ "$HARBOUR_REGISTRY" = "your-harbor-url.com" ] || [ "$HARBOUR_PROJECT" = "your-project-name" ]; then
    echo "❌ Error: HARBOUR_REGISTRY and HARBOUR_PROJECT must be configured!"
    echo "Current values:"
    echo "  HARBOUR_REGISTRY='$HARBOUR_REGISTRY'"
    echo "  HARBOUR_PROJECT='$HARBOUR_PROJECT'" 
    echo "  REPOSITORY='$REPOSITORY'"
    echo "  TAG='$TAG'"
    echo ""
    echo "Please check your .env file configuration"
    exit 1
fi

echo "🚀 Deploy-only mode for job: $JOB_NAME (environment: $ENVIRONMENT)"
echo "📦 Skipping build - using existing Harbor image"

# Construct Harbor image name (assuming it already exists)
HARBOR_IMAGE_NAME="$HARBOUR_REGISTRY/$HARBOUR_PROJECT/$REPOSITORY:$TAG"
echo "🎯 Using Harbor Image: $HARBOR_IMAGE_NAME"

# Set Terraform variable
echo "🔧 Setting Terraform variables..."
TF_VAR_NAME="TF_VAR_${JOB_NAME//-/_}_image"  # Convert hyphens to underscores
export "$TF_VAR_NAME"="$HARBOR_IMAGE_NAME"
echo "✅ Set $TF_VAR_NAME=$HARBOR_IMAGE_NAME"

# Verify the image exists in Harbor (optional check)
echo "🔍 Checking if Harbor image exists..."
if docker manifest inspect "$HARBOR_IMAGE_NAME" >/dev/null 2>&1; then
    echo "✅ Harbor image exists: $HARBOR_IMAGE_NAME"
else
    echo "⚠️  Warning: Could not verify Harbor image exists (might be due to permissions)"
    echo "   Proceeding anyway - Kubernetes will attempt to pull: $HARBOR_IMAGE_NAME"
fi

# Handle Terraform deployment
echo ""
echo "🌍 Checking Terraform plan..."
terraform plan

# Auto-deploy if requested
if [ "$AUTO_DEPLOY" = "true" ]; then
    echo "🚀 Auto-deploying..."
    terraform apply -auto-approve
    echo "✅ Deployment complete!"
else
    echo ""
    echo "🎯 To deploy, run:"
    echo "   terraform apply"
    echo ""
    echo "Or use: ./deploy-only.sh $JOB_NAME $ENVIRONMENT true"
fi

echo ""
echo "📋 Summary:"
echo "  Job: $JOB_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  Harbor Image: $HARBOR_IMAGE_NAME"
echo "  Terraform Variable: $TF_VAR_NAME"