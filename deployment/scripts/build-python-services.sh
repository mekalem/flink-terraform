#!/bin/bash

set -e

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)
    echo "Environment variables loaded"
else
    echo ".env file not found! Please create one with your Harbor configuration."
    echo "Example .env file:"
    echo "HARBOR_REGISTRY=your-harbor-url.com"
    echo "HARBOR_PROJECT=your-project-name"
    echo "NAMESPACE=sasktel-data-team-flink"
    exit 1
fi

# Use environment variables from .env
HARBOUR_REGISTRY=${HARBOR_REGISTRY}
HARBOUR_PROJECT=${HARBOR_PROJECT}
TAG="latest"

# Build and push model server
echo "Building Model Server..."
cd services/model-server
docker build -t ml-model-server:local .

HARBOR_IMAGE="$HARBOUR_REGISTRY/$HARBOUR_PROJECT/ml-model-server:$TAG"
echo "Tagging: $HARBOR_IMAGE"
docker tag ml-model-server:local "$HARBOR_IMAGE"

echo "Pushing to Harbor..."
docker push "$HARBOR_IMAGE"
echo "Model Server pushed: $HARBOR_IMAGE"

# # Build and push data generator
# echo ""
# echo "Building Data Generator..."
# cd ../data-generator
# docker build -t data-generator:local .

# HARBOR_IMAGE="$HARBOUR_REGISTRY/$HARBOUR_PROJECT/data-generator:$TAG"
# echo "Tagging: $HARBOR_IMAGE"
# docker tag data-generator:local "$HARBOR_IMAGE"

# echo "Pushing to Harbor..."
# docker push "$HARBOR_IMAGE"
# echo "Data Generator pushed: $HARBOR_IMAGE"

# echo ""
# echo "All Python services built and pushed!"
# echo "Model Server: $HARBOUR_REGISTRY/$HARBOUR_PROJECT/ml-model-server:$TAG"
# echo "Data Generator: $HARBOUR_REGISTRY/$HARBOUR_PROJECT/data-generator:$TAG"