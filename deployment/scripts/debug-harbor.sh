#!/bin/bash

# Load .env from root directory
if [ -f ../../.env ]; then
    source ../../.env
else
    echo "❌ .env file not found at ../../.env"
    exit 1
fi

HARBOR_IMAGE="$HARBOR_REGISTRY/$HARBOR_PROJECT/customer-analytics:latest"

echo "🔍 Debugging Harbor image: $HARBOR_IMAGE"

# Method 1: Pull and inspect the image locally
echo ""
echo "📥 Pulling Harbor image locally..."
docker pull "$HARBOR_IMAGE"

echo ""
echo "🔍 Checking what's inside the image..."
docker run --rm "$HARBOR_IMAGE" ls -la /opt/flink/examples/streaming/

echo ""
echo "🔍 Checking what's inside the image..."
docker run --rm "$HARBOR_IMAGE" ls -la /opt/flink/usrlib/

echo ""
echo "🔍 Looking for JAR files anywhere in /opt/flink..."
docker run --rm "$HARBOR_IMAGE" find /opt/flink -name "*.jar" -type f

echo ""
echo "🔍 Checking Flink directory structure..."
docker run --rm "$HARBOR_IMAGE" ls -la /opt/flink/

echo ""
echo "🔍 Checking if there are any customer-analytics files..."
docker run --rm "$HARBOR_IMAGE" find / -name "*customer-analytics*" -type f 2>/dev/null || echo "No customer-analytics files found"