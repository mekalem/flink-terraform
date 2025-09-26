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


When Debugging Jobs not running in Session mode
- don't see task manager or slots listed (this is fine, it happens and doens't show anything if no streaming job / job is utilizing taskmanager)
1. Check the Session Cluster Status First
Before jobs can run, the session cluster needs to be ready:
``` bash

kubectl get flinkdeployment data-team-flink -n sasktel-data-team-flink
```
Make sure the jobManagerDeploymentStatus is READY (which your Terraform waits for).
If its shows `deployed` its not the same, cause job manager has conditions
``` hcl
  wait {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
```

In that case, lets run deeper debug
``` bash
kubectl describe flinkdeployment data-team-flink -n sasktel-data-team-flink
```
check for `  Job Manager Deployment Status:  DEPLOYING`
The jobManagerDeploymentStatus is showing DEPLOYING instead of READY. This means your session cluster isn't fully started yet, which is why your session jobs aren't running.

wait for it to be `Job Manager Deployment Status:  READY`

Let's check what's happening with the actual pods:
``` bash
kubectl get pods -n sasktel-data-team-flink
```

If the session cluster is READY and the JobManager pod is running. Let's check if your session jobs are running:
``` bash
kubectl get flinksessionjob -n sasktel-data-team-flink
``` bash
sasktel-data-team-flink
NAME                JOB STATUS   LIFECYCLE STATE
state-machine-job                UPGRADING
word-count-job                   UPGRADING

```
This should show you the status of your two jobs

If session cluster is ready but if the session jobs aren't showing up or aren't running, we can describe them to see what's happening:
``` bash
kubectl describe flinksessionjob state-machine-job -n sasktel-data-team-flink
kubectl describe flinksessionjob word-count-job -n sasktel-data-team-flink
```

For example: one issue was 
`Could not find a file system implementation for scheme 'local'. The scheme is not directly supported by Flink and no Hadoop file system to support this scheme could be loaded. For a full list of supported file systems, please see https://nightlies.apache.org/flink/flink-docs-stable/ops/filesystems/. -> Hadoop is not in the classpath/dependencies.`

local:// is not supported in this Flink setup. The error message clearly states that Flink can't find a file system implementation for the 'local' scheme.

First, let's see what's in the Flink examples directory:
``` bash
kubectl exec -it data-team-flink-86f7769d46-qm55h -n sasktel-data-team-flink -- ls -la /opt/flink/examples/
```

or get inside jobmanager container 
``` bash
kubectl exec -it data-team-flink-86f7769d46-qm55h -n sasktel-data-team-flink -- bash
```

so I upgraded Terraform to use regular file paths instead of local://:

But if there still an issu with the path not found check if the path is accessable in general 
``` bash
kubectl exec -it data-team-flink-86f7769d46-qm55h -n sasktel-data-team-flink -- find /opt/flink -name "*.jar" | grep -i example
```
Then
Let's verify the JAR is accessible from within the pod:
``` bash
kubectl exec -it data-team-flink-86f7769d46-qm55h -n sasktel-data-team-flink -- ls -la /opt/flink/examples/streaming/StateMachineExample.jar
```

if it shows something like 
``` bash
-rw-r--r--. 1 flink flink 5427101 Nov 13  2023 /opt/flink/examples/streaming/StateMachineExample.jar
``` 
access is working

TRy
1. Delete the stuck session jobs and recreate them:
``` bash
kubectl delete flinksessionjob state-machine-job word-count-job -n sasktel-data-team-flink
```
2. then recreate
``` bash
terraform apply
```

1. Check if there are multiple pods or if the pod changed:
bashkubectl get pods -n sasktel-data-team-flink
2. Let's check the JAR from the current pod again:
bash# Get the current pod name
JOBMANAGER_POD=$(kubectl get pods -n sasktel-data-team-flink -l component=jobmanager -o jsonpath='{.items[0].metadata.name}')
echo "Checking pod: $JOBMANAGER_POD"

