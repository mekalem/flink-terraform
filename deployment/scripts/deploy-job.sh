#!/bin/bash
set -e

JOB_NAME=$1
VERSION=$2
ENVIRONMENT=$3

if [[ -z "$JOB_NAME" || -z "$VERSION" || -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <job-name> <version> <environment>"
    exit 1
fi

echo "Deploying $JOB_NAME version $VERSION to $ENVIRONMENT"

# Step 1: Build the job
cd jobs/$JOB_NAME
mvn clean package -DskipTests

# Step 2: Build Docker image
docker build -t sasktel-registry/$JOB_NAME:$VERSION .

# Step 3: Push to registry
docker push sasktel-registry/$JOB_NAME:$VERSION

# Step 4: Update Terraform variable
cd ../../infrastructure
echo "${JOB_NAME}_version = \"$VERSION\"" >> environments/$ENVIRONMENT.tfvars

# Step 5: Deploy with Terraform
terraform init
terraform plan -var-file="environments/$ENVIRONMENT.tfvars"
terraform apply -var-file="environments/$ENVIRONMENT.tfvars" -auto-approve

echo "✅ $JOB_NAME deployed successfully!"