## File Structure
flink-data-platform/
├── infrastructure/
│   │   └── environments/
│   ├── main.tf                    # Your existing Terraform
│   ├── variables.tf               # Terraform variables
│   ├── outputs.tf                 # Terraform outputs
│   └── terraform.tfvars           # Environment-specific values
├── jobs/
│   ├── common/                    # Shared utilities
│   │   ├── pom.xml               # Common dependencies
│   │   └── src/main/java/com/company/flink/
│   │       ├── config/           # Configuration classes
│   │       ├── serializers/      # Custom serializers
│   │       ├── sources/          # Custom sources
│   │       ├── sinks/            # Custom sinks
│   │       └── utils/            # Utility classes
│   ├── data-ingestion-job/       # Example job 1
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   └── src/main/java/com/company/jobs/
│   ├── ml-inference-job/         # Example job 2
│   │   ├── pom.xml
│   │   ├── Dockerfile
│   │   └── src/main/java/com/company/jobs/
│   └── analytics-job/            # Example job 3
│       ├── pom.xml
│       ├── Dockerfile
│       └── src/main/java/com/company/jobs/
├── deployment/
│   ├── job-templates/            # Kubernetes/Flink job templates
│   │   ├── base-job-template.yaml
│   │   └── job-config-template.yaml
│   ├── scripts/                  # Deployment scripts
│   │   ├── build-and-deploy.sh
│   │   ├── create-job.sh
│   │   └── update-job.sh
│   └── configs/                  # Environment configs
│       ├── dev.yaml
│       ├── staging.yaml
│       └── prod.yaml
├── docker/
│   ├── base/
│   │   └── Dockerfile            # Base Flink image with common deps
│   └── registry/                 # Container registry configs
├── docs/
│   ├── job-development.md
│   ├── deployment-guide.md
│   └── troubleshooting.md
├── .github/workflows/            # CI/CD pipelines
│   ├── build-jobs.yml
│   └── deploy-jobs.yml
├── Makefile                      # Common commands
├── README.md
└── .gitignore

## Getting Started Process
### Step A: First, build the common module properly
``` bash
# Build common utilities (this provides shared code to all jobs)
cd jobs/common
mvn clean install
cd ../..
```

###  Step B: Create / Update your analytics-job pom.xml to use the common module
### Step C: Build and run your analytics-job
``` bash
# Build your specific job (this will use the common module)
cd jobs/analytics-job
mvn clean package

# Check the JAR was created
ls -la target/analytics-job-1.0.0.jar
```
### Step D: Access Flink and deploy
``` bash
# Login to OpenShift
oc login <your-cluster-url>

# Check Flink is running
oc get pods -n sasktel-data-team-flink

You should see something like:
NAME                                 READY   STATUS    RUNNING
flink-oauth-proxy-xxxxx              1/1     Running
data-team-flink-xxxxx                1/1     Running

# Get Flink UI URL
oc get routes -n sasktel-data-team-flink
```
This should show you a URL like https://flink-ui-data-team-flink.apps.your-cluster.com



oc expose svc flink-oauth-proxy --name=flink-ui --port=8080 -n sasktel-data-team-flink

route.route.openshift.io/flink-ui exposed

oc delete route flink-ui -n sasktel-data-team-flink

route.route.openshift.io "flink-ui" deleted

oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink
oc port-forward svc/customer-analytics-rest 8082:8081 -n sasktel-data-team-flink

kubectl get services -n sasktel-data-team-flink


ps aux | grep 'oc port-forward'
kill <pid>

# Then deploy only the customer analytics job
terraform apply -target=kubernetes_manifest.customer_analytics_deployment

## Running

# Test the Makefile
make help

# Create your first job
make create-job JOB=customer-analytics

# Edit the generated job file, then build it
make build-job JOB=customer-analytics

# Deploy to development
make deploy-dev

## Troubleshooting 
# Make the scripts executable
``` bash
chmod +x deployment/scripts/create-job.sh
chmod +x deployment/scripts/build-and-deploy.sh
chmod +x deployment/scripts/update-job.sh
```


 terraform apply -var-file="infrastructure/environments/dev.tfvars"

