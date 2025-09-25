# Build and Deploy Script Analysis & Harbor Registry Guide

## Script Breakdown - Line by Line

### 1. Script Header & Error Handling
```bash
#!/bin/bash
set -e                    # Exit immediately if any command fails
```
**What it does**: Makes script fail-fast - if any command returns non-zero exit code, script stops.

### 2. Parameter Handling
```bash
JOB_NAME=$1              # First argument = job name (e.g., "customer-analytics")
ENVIRONMENT=${2:-dev}    # Second argument = environment, defaults to "dev"
AUTO_DEPLOY=${3:-false}  # Third argument = auto-deploy flag, defaults to "false"
```
**Usage**: `./build-and-deploy.sh customer-analytics prod true`

### 3. Input Validation
```bash
if [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <job-name> [environment] [auto-deploy]"
    echo "Available jobs:"
    ls -d jobs/*/ | grep -v common | xargs -n 1 basename
    exit 1
fi
```
**What it does**: 
- Checks if JOB_NAME is empty
- Shows usage and lists available jobs from `jobs/` directory
- Excludes `common` directory from job list

### 4. Directory Validation
```bash
JOB_DIR="jobs/$JOB_NAME"
if [ ! -d "$JOB_DIR" ]; then
    echo "Job directory $JOB_DIR not found!"
    exit 1
fi
```
**What it does**: Verifies the job directory exists before proceeding.

### 5. Build Common Dependencies
```bash
echo "Building common utilities..."
cd jobs/common
mvn clean install -q    # -q = quiet mode (less output)
cd ../..
```
**What it does**: 
- Builds shared utilities/libraries first
- Installs them to local Maven repository
- Other jobs can depend on these common components

### 6. Build Specific Job
```bash
echo "Building $JOB_NAME..."
cd "$JOB_DIR"
mvn clean package -q    # Creates JAR in target/ directory
```
**What it does**: Compiles your Java code and packages it into a JAR file.

### 7. JAR Validation
```bash
JAR_FILE="target/$JOB_NAME-1.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    exit 1
fi
```
**What it does**: Ensures the JAR was actually created by Maven build.

### 8. Dynamic Dockerfile Creation
```bash
if [ ! -f "Dockerfile" ]; then
    echo "Creating Dockerfile for $JOB_NAME..."
    cat > Dockerfile << EOF
FROM flink:1.16

# Copy the job JAR to the expected location
COPY target/$JOB_NAME-1.0.jar /opt/flink/examples/streaming/$JOB_NAME.jar

# Copy any additional dependencies if needed
# COPY lib/* /opt/flink/lib/
EOF
fi
```
**What it does**: Creates a Dockerfile if one doesn't exist, using your JAR.

### 9. Docker Image Build
```bash
IMAGE_NAME="flink-jobs/$JOB_NAME:latest"
echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" .
```
**What it does**: Builds Docker image containing your JAR + Flink runtime.

### 10. Registry Push (Currently Commented)
```bash
# echo "Pushing to registry..."
# docker push "$IMAGE_NAME"
```
**What it does**: Would push the Docker image to a registry (Harbor in your case).

## Harbor Registry - What Goes There

### ❌ WRONG: JARs don't go to Harbor
**JARs are NOT pushed to Harbor directly**

### ✅ CORRECT: Docker Images go to Harbor
**Docker images containing your JARs go to Harbor**

## Harbor Configuration Required

### 1. Update Your Script for Harbor
```bash
# Replace this line:
IMAGE_NAME="flink-jobs/$JOB_NAME:latest"

# With Harbor registry URL:
HARBOR_REGISTRY="your-harbor-url.com"
PROJECT_NAME="sasktel-flink"  # Your Harbor project
IMAGE_NAME="$HARBOR_REGISTRY/$PROJECT_NAME/$JOB_NAME:latest"
```

### 2. Enable Registry Push
```bash
# Uncomment and fix these lines:
echo "Pushing to Harbor registry..."
docker push "$IMAGE_NAME"
```

### 3. Login to Harbor (Run Once)
```bash
# Login to Harbor before first push
docker login your-harbor-url.com
# Enter your Harbor credentials
```

## Script Issues & Corrections

### 🚨 CRITICAL ISSUE: JAR Location
```bash
# ❌ WRONG in your current script:
COPY target/$JOB_NAME-1.0.jar /opt/flink/examples/streaming/$JOB_NAME.jar

# ✅ SHOULD BE:
COPY target/$JOB_NAME-1.0.jar /opt/flink/usrlib/$JOB_NAME.jar
```

**Wh