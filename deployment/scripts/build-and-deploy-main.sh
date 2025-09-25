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

# Harbor Registry Configuration - FILL THESE IN!
# HARBOUR_REGISTRY="container-registry.stholdco.com"  # REPLACE with your actual Harbor registry URL
# HARBOUR_PROJECT="technology-data-team"     # REPLACE with your actual Harbor project name

# Use environment variables from .env
HARBOUR_REGISTRY=${HARBOR_REGISTRY}
HARBOUR_PROJECT=${HARBOR_PROJECT}
REPOSITORY="$JOB_NAME"
TAG="latest"

if [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <job-name> [environment] [auto-deploy]"
    echo "Available jobs:"
    ls -d jobs/*/ | grep -v common | xargs -n 1 basename
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
    echo "Please edit the script and set real values for HARBOUR_REGISTRY and HARBOUR_PROJECT"
    exit 1
fi

JOB_DIR="jobs/$JOB_NAME"
if [ ! -d "$JOB_DIR" ]; then
    echo "Job directory $JOB_DIR not found!"
    exit 1
fi

echo "🔨 Building job: $JOB_NAME for environment: $ENVIRONMENT"

# Build common utilities first
echo "Building common utilities..."
cd jobs/common
mvn clean install -q
cd ../..

# Build the specific job
echo "Building $JOB_NAME..."
cd "$JOB_DIR"
mvn clean package -q

# Check if JAR was created
JAR_FILE="target/$JOB_NAME-1.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    exit 1
fi

# Create Dockerfile if it doesn't exist
if [ ! -f "Dockerfile" ]; then
    echo "Creating Dockerfile for $JOB_NAME..."
    cat > Dockerfile << EOF
FROM flink:1.16

# Copy the job JAR to the expected location
COPY target/$JOB_NAME-1.0.jar /opt/flink/usrlib/$JOB_NAME.jar

# Copy any additional dependencies if needed
# COPY lib/* /opt/flink/lib/
EOF
fi


# Build Docker image (local)
LOCAL_IMAGE_NAME="flink-jobs/$JOB_NAME:latest"
echo "🏗️  Building Docker image: $LOCAL_IMAGE_NAME"
docker build -t "$LOCAL_IMAGE_NAME" .

cd ../..

echo "✅ Job $JOB_NAME built successfully!"
echo "📦 Local Image: $LOCAL_IMAGE_NAME"
echo "🚀 JAR: $JOB_DIR/$JAR_FILE"

# Push to Harbor Registry
echo ""
echo "🚢 Pushing to Harbor Registry..."

# Construct Harbor image name
HARBOR_IMAGE_NAME="$HARBOUR_REGISTRY/$HARBOUR_PROJECT/$REPOSITORY:$TAG"

# Debug output
echo "🔍 Image tagging details:"
echo "  Source (local): $LOCAL_IMAGE_NAME"
echo "  Target (harbor): $HARBOR_IMAGE_NAME"
echo ""

echo "🏷️  Tagging image for Harbor..."
if docker tag "$LOCAL_IMAGE_NAME" "$HARBOR_IMAGE_NAME"; then
    echo "Successfully tagged image"
else
    echo "Failed to tag image"
    exit 1
fi

echo "📤 Pushing image to Harbor..."
if docker push "$HARBOR_IMAGE_NAME"; then
    echo "✅ Successfully pushed to Harbor: $HARBOR_IMAGE_NAME"

    # After successful push
    echo "🔧 Setting Terraform variables..."
    TF_VAR_NAME="TF_VAR_${JOB_NAME//-/_}_image"  # Convert hyphens to underscores
    export "$TF_VAR_NAME"="$HARBOR_IMAGE_NAME"
    echo "✅ Set $TF_VAR_NAME=$HARBOR_IMAGE_NAME"

else
    echo " Failed to push to Harbor registry"
    echo "Make sure you're logged in: docker login $HARBOUR_REGISTRY"
    exit 1
fi

# After successful push
# echo "🔧 Setting Terraform variables..."
# TF_VAR_NAME="TF_VAR_${JOB_NAME//-/_}_image"  # Convert hyphens to underscores
# export "$TF_VAR_NAME"="$HARBOR_IMAGE_NAME"
# echo "✅ Set $TF_VAR_NAME=$HARBOR_IMAGE_NAME"


# Now handle Terraform part - using ROOT main.tf
echo ""
echo "🌍 Checking Terraform plan..."
terraform plan

# Auto-deploy if requested
if [ "$AUTO_DEPLOY" = "true" ]; then
    echo "🚀 Auto-deploying..."
    terraform apply -auto-approve
else
    echo ""
    echo "🎯 To deploy, run:"
    echo "   terraform apply"
    echo ""
    echo "Or use: ./deployment/scripts/build-and-deploy.sh $JOB_NAME $ENVIRONMENT true"
fi