# Deployment Types
1. Application Mode (Each JAR = Separate FlinkDeployment) 
- **Setup**
    - What we have now - each job gets its own dedicated Flink cluster
    - SIMPLEST: Just Add Another FlinkDeployment
    - FlinkDeployment #1: data-team-flink (runs StateMachineExample.jar)
    - FlinkDeployment #2: customer-analytics (runs customer-analytics.jar)
    - Each has its own JobManager + TaskManagers
- **Resources**:
    - 2 separate Flink clusters
    - Each job is completely isolated
    - If one crashes, the other keeps running

# How to RUN with custom 

2 separate setup
The infrastructure directory setup looks more sophisticated and is designed to use the variables from dev.tfvars. Let me explain what's happening and give you the best path forward.
What's Happening

**Root main.tf:** Hard-coded values, works but not scalable
**Infrastructure setup:** Uses variables, designed for multiple environments, but currently disconnected from your actual FlinkDeployment

Terraform will automatically detect the new resource when you run terraform plan

Step 1: Add the Code to `main.tf`
Step 2: Check What Terraform Will Do
``` bash
cd infrastructure
terraform plan -var-file="environments/dev.tfvars"
```
you should see something like 
``` bash
Plan: 1 to add, 0 to change, 0 to destroy.
```
Step 3: Apply the Changes
``` bash
terraform apply -var-file="environments/dev.tfvars"
```

2. Session Mode (Multiple JARs = One Cluster + Multiple Jobs) -> One shared Flink cluster that runs multiple jobs



## Debug
1. Cannot create resource that already exists
Delete from Kubernetes directly (Quick)
``` bash
kubectl delete flinkdeployment customer-analytics -n sasktel-data-team-flink
```

# Kubernetes Resources
# List all FlinkDeployments
kubectl get flinkdeployments -n sasktel-data-team-flink

# List all FlinkSessionJobs (if using session mode)
kubectl get flinksessionjobs -n sasktel-data-team-flink

# List both together
kubectl get flinkdeployments,flinksessionjobs -n sasktel-data-team-flink

# More detailed view
kubectl get flinkdeployments,flinksessionjobs -n sasktel-data-team-flink -o wide

# All resources in the namespace
kubectl get all -n sasktel-data-team-flink

# Terraform State
# List all resources Terraform is managing
terraform state list

# Show detailed state
terraform show

# Show just the Flink resources
terraform state list | grep flink

# Quick Satus CHeck
# See what's actually running
kubectl get pods -n sasktel-data-team-flink

# Check if your customer-analytics is there
kubectl get flinkdeployment customer-analytics -n sasktel-data-team-flink


# Delete the Crashing Pod
# Delete the customer-analytics FlinkDeployment
kubectl delete flinkdeployment customer-analytics -n sasktel-data-team-flink

# Verify it's gone
kubectl get flinkdeployments -n sasktel-data-team-flink

# Debug Why It's Crashing
Before recreating, let's see what went wrong:
# Check the logs of the crashed pod
kubectl logs customer-analytics-896bdf8f-d479b -n sasktel-data-team-flink

# If there are multiple containers, check the jobmanager specifically
kubectl logs customer-analytics-896bdf8f-d479b -c flink-main-container -n sasktel-data-team-flink

# Check events for more details
kubectl describe pod customer-analytics-896bdf8f-d479b -n sasktel-data-team-flink

Most Likely Issues

JAR not found: The local:///opt/flink/jobs/customer-analytics.jar doesn't exist in the container
Wrong image: You're using base flink:1.16 instead of your custom image flink-jobs/customer-analytics:latest


# Check What's in the Flink Container
# Get into your working Flink JobManager
kubectl exec -it data-team-flink-6ff747d4c7-vxvzw -n sasktel-data-team-flink -- bash    

Once you're inside the container, run:
# Check the examples directory (where your working JAR is)
ls -la /opt/flink/examples/streaming/

# Check if the jobs directory exists
ls -la /opt/flink/jobs/

# Find all JAR files in the container
find /opt/flink -name "*.jar" -type f

# Check other common locations
ls -la /opt/flink/lib/
ls -la /opt/flink/usrlib/



# TO DEBUG CRASH
Check pods status 
``` bash
kubectl get pods -n sasktel-data-team-flink
```
Returns
``` bash
NAME                                 READY   STATUS             RESTARTS     AGE
customer-analytics-896bdf8f-lknbb    0/1     CrashLoopBackOff   4 (4s ago)   2m3s
data-team-flink-6ff747d4c7-vxvzw     1/1     Running            0            5d21h
data-team-flink-taskmanager-1-1      1/1     Running            0            5d21h
flink-oauth-proxy-6d7cff5fb6-24zs6   1/1     Running            0            10d
```

- This means it errored out and kubernetes tried restarting it 4 times

Get the pod name and check logs of namespace 
``` bash
kubectl logs customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink
```

- I see logs say 
`Caused by: java.io.IOException: JAR file does not exist '/opt/flink/examples/streaming/customer-analytics.jar'`




Debugging Steps (Do These NOW)
Step 1: Get the Crash Logs
bash# Get current logs
kubectl logs customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink

# If pod restarted, get previous logs
kubectl logs customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink --previous

# Get detailed pod info
kubectl describe pod customer-analytics-896bdf8f-lknbb -n sasktel-data-team-flink
Step 2: Check FlinkDeployment Status
bashkubectl get flinkdeployment customer-analytics -n sasktel-data-team-flink -o 


# Step-by-Step Docker Rebuild and Verification
1. Rebuild the Docker Image

``` bash
# You're already in jobs/customer-analytics/, so run:
docker build -t flink-jobs/customer-analytics:latest .
```

2. Verify the JAR is in the Correct Location
``` bash
# Check if the JAR file exists in the image at the expected path
docker run --rm flink-jobs/customer-analytics:latest ls -la /opt/flink/examples/streaming/
```

expected ouput 
total 12345
drwxr-xr-x 2 flink flink    4096 Dec 15 10:30 .
drwxr-xr-x 3 flink flink    4096 Dec 15 10:30 ..
-rw-r--r-- 1 root root 12345678 Dec 15 10:30 customer-analytics.jar  ← This should be there



# CrashLoopBackOff

## Quick fixes to try:
docker images | grep customer-analytics


# CI/CD Pipeline Players
.env                           (SOURCE OF TRUTH)
 ↓
build-script.sh               (CI - Build & Push)
 ↓
main.tf                       (CD - Deploy)
 ↑
variables.tf                  (Variable Definitions)
 ↑
environments/dev.tfvars       (Environment Values)


What Each File Does:
1. .env = 🎯 SINGLE SOURCE OF TRUTH
**Purpose:** One place to change all common config

2. build-script.sh = 🔨 CI (Continuous Integration)
**Purpose:**
Reads .env
Builds JAR → Docker image → Pushes to Harbor
Sets Terraform variables from .env
Yes, this IS the CI pipeline!

3. main.tf = 🚀 CD (Continuous Deployment)
**Purpose:** The actual deployment definitions

``` hcl
resource "kubernetes_manifest" "customer_analytics" {
  manifest = {
    spec = {
      image = var.customer_analytics_image  # Gets value from variables
    }
  }
}
```

4. infrastructure/variables.tf = 📋 VARIABLE DEFINITIONS
**Purpose:** "These variables CAN be used" (the template)

``` tf
variable "harbor_registry" {
  description = "Harbor registry URL"
  type        = string
}
```

5. environments/dev.tfvars = ⚙️ ENVIRONMENT-SPECIFIC VALUES
**Purpose:** "These are the values I WANT for dev environment"
``` hcl
namespace = "sasktel-data-team-flink"
parallelism = 2
memory = "2048m"
```

Change .env → Run build script → Terraform uses those values → Deploys
project-root/
├── .env                           # 🎯 Source of truth
├── main.tf                        # 🚀 Deployment
├── build-and-deploy.sh            # 🔨 CI/CD script  
├── infrastructure/
│   └── variables.tf               # 📋 Variable definitions
└── environments/
    ├── dev.tfvars                 # ⚙️ Dev values
    ├── qa.tfvars                  # ⚙️ QA values  
    └── prod.tfvars                # ⚙️ Prod values