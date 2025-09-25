#!/bin/bash

set -e

JOB_NAME=$1
ENVIRONMENT=${2:-dev}
AUTO_DEPLOY=${3:-false}

if [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <job-name> [environment] [auto-deploy]"
    echo "Available jobs:"
    ls -d jobs/*/ | grep -v common | xargs -n 1 basename
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
COPY target/$JOB_NAME-1.0.jar /opt/flink/jobs/$JOB_NAME.jar

# Copy any additional dependencies if needed
# COPY lib/* /opt/flink/lib/
EOF
fi

# Build Docker image
IMAGE_NAME="flink-jobs/$JOB_NAME:latest"
echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" .

# Push to registry (uncomment when you have a registry)
# echo "Pushing to registry..."
# docker push "$IMAGE_NAME"

cd ../..

echo "✅ Job $JOB_NAME built successfully!"
echo "📦 Image: $IMAGE_NAME"
echo "🚀 JAR: $JOB_DIR/$JAR_FILE"

# Now handle Terraform part
cd infrastructure

echo "🔍 Checking Terraform plan..."
terraform plan -var-file="environments/$ENVIRONMENT.tfvars"

# Auto-deploy if requested
if [ "$AUTO_DEPLOY" = "true" ]; then
    echo "🚀 Auto-deploying..."
    terraform apply -var-file="environments/$ENVIRONMENT.tfvars" -auto-approve
else
    echo ""
    echo "🎯 To deploy, run:"
    echo "   cd infrastructure"
    echo "   terraform apply -var-file=\"environments/$ENVIRONMENT.tfvars\""
    echo ""
    echo "Or use: ./deployment/scripts/build-and-deploy.sh $JOB_NAME $ENVIRONMENT true"
fi