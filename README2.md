# Flink Data Platform

A Terraform-managed Apache Flink deployment on OpenShift/Kubernetes for stream processing workloads.

## Table of Contents

- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Deployment](#deployment)
- [Working with Jobs](#working-with-jobs)
- [Common Commands](#common-commands)
- [Debugging & Troubleshooting](#debugging--troubleshooting)
- [Architecture Patterns](#architecture-patterns)
- [ML Inference Setup](#ml-inference-setup)

---

## Project Structure

```
flink-data-platform/
├── infrastructure/
│   ├── environments/
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── prod.tfvars
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
├── jobs/
│   ├── common/                    # Shared utilities
│   │   ├── pom.xml
│   │   └── src/main/java/com/company/flink/
│   │       ├── config/
│   │       ├── serializers/
│   │       ├── sources/
│   │       ├── sinks/
│   │       └── utils/
│   ├── data-ingestion-job/
│   ├── ml-inference-job/
│   └── analytics-job/
├── services/
│   ├── model-server/             # Python FastAPI service
│   └── data-generator/           # Python Kafka producer
├── deployment/
│   ├── job-templates/
│   ├── scripts/
│   └── configs/
├── docker/
│   ├── base/
│   └── registry/
├── .env                          # Source of truth for config
├── Makefile
└── README.md
```

---

## Getting Started

### Prerequisites

- OpenShift/Kubernetes cluster access
- Terraform installed
- Maven 3.6+
- Docker
- kubectl/oc CLI tools

### Initial Setup

#### Step 1: Build Common Module

The common module provides shared utilities for all Flink jobs.

```bash
cd jobs/common
mvn clean install
cd ../..
```

#### Step 2: Build Your Job

```bash
cd jobs/analytics-job
mvn clean package

# Verify JAR was created
ls -la target/analytics-job-1.0.0.jar
```

#### Step 3: Login to OpenShift

```bash
# Login to OpenShift cluster
oc login <your-cluster-url>

# Check Flink is running
oc get pods -n sasktel-data-team-flink

# Get Flink UI URL
oc get routes -n sasktel-data-team-flink
```

#### Step 4: Port Forward to Flink UI

```bash
# Port forward to JobManager
oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink

# Access UI at: http://localhost:8081
```

---

## Deployment

### Deployment Types

#### 1. Application Mode (Each JAR = Separate FlinkDeployment)

- Each job gets its own dedicated Flink cluster
- Complete isolation between jobs
- If one crashes, others keep running

```
FlinkDeployment #1: data-team-flink (runs StateMachineExample.jar)
FlinkDeployment #2: customer-analytics (runs customer-analytics.jar)
```

#### 2. Session Mode (Multiple JARs = One Cluster + Multiple Jobs)

- One shared Flink cluster running multiple jobs
- More resource efficient
- Jobs share JobManager and TaskManagers

### Terraform Deployment

#### Using Environment Files

```bash
# Plan deployment
cd infrastructure
terraform plan -var-file="environments/dev.tfvars"

# Apply deployment
terraform apply -var-file="environments/dev.tfvars"

# Deploy specific resource
terraform apply -target=kubernetes_manifest.customer_analytics_deployment
```

#### Using Custom Variables Script

```bash
# Deploy using Makefile
make dev-deploy

# This internally runs:
terraform apply -var-file="infrastructure/environments/dev.tfvars"
```

### Configuration Hierarchy

```
.env                           # Source of truth
 ↓
build-script.sh               # CI - Build & Push
 ↓
main.tf                       # CD - Deploy
 ↑
variables.tf                  # Variable definitions
 ↑
environments/dev.tfvars       # Environment values
```

---

## Working with Jobs

### Viewing Running Jobs

```bash
# Method 1: Using Flink CLI
kubectl exec -it pod/data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  /opt/flink/bin/flink list

# Method 2: Using REST API
kubectl port-forward service/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink
curl http://localhost:8081/jobs/overview

# Method 3: Check Flink UI
# Access http://localhost:8081 after port-forward
```

### Canceling Jobs

```bash
# Recommended: Using Flink CLI
kubectl exec -it pod/data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  /opt/flink/bin/flink cancel <JOB_ID>

# With savepoint (safe cancellation)
kubectl exec -it pod/data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  /opt/flink/bin/flink cancel -s s3://bucket/savepoints <JOB_ID>

# Using REST API
curl -X PATCH http://localhost:8081/jobs/<JOB_ID>?mode=cancel

# Nuclear option: Restart JobManager
kubectl delete pod data-team-flink-<pod-id> -n sasktel-data-team-flink
```

### Viewing Job Logs

#### TaskManager Logs (Job Output)

```bash
# Real-time logs (recommended)
kubectl logs -f pod/data-team-flink-taskmanager-1-2 -n sasktel-data-team-flink

# Last 100 lines
kubectl logs pod/data-team-flink-taskmanager-1-2 -n sasktel-data-team-flink --tail=100

# Filter by job name
kubectl logs -f pod/data-team-flink-taskmanager-1-2 -n sasktel-data-team-flink | grep "SIP Call Counter"

# Filter by job ID
kubectl logs -f pod/data-team-flink-taskmanager-1-2 -n sasktel-data-team-flink | grep "3a7b9c2d"

# Search for errors
kubectl logs pod/data-team-flink-taskmanager-1-2 -n sasktel-data-team-flink | grep -i "error\|exception"
```

#### JobManager Logs (Job Submission)

```bash
# Follow JobManager logs
kubectl logs -f pod/data-team-flink-<pod-id> -n sasktel-data-team-flink

# Last 100 lines
kubectl logs pod/data-team-flink-<pod-id> -n sasktel-data-team-flink --tail=100
```

#### Filter Logs by Specific Output

```bash
kubectl logs -f $(kubectl get pods -n sasktel-data-team-flink -l component=taskmanager -o name | head -1) \
  -n sasktel-data-team-flink | grep -E "RAW-EVENTS|FILTERED-CALLS|WITH-PREFIX"
```

---

## Common Commands

### Kubernetes Resources

```bash
# List all FlinkDeployments
kubectl get flinkdeployments -n sasktel-data-team-flink

# List all FlinkSessionJobs
kubectl get flinksessionjobs -n sasktel-data-team-flink

# List both
kubectl get flinkdeployments,flinksessionjobs -n sasktel-data-team-flink

# Detailed view
kubectl get flinkdeployments,flinksessionjobs -n sasktel-data-team-flink -o wide

# All resources in namespace
kubectl get all -n sasktel-data-team-flink

# Check pods status
kubectl get pods -n sasktel-data-team-flink

# Check services
kubectl get services -n sasktel-data-team-flink

# Check storage classes
kubectl get storageclass
```

### Terraform State

```bash
# List all managed resources
terraform state list

# Show detailed state
terraform show

# Show Flink resources only
terraform state list | grep flink
```

### Port Forwarding

```bash
# Forward JobManager REST API
oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink

# Forward customer analytics
oc port-forward svc/customer-analytics-rest 8082:8081 -n sasktel-data-team-flink

# Kill port forward processes
ps aux | grep 'oc port-forward'
kill <pid>
```

### Docker Commands

```bash
# Build Docker image
docker build -t flink-jobs/customer-analytics:latest .

# Verify image
docker images | grep customer-analytics

# Check JAR in image
docker run --rm flink-jobs/customer-analytics:latest ls -la /opt/flink/examples/streaming/

# Find JARs in container
docker run --rm flink-jobs/customer-analytics:latest find /opt/flink -name "*.jar" -type f
```

### Make Commands

```bash
# Show available commands
make help

# Create new job
make create-job JOB=customer-analytics

# Build job
make build-job JOB=customer-analytics

# Deploy to development
make deploy-dev
```

---

## Debugging & Troubleshooting

### Understanding Pod Status

When you run `kubectl get pods`, you'll see output like:

```
NAME                                 READY   STATUS             RESTARTS     AGE
customer-analytics-896bdf8f-lknbb    0/1     CrashLoopBackOff   4 (4s ago)   2m3s
data-team-flink-6ff747d4c7-vxvzw     1/1     Running            0            5d21h
```

**Column Meanings:**
- **READY**: `0/1` means 0 out of 1 containers are ready
- **STATUS**: Current state (Running, CrashLoopBackOff, Pending, etc.)
- **RESTARTS**: Number of times pod has restarted (indicates crashes)
- **AGE**: How long pod has been running

### Common Errors & Solutions

#### 1. CrashLoopBackOff

**Symptoms:**
- Pod shows `CrashLoopBackOff` status
- RESTARTS count keeps increasing

**Debug Steps:**

```bash
# Check current logs
kubectl logs customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink

# Check previous logs (if restarted)
kubectl logs customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink --previous

# Get detailed pod info
kubectl describe pod customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink

# Check events
kubectl get events -n sasktel-data-team-flink --sort-by='.lastTimestamp' | tail -20
```

**Common Causes:**
- JAR file not found in container
- Wrong image used
- Missing dependencies
- Configuration errors

#### 2. JAR File Not Found

**Error Message:**
```
java.io.IOException: JAR file does not exist '/opt/flink/examples/streaming/customer-analytics.jar'
```

**Solution:**

```bash
# Verify JAR exists in container
kubectl exec -it data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  ls -la /opt/flink/examples/streaming/

# Find all JARs in container
kubectl exec -it data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  find /opt/flink -name "*.jar" -type f

# Check if specific JAR is accessible
kubectl exec -it data-team-flink-<pod-id> -n sasktel-data-team-flink -- \
  ls -la /opt/flink/examples/streaming/StateMachineExample.jar
```

#### 3. Resource Already Exists

**Error Message:**
```
Error: resource already exists
```

**Solution:**

```bash
# Delete from Kubernetes
kubectl delete flinkdeployment customer-analytics -n sasktel-data-team-flink

# Verify deletion
kubectl get flinkdeployments -n sasktel-data-team-flink

# Reapply with Terraform
terraform apply -var-file="environments/dev.tfvars"
```

#### 4. Session Mode: Jobs Not Running

**Symptoms:**
- Session cluster shows `DEPLOYING` instead of `READY`
- Jobs stuck in `UPGRADING` state

**Debug Steps:**

```bash
# Check session cluster status
kubectl get flinkdeployment data-team-flink -n sasktel-data-team-flink

# Detailed cluster status
kubectl describe flinkdeployment data-team-flink -n sasktel-data-team-flink

# Check session jobs
kubectl get flinksessionjob -n sasktel-data-team-flink

# Describe specific job
kubectl describe flinksessionjob state-machine-job -n sasktel-data-team-flink
```

**Wait for READY status:**
```bash
# JobManager should show READY
# Look for: Job Manager Deployment Status: READY
kubectl describe flinkdeployment data-team-flink -n sasktel-data-team-flink
```

#### 5. No TaskManager Running

**Symptoms:**
- Only JobManager pod exists
- No TaskManager pod in `kubectl get pods`

**Debug Steps:**

```bash
# Check if TaskManager should exist
kubectl describe flinkdeployment data-team-flink -n sasktel-data-team-flink

# Look for TaskManager replicas in spec
# Should show: Task Manager: Replicas: 1

# Check for deployments
kubectl get deployments,replicasets -n sasktel-data-team-flink

# Check events
kubectl get events -n sasktel-data-team-flink --sort-by='.lastTimestamp'
```

**Solution:**
```bash
# Delete and recreate session cluster
kubectl delete flinkdeployment data-team-flink -n sasktel-data-team-flink
terraform apply
```

#### 6. Local:// File System Not Supported

**Error Message:**
```
Could not find a file system implementation for scheme 'local'
```

**Problem:**
- `local://` URLs don't work in session mode
- Session mode requires JAR to be downloadable by Flink operator

**Solutions:**

```bash
# Option 1: Use absolute path (not local://)
# In Terraform: jarURI = "/opt/flink/examples/streaming/StateMachineExample.jar"

# Option 2: Use HTTP server
# In Terraform: jarURI = "http://jar-server:8443/StateMachineExample.jar"

# Option 3: Switch to Application Mode
# Use FlinkDeployment instead of FlinkSessionJob
```

#### 7. Session Mode JAR Access Issues

**Problem:**
- In session mode, the Flink operator pod downloads JARs, not the session cluster
- The operator pod doesn't have access to JARs in your custom image

**Why local:// works in Application Mode but not Session Mode:**

```
Application Mode:
JAR is in the same pod → local:// works ✓

Session Mode:
Operator downloads JAR → Submits to cluster
Operator can't access local:// in session pods ✗
```

**Solutions:**

1. **HTTP Server (Recommended)**
   - Deploy JAR server as sidecar
   - Use `http://jar-server:8443/your-job.jar`

2. **Harbor Registry**
   - Upload JARs to Harbor
   - Configure operator to download from Harbor

3. **Switch to Application Mode**
   - Each job gets dedicated cluster
   - JAR built into image

### Checking Container Contents

```bash
# Get shell access to JobManager
kubectl exec -it data-team-flink-<pod-id> -n sasktel-data-team-flink -- bash

# Once inside container:
ls -la /opt/flink/examples/streaming/
ls -la /opt/flink/jobs/
ls -la /opt/flink/lib/
find /opt/flink -name "*.jar" -type f
```

### Rebuilding Docker Images

```bash
# Rebuild image
cd jobs/customer-analytics/
docker build -t flink-jobs/customer-analytics:latest .

# Verify JAR location
docker run --rm flink-jobs/customer-analytics:latest \
  ls -la /opt/flink/examples/streaming/

# Expected output should show your JAR file
```

### Finding JobManager and TaskManager Pods

```bash
# Get JobManager pod name
JOBMANAGER_POD=$(kubectl get pods -n sasktel-data-team-flink \
  -l component=jobmanager -o jsonpath='{.items[0].metadata.name}')
echo "JobManager: $JOBMANAGER_POD"

# Get TaskManager pod name
TASKMANAGER_POD=$(kubectl get pods -n sasktel-data-team-flink \
  -l component=taskmanager -o jsonpath='{.items[0].metadata.name}')
echo "TaskManager: $TASKMANAGER_POD"

# Use these in commands
kubectl logs -f $JOBMANAGER_POD -n sasktel-data-team-flink
kubectl logs -f $TASKMANAGER_POD -n sasktel-data-team-flink
```

### Script Permissions

If deployment scripts fail with permission errors:

```bash
chmod +x deployment/scripts/create-job.sh
chmod +x deployment/scripts/build-and-deploy.sh
chmod +x deployment/scripts/update-job.sh
chmod +x deployment/scripts/deploy.sh
chmod +x build-python-services.sh
```

---

## Architecture Patterns

### Application vs Session Mode

**When to Use Application Mode:**
- Production jobs requiring isolation
- Jobs with different resource requirements
- Critical jobs that need dedicated resources

**When to Use Session Mode:**
- Development and testing
- Multiple similar jobs
- Resource-constrained environments

### Naming Convention

In Terraform, there are two types of names:

```hcl
# Terraform resource name (internal to Terraform)
resource "kubernetes_manifest" "flink_session_cluster" {
  
  # Kubernetes resource name (what gets created in cluster)
  metadata = {
    name = "data-team-flink"
  }
}
```

**Important:** FlinkSessionJob references use the Kubernetes name:

```hcl
resource "kubernetes_manifest" "session_job" {
  spec = {
    deploymentName = "data-team-flink"  # ← Kubernetes name, not Terraform resource name
  }
}
```

---

## ML Inference Setup

### Architecture

```
┌─────────────────┐
│ Data Generator  │ → Kafka Topic (npl_input_stream)
│    (Pod)        │
└─────────────────┘
         ↓
┌─────────────────┐     ┌──────────────────┐
│  Flink ML Job   │ ←calls→ │  Model Server    │
│    (FlinkDep)   │     │     (Pod)        │
└─────────────────┘     └──────────────────┘
         ↓                       ↓
   Kafka Topic            ┌──────────────────┐
(ml_predictions)          │  Model Storage   │
                          │  (PVC or S3)     │
                          └──────────────────┘
```

### Three Separate Images

1. **Flink Job Image (Java)**
   - Based on `flink:1.18`
   - Contains ML job JAR
   - Processes streams and calls model server

2. **Model Server Image (Python)**
   - Based on `python:3.10`
   - FastAPI web server
   - Loads and serves ML model

3. **Data Generator Image (Python)**
   - Based on `python:3.9`
   - Produces test data to Kafka

### Building Python Services

```bash
cd services/model-server/

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Test locally
python main.py

# Test in another terminal
curl http://localhost:8000/health
curl http://localhost:8000/test

# Build Docker image
docker build -t harbor.yourcompany.com/ml-model-server:latest .
docker push harbor.yourcompany.com/ml-model-server:latest
```

### Storage Setup

```bash
# Check available storage classes
oc get storageclass

# Common output:
# dell-powerstore-block (default) - Block storage
# dell-powerstore-nfs             - NFS storage
```

**Storage Class Features:**
- **RECLAIMPOLICY: Delete** - Storage deleted when PVC deleted
- **WaitForFirstConsumer** - Volume created when pod scheduled
- **ALLOWVOLUMEEXPANSION: true** - Can resize PVC later

### Accessing Model Server

```bash
# Check service
kubectl get svc ml-model-server -n sasktel-data-team-flink

# Port forward (for testing)
kubectl port-forward svc/ml-model-server 8000:8000 -n sasktel-data-team-flink

# Access FastAPI docs
# http://localhost:8000/docs

# Test prediction
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"text": "test message", "note_type": "TECHNICAL SUPPORT", "can": "7110347"}'
```

### Why Separate Services?

The model server provides:
- **Load balancing** across replicas
- **Health awareness** (only sends to healthy pods)
- **Stable endpoint** (DNS name doesn't change)
- **Request queuing** handled by Kubernetes
- **Automatic failover** if pod crashes

Without the service, your Flink job would need to:
- Track individual pod IPs
- Implement retry logic
- Detect unhealthy pods
- Manually distribute load

---

## Additional Resources

### File Locations

- **Flink Examples**: `/opt/flink/examples/`
- **Flink Libraries**: `/opt/flink/lib/`
- **User Libraries**: `/opt/flink/usrlib/`
- **Job JARs**: `/opt/flink/jobs/` or `/opt/flink/examples/streaming/`

### Useful Links

- [Flink Documentation](https://nightlies.apache.org/flink/flink-docs-stable/)
- [Flink Kubernetes Operator](https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-stable/)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)

### Environment Variables

Check `.env` file for:
- Harbor registry URL
- Image tags
- Resource limits
- Parallelism settings
- Memory configurations

---

## Quick Reference

### Most Used Commands

```bash
# Check everything
kubectl get all -n sasktel-data-team-flink

# View job list
kubectl exec -it <jobmanager-pod> -n sasktel-data-team-flink -- /opt/flink/bin/flink list

# Follow logs
kubectl logs -f <pod-name> -n sasktel-data-team-flink

# Port forward UI
oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink

# Deploy
terraform apply -var-file="environments/dev.tfvars"

# Delete resource
kubectl delete flinkdeployment <name> -n sasktel-data-team-flink
```