# Check if the JAR exists
kubectl exec -it $JOBMANAGER_POD -n sasktel-data-team-flink -- ls -la /opt/flink/examples/streaming/WordCount.jar
3. Check TaskManager pod as well:
bash# Check if there's a TaskManager pod
kubectl get pods -n sasktel-data-team-flink -l component=taskmanager

Issue might be no taskmanager pod running
``` bash
 kubectl get pods -n sasktel-data-team-flink
NAME                                 READY   STATUS    RESTARTS   AGE
data-team-flink-86f7769d46-qm55h     1/1     Running   0          55m
flink-oauth-proxy-5448fdfdb4-s5kdf   1/1     Running   0          61m
```
we sohuld see one more.
1. Check why TaskManager isn't starting:
``` bash
kubectl describe flinkdeployment data-team-flink -n sasktel-data-team-flink
```
check for any TaskManage related errors

2. Check for any TaskManager-related events or failed deployments:

``` bash
kubectl get events -n sasktel-data-team-flink --sort-by='.lastTimestamp' | tail -20
```

3. Check if there are any ReplicaSets or Deployments for TaskManager:
``` bash
kubectl get deployments,replicasets -n sasktel-data-team-flink
```

atm The FlinkDeployment shows TaskManager: Replicas: 1 in the spec, but there's no TaskManager pod running, and there's no TaskManager deployment or replicaset. This is unusual - normally in session mode, TaskManagers should start automatically.

Delete Existing session cluster
```bash
kubectl delete flinkdeployment data-team-flink -n sasktel-data-team-flink
```


## SEE NOTES
Warning  Error   4m34s (x13 over 18m)  Job   /opt/flink/examples/streaming/WordCount.jar (No such file or directory)
ok so lets leave it in default mode which is native and i think i know issues, whe i describe the jobs, i see this issue, so both local:///opt or /opt don't work in session moe but local worked in application mode, what is the issue this doesn;t work even though ive cheked with bash the jobmanager has this file and can acccess it?You've identified the key issue! The difference between application mode and session mode is crucial here:

In Application Mode: The JAR file is accessible because it's part of the same pod where the job runs.
In Session Mode: The FlinkSessionJob needs to submit the JAR to the session cluster, but the way JAR files are handled is different. The session cluster JobManager needs to be able to access the JAR file to distribute it to TaskManagers.


In FlinkSessionJob, the jarURI can contain remote sources and leverages the Flink filesystem mechanism to download the JAR and submit to the session cluster. The download of the JAR happens in the flink-kubernetes-operator pod ApacheStack Overflow. The operator will upload the user JAR first and then call the JobManager to build the JobGraph FLIP-215: Introduce FlinkSessionJob CRD in the kubernetes operator - Apache Flink - Apache Software Foundation.
The Problem: In session mode, the Flink Operator needs to download/access the JAR file to upload it to the session cluster, not the session cluster pods themselves. The operator pod doesn't have access to the local JAR files in your session cluster pods.


Option 1: Use HTTP URLs for JAR files (Easiest)
Option 2: Build Custom Image with JAR
Option 3: Use File Server/Object Storage


# Delete the deployment (this will remove the pod)
kubectl delete deployment jar-server -n sasktel-data-team-flink

# Also delete the service
kubectl delete service jar-server -n sasktel-data-team-flink

# Or if you used Terraform, remove those resources from your .tf file and run:
terraform apply

The difference between those two names is:

resource "kubernetes_manifest" "flink_session_cluster" - This is the Terraform resource name. It's just an identifier within your Terraform configuration so you can reference this resource elsewhere (like in depends_on).
name = "data-team-flink" - This is the actual Kubernetes resource name that gets created in the cluster. This is what other Kubernetes resources will reference.

Your configuration will work perfectly! Here's what happens:

Terraform creates: A Kubernetes FlinkDeployment named data-team-flink
FlinkSessionJob references: deploymentName = "data-team-flink" (the Kubernetes name, not the Terraform resource name)

This is exactly right. The FlinkSessionJob's deploymentName field must match the metadata.name of the session cluster, which is data-team-flink