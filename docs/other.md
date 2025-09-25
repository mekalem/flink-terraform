# How Jobs Actually Get Deployed
Method 1: Direct JAR Submission (Traditional)
``` bash
# On your machine:
mvn clean package  # Creates target/your-job.jar

# Submit to cluster:
kubectl cp target/your-job.jar data-team-flink-xxx:/tmp/
kubectl exec data-team-flink-xxx -- flink run /tmp/your-job.jar
```

Method 2: Kubernetes Job (Modern/Production)
``` bash
# Your code becomes a Docker image:
docker build -t registry/customer-analytics:v1.0 .

# Kubernetes creates a separate pod that:
# 1. Runs your containerized job
# 2. Submits itself to the Flink cluster
# 3. JobManager schedules it on TaskManagers
```


# Flink Kubernetes Operator Production Deployment Guide
You have the Flink Kubernetes Operator running (not native Kubernetes Flink), 
This is NOT standard Kubernetes - this is the Flink Kubernetes Operator!

## What You Have Now (Application Mode)

``` hcl
# Your current Terraform - Application Mode
resource "kubernetes_manifest" "flink_deployment" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"    # ← This is the Flink Operator CR
    # ... rest of your config
  }
}
```
## Understanding Your Architecture

    ┌─────────────────────────────────────────────────────────────────┐
│                    Flink Kubernetes Operator                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              FlinkDeployment CR                           │  │
│  │  ┌─────────────────┐    ┌─────────────────────────────┐  │  │
│  │  │   JobManager    │    │      TaskManagers           │  │  │
│  │  │   (Master)      │    │  ┌─────┐ ┌─────┐ ┌─────┐   │  │  │
│  │  │                 │    │  │ TM1 │ │ TM2 │ │ TMn │   │  │  │
│  │  └─────────────────┘    │  └─────┘ └─────┘ └─────┘   │  │  │
│  │                         └─────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

## Production Deployment Options
**Option 1:** Application Mode (Current - Recommended for Production)
Each job = Separate FlinkDeployment = Separate Flink cluster
Advantages:

-  Complete isolation between jobs
- Independent scaling per job
- Fault tolerance - one job crash doesn't affect others
- Easy resource management
- Production best practice

Your Code Structure Should Be:
infrastructure/
├── flink-deployments/
│   ├── data-team-flink.tf        # Current example job
│   ├── customer-analytics.tf     # Your new job
│   ├── ml-inference.tf           # Future job
│   └── analytics-pipeline.tf     # Future job

**Option 2:** Session Mode (Multiple jobs, one cluster)
One FlinkDeployment + Multiple FlinkSessionJobs


# Recommended Production Approach: Application Mode
Step 1: Create Your Job's FlinkDeployment
Create infrastructure/flink-deployments/customer-analytics.tf:

Step 2: Docker Image Strategy
Your job needs to be packaged into a Docker image:

``` dockerfile
# jobs/customer-analytics/Dockerfile
FROM flink:1.16

# Copy your compiled JAR
COPY target/customer-analytics-*.jar /opt/flink/usrlib/customer-analytics.jar

# Copy any additional dependencies
COPY target/lib/*.jar /opt/flink/usrlib/

# Copy configuration files
COPY src/main/resources/*.properties /opt/flink/conf/

# Set up any environment variables
ENV FLINK_CLASSPATH=/opt/flink/usrlib/*
```

# Flink Execution Model:
**source code gets COMPILED → PACKAGED → SUBMITTED as jobs**

1. Inside the JobManager Container Explained

``` bash
kubectl exec -it data-team-flink-6ff747d4c7-vxvzw -n sasktel-data-team-flink -- bash
```
- Running the command above means you've entered the JobManager container, which contains:
/opt/flink/          ← Standard Flink installation
├── bin/            ← Flink CLI tools (flink run, flink list, etc.)
├── lib/            ← Flink runtime libraries  
├── conf/           ← Cluster configuration
├── log/            ← Runtime logs
└── examples/       ← Sample Flink jobs

/opt/java/          ← Java runtime (JVM)

2. The Real Flow: Source Code → Running Job

Your Local Machine                    Kubernetes Cluster
┌─────────────────────┐              ┌──────────────────────────────────┐
│                     │              │                                  │
│ jobs/               │              │  JobManager Container            │
│ ├── customer-       │   BUILD &    │  ┌─────────────────────────────┐ │
│ │   analytics/      │   PACKAGE    │  │ /opt/flink/                 │ │
│ │   ├── src/        │      →       │  │ ├── bin/ (flink CLI)        │ │
│ │   ├── pom.xml     │   SUBMIT     │  │ ├── lib/ (runtime libs)     │ │
│ │   └── Dockerfile  │      →       │  │ └── conf/ (config)          │ │
│ └── ...             │   EXECUTE    │  └─────────────────────────────┘ │
│                     │              │                                  │
└─────────────────────┘              │  Your Job Pods                  │
                                     │  ┌─────────────────────────────┐ │
                                     │  │ customer-analytics-xxx      │ │
                                     │  │ (Your compiled JAR runs     │ │
                                     │  │  here as separate pod)      │ │
                                     │  └─────────────────────────────┘ │
                                     └──────────────────────────────────┘


                                     # Flink Kubernetes Operator vs Native Kubernetes Flink

## The Fundamental Difference

### What You Have: Flink Kubernetes Operator
```yaml
apiVersion: flink.apache.org/v1beta1  # ← This tells you it's the OPERATOR
kind: FlinkDeployment                 # ← Custom Resource managed by operator
```

### What You DON'T Have: Native Kubernetes Flink
```yaml
apiVersion: apps/v1                   # ← Standard Kubernetes
kind: Deployment                      # ← Regular Kubernetes Deployment
```

## Architecture Comparison

### 1. Flink Kubernetes Operator (What You Have)
```
FlinkSessionJob Custom Resources (CR)
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │            Flink Kubernetes Operator                   │    │
│  │              (Control Plane)                           │    │
│  │                                                         │    │
│  │  Watches FlinkDeployment CRs                           │    │
│  │  Creates/Manages Flink Clusters                        │    │
│  │  Handles Upgrades/Scaling                              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                FlinkDeployment CR                       │    │
│  │   ┌─────────────┐    ┌─────────────────────────────┐   │    │
│  │   │ JobManager  │    │      TaskManagers           │   │    │
│  │   │   (Pod)     │    │   ┌─────┐ ┌─────┐ ┌─────┐   │   │    │
│  │   │             │    │   │ Pod │ │ Pod │ │ Pod │   │   │    │
│  │   └─────────────┘    │   └─────┘ └─────┘ └─────┘   │   │    │
│  │                      └─────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Native Kubernetes Flink (What You DON'T Have)
```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Standard Kubernetes Resources              │    │
│  │                                                         │    │
│  │  ┌─────────────┐    ┌─────────────────────────────┐    │    │
│  │  │ Deployment  │    │         Deployment          │    │    │
│  │  │(JobManager) │    │     (TaskManagers)          │    │    │
│  │  │             │    │                             │    │    │
│  │  │  ┌─────┐    │    │   ┌─────┐ ┌─────┐ ┌─────┐   │    │    │
│  │  │  │ Pod │    │    │   │ Pod │ │ Pod │ │ Pod │   │    │    │
│  │  │  └─────┘    │    │   └─────┘ └─────┘ └─────┘   │    │    │
│  │  └─────────────┘    └─────────────────────────────┘    │    │
│  │                                                         │    │
│  │  + Services + ConfigMaps + Secrets + ...               │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Key Differences

### Management Level

#### Flink Kubernetes Operator (Your Setup)
```yaml
# You write HIGH-LEVEL declarations:
spec:
  job:
    jarURI: "local:///path/to/job.jar"
    parallelism: 8
    upgradeMode: "savepoint"
  taskManager:
    resource:
      memory: "4096m"
      cpu: 2
```
**The operator handles everything else automatically!**

#### Native Kubernetes Flink
```yaml
# You must write LOW-LEVEL Kubernetes resources:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-jobmanager
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: jobmanager
        image: flink:1.16
        command: ["/docker-entrypoint.sh", "jobmanager"]
        env:
        - name: JOB_MANAGER_RPC_ADDRESS
          value: "flink-jobmanager"
        # ... hundreds of lines of configuration
---
apiVersion: apps/v1
kind: Deployment  
metadata:
  name: flink-taskmanager
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: taskmanager
        image: flink:1.16
        command: ["/docker-entrypoint.sh", "taskmanager"]
        # ... more configuration
---
# Plus Services, ConfigMaps, Secrets, etc.
```

## Feature Comparison

| Feature | Flink Operator | Native Kubernetes |
|---------|---------------|-------------------|
| **Setup Complexity** | ⭐ Simple | ⭐⭐⭐⭐⭐ Complex |
| **Job Deployment** | `kubectl apply flinkdeployment.yaml` | Manual JAR submission |
| **Scaling** | Automatic | Manual |
| **Upgrades** | Savepoint-based | Manual |
| **Monitoring** | Built-in | Custom setup |
| **High Availability** | Automatic | Manual setup |
| **Resource Management** | Declarative | Imperative |
| **Production Readiness** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐ Requires expertise |

## What This Means for Your Workflow

### With Flink Operator (Your Current Setup)
```bash
# 1. Create FlinkDeployment YAML
# 2. Apply it
kubectl apply -f customer-analytics-flinkdeployment.yaml

# The operator automatically:
# ✅ Creates JobManager pod
# ✅ Creates TaskManager pods  
# ✅ Configures networking
# ✅ Submits    