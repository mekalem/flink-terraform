# Flink Real-Time Streaming Platform - Technical Overview

## Table of Contents
1. [Infrastructure Overview](#infrastructure-overview)
2. [Kubernetes/OpenShift Components](#kubernetesopenshift-components)
3. [Flink Architecture & Deployment Modes](#flink-architecture--deployment-modes)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [ML Model Inference Architecture](#ml-model-inference-architecture)
6. [Known Issues & Solutions](#known-issues--solutions)
7. [Best Practices & Recommendations](#best-practices--recommendations)
8. [Next Steps & Infrastructure Needs](#next-steps--infrastructure-needs)

---

## Infrastructure Overview

### Technology Stack
- **Container Orchestration**: OpenShift (enterprise Kubernetes distribution)
- **Infrastructure as Code**: Terraform
- **Stream Processing**: Apache Flink with Kubernetes Operator
- **Message Broker**: Apache Kafka
- **Container Registry**: Harbor
- **ML Framework**: Flair (PyTorch-based NLP)

### Access & Authentication
```bash
# Login to OpenShift cluster
oc login <server-url>

# Switch to project/namespace
oc project sasktel-data-team-flink

# View all resources
kubectl get all -n sasktel-data-team-flink
```

---

## Kubernetes/OpenShift Components

### Terminology Clarification
| OpenShift Term | Kubernetes Term | Description |
|----------------|-----------------|-------------|
| **Project** | **Namespace** | Logical isolation boundary for resources |
| **Route** | **Ingress** | Exposes services externally |
| Both use same terms | Pod, Service, Deployment, ReplicaSet | Core Kubernetes resources |

### Current Deployment Resources

#### Pods (Running Containers)
```
pod/data-team-flink-5c4c767f8d-9w8z8     # JobManager (Flink coordinator)
pod/data-team-flink-taskmanager-1-2      # TaskManager (Flink worker)
pod/flink-oauth-proxy-95c575478-czr6v    # OAuth authentication proxy
pod/custom-jar-server-544c4c8f69-jr6st   # JAR file server
pod/ml-model-server-76bcbdd44b-4wdp8     # ML model inference server (replica 1)
pod/ml-model-server-76bcbdd44b-bxj67     # ML model inference server (replica 2)
```

#### Services (Network Access)
```
service/data-team-flink          # Headless service (ClusterIP: None) - for pod discovery
service/data-team-flink-rest     # Flink UI/API (ClusterIP) - port 8081
service/flink-oauth-proxy        # Auth proxy (ClusterIP) - port 8080
service/custom-jar-server        # JAR server (ClusterIP) - port 8443
service/ml-model-server          # ML inference API (ClusterIP) - port 8000
```

**ClusterIP Services**: Only accessible within the Kubernetes cluster. To access externally, use:
- **Routes** (OpenShift) or **Ingress** (Kubernetes) - expose via HTTP/HTTPS
- **Port-forwarding** - temporary local access: `kubectl port-forward service/data-team-flink-rest 8081:8081`

#### Deployments (Desired State Management)
Manages ReplicaSets and ensures specified number of pod replicas are running.

#### ReplicaSets (Pod Replication)
Ensures desired number of identical pods are running. Managed by Deployments.

#### Routes (External Access)
```
route/data-team-flink-ui    → service/data-team-flink-rest:8081
route/ml-model-api          → service/ml-model-server:8000
```

---

## Flink Architecture & Deployment Modes

### Flink Kubernetes Operator
We use **Flink Kubernetes Operator** (not native Kubernetes Flink deployment).

### Deployment Types

#### 1. Application Mode vs Session Mode

| Aspect | Application Mode | Session Mode |
|--------|------------------|--------------|
| **Relationship** | 1:1 (one cluster per job) | 1:N (one cluster, multiple jobs) |
| **Resources** | Dedicated JobManager + TaskManagers per job | Shared JobManager + TaskManagers |
| **UI** | Separate UI per job | Single shared UI |
| **Isolation** | Complete isolation | Shared resources |
| **When to use** | Production jobs, long-running | Development, multiple small jobs |
| **Visible in `kubectl get pods`** | JobManager + TaskManager pods per job | One JobManager, shared TaskManagers |

**Current Setup**: Session Mode (shared resources for multiple jobs)

#### 2. Native vs Standalone Mode

| Aspect | Native Mode (Default) ⭐ | Standalone Mode |
|--------|------------------------|-----------------|
| **Kubernetes Awareness** | Flink talks to Kubernetes API | Flink unaware of Kubernetes |
| **Resource Management** | Dynamic - Flink requests/releases resources | Static - Operator manages all resources |
| **TaskManager Allocation** | On-demand when jobs submitted | Pre-allocated, always running |
| **Idle State (no jobs)** | 0 TaskManagers, 0 slots shown | TaskManagers running, slots visible |
| **Scalability** | Automatic, flexible | Manual/Operator-controlled |
| **Best for** | Production, variable workloads | Legacy apps, fixed capacity |

**Current Setup**: Native Mode (dynamic resource allocation)

### Flink Components

```
┌─────────────────────────────────────────────────────┐
│  JobManager (Coordinator)                           │
│  - Schedules tasks                                  │
│  - Manages checkpoints                              │
│  - Provides Web UI                                  │
└─────────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌───────────┐  ┌───────────┐  ┌───────────┐
│TaskManager│  │TaskManager│  │TaskManager│
│(Worker 1) │  │(Worker 2) │  │(Worker 3) │
│           │  │           │  │           │
│ Slots: 2  │  │ Slots: 2  │  │ Slots: 2  │
└───────────┘  └───────────┘  └───────────┘
```

---

## CI/CD Pipeline

### Build Phase (Continuous Integration)

```
Source Code (Java)
    │
    ├─ mvn clean package      # Compile Java → JAR files
    │                          # Output: target/*.jar
    │
    ├─ docker build           # Build Flink image with JARs
    │   └─ Base: flink:1.18-java11
    │   └─ Add: target/*.jar → /opt/flink/usrlib/
    │
    └─ docker push            # Push to Harbor registry
        └─ harbor.company.com/flink-jobs:v1.0.0
```

### Deployment Phase (Continuous Deployment)

```
Terraform Configuration
    │
    ├─ Pulls image from Harbor
    │
    ├─ Specifies JAR path: local:///opt/flink/usrlib/job.jar
    │
    └─ terraform apply        # Deploys Flink job
        └─ Job starts running
```

### Multi-JAR Image Strategy

**Option A: Single Image with Multiple JARs** ⭐ (Recommended for Session Mode)

```dockerfile
FROM flink:1.18-java11

# Copy all job JARs
COPY jobs/data-ingestion/target/data-ingestion-1.0.jar /opt/flink/usrlib/
COPY jobs/ml-inference/target/ml-inference-1.0.jar /opt/flink/usrlib/
COPY jobs/analytics/target/analytics-1.0.jar /opt/flink/usrlib/

# Copy common dependencies
COPY jobs/common/target/common-utils.jar /opt/flink/lib/
```

**Terraform/FlinkDeployment Config:**
```yaml
spec:
  image: harbor.company.com/flink-platform:1.0.0
  job:
    jarURI: local:///opt/flink/usrlib/ml-inference-1.0.jar
    # Switch jobs by changing jarURI, no image rebuild needed
```

**Pros:**
- ✅ One image for all jobs
- ✅ Faster deployments (no rebuild for job changes)
- ✅ Similar to Flink's examples/ folder structure

**Cons:**
- ⚠️ Larger image size
- ⚠️ Less isolation

**Option B: Individual Job Images** (Better for Application Mode)
- Each job gets its own image
- Smallest images, best isolation
- More CI/CD complexity

---

## ML Model Inference Architecture

### Current Challenge: Python Model + Java Flink

Your Flair NLP model is Python-based (`.pt` file), but Flink jobs are Java.

### Architecture Options

#### Option 1: External Model Server (Current Setup) 🔄

```
┌──────────────────────────────────────────────────────┐
│ Flink Job (Java)                                     │
│   │                                                   │
│   ├─ Read from Kafka                                 │
│   ├─ Pre-process data                                │
│   ├─ HTTP Request ──────────────────┐                │
│   │                                  │                │
│   ├─ Receive prediction ◄────────────┼───┐           │
│   └─ Write to Kafka sink             │   │           │
└───────────────────────────────────────┼───┼───────────┘
                                        │   │
                                        ▼   │
                        ┌───────────────────┴───────────┐
                        │ ML Model Server (Python)      │
                        │   - Flask/FastAPI             │
                        │   - Loads model.pt from S3    │
                        │   - 2 replicas (HA)           │
                        └───────────────────────────────┘
```

**Current Resources:**
- `pod/ml-model-server-*` (2 replicas)
- `service/ml-model-server:8000`

**Pros:**
- ✅ Separation of concerns (data processing vs ML)
- ✅ Easy model updates (no Flink restart)
- ✅ Independent scaling
- ✅ Multiple jobs can share model

**Cons:**
- ❌ More operational overhead (2 services to manage)
- ❌ Network latency (HTTP calls)
- ❌ Additional infrastructure

**When to Use:**
- Model changes frequently (weekly/monthly)
- Multiple different models needed
- ML team manages models separately
- Need A/B testing

#### Option 2: Embedded Model with ONNX ⭐ (Recommended)

```
┌──────────────────────────────────────────────────────┐
│ Flink TaskManager (Java)                             │
│   │                                                   │
│   ├─ Model loaded from S3 at startup (ONNX)          │
│   ├─ Model cached in memory                          │
│   │                                                   │
│   ├─ Read from Kafka                                 │
│   ├─ Pre-process data                                │
│   ├─ Local inference (no network call)               │
│   └─ Write to Kafka sink                             │
└──────────────────────────────────────────────────────┘
```

**Setup:**
```python
# One-time: Convert Flair .pt → ONNX
import torch
from flair.models import SequenceClassifier

model = SequenceClassifier.load('model.pt')
torch.onnx.export(model, dummy_input, "model.onnx")
# Upload model.onnx to S3
```

```java
// Flink job loads ONNX model
import ai.onnxruntime.*;

public class ModelFunction extends RichMapFunction<Input, Output> {
    private transient OrtSession session;
    
    @Override
    public void open(Configuration config) {
        // Load model ONCE per TaskManager
        byte[] modelBytes = loadFromS3("s3://bucket/model.onnx");
        session = env.createSession(modelBytes);
    }
    
    @Override
    public Output map(Input input) {
        // Fast local inference
        return session.run(input);
    }
}
```

**What This Eliminates:**
- ❌ No `ml-model-server` pods needed
- ❌ No separate Python deployment
- ❌ No HTTP networking overhead

**Pros:**
- ✅ **Simpler operations** (one thing to manage)
- ✅ Better latency (no network)
- ✅ True end-to-end Flink processing
- ✅ Model still updatable (load from S3)

**Cons:**
- ⚠️ One-time ONNX conversion effort
- ⚠️ Model updates need job restart (no rebuild)
- ⚠️ Each TaskManager loads model (more memory)

**When to Use:**
- Stable models (changes quarterly)
- Single pipeline needs model
- Want operational simplicity
- Latency is critical

#### Option 3: PyFlink with Native Python Model

Full Python stack - both Flink and model in Python.

**Pros:**
- ✅ Native Python (no Java)
- ✅ Direct model usage

**Cons:**
- ❌ PyFlink less mature than Java API
- ❌ Larger images (Python + Java + ML libs)
- ❌ Team already knows Java Flink
- ❌ More complex debugging

**Recommendation**: Only if team prefers Python over Java

### Decision Matrix

| Criteria | External Server | Embedded ONNX | PyFlink |
|----------|----------------|---------------|---------|
| **Operational Simplicity** | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Model Update Frequency** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Latency** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Team Familiarity** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Resource Efficiency** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |

**Recommended Path**: Start with **Embedded ONNX**, move to external server only if frequent model updates needed.

---

## Known Issues & Solutions

### Issue 1: TaskManager stdout Not Visible in UI

**Problem**: `print()` statements don't appear in Flink Web UI logs.

**Root Cause**: Flink on Kubernetes uses console logging (`log4j-console.properties`), which sends output to container stdout, not log files. UI shows operational logs only.

**Solutions:**

**A. Access via kubectl** (Easiest)
```bash
kubectl logs -n sasktel-data-team-flink pod/data-team-flink-taskmanager-1-2 -f
```

**B. Configure File Logging**
Modify `log4j-console.properties` in ConfigMap:
```properties
log4j.rootLogger=INFO, console, file
log4j.appender.file=org.apache.log4j.RollingFileAppender
log4j.appender.file.File=/opt/flink/log/taskmanager.log
```

**C. Log Aggregation** (Production)
- Use FluentD sidecars to forward logs to S3/CloudWatch
- Requires additional setup

### Issue 2: Metrics Show 0 Bytes Processed

**Problem**: Simple source→sink jobs show working but 0 bytes in UI.

**Root Cause**: Flink **operator chaining** optimization. When operators can run in the same thread, they're fused together, so intermediate metrics aren't tracked separately.

**Solutions:**

**A. Disable Chaining**
```java
dataStream
    .map(new MyMapper())
    .disableChaining()  // Force separate operator
    .addSink(kafkaSink);
```

**B. Add Transformations**
```java
dataStream
    .map(x -> x)  // Identity function forces separation
    .addSink(kafkaSink);

// Or use rebalance (redistributes data)
dataStream
    .rebalance()
    .addSink(kafkaSink);
```

**C. Accept It**
- This is normal Flink optimization behavior
- Desktop Flink may show metrics differently
- Focus on job-level metrics instead

---

## Best Practices & Recommendations

### Docker Image Strategy

**✅ DO:**
```dockerfile
FROM flink:1.18-java11

# Application JARs
COPY jobs/**/target/*.jar /opt/flink/usrlib/

# Common libraries
COPY common-libs/*.jar /opt/flink/lib/

# Models loaded at runtime from S3, NOT baked in
ENV MODEL_S3_PATH=s3://bucket/models/
```

**❌ DON'T:**
```dockerfile
# Bad: Embedding large model files
COPY model.pt /opt/flink/models/  # Makes image huge!
COPY requirements.txt .            # Python deps in Java image
RUN pip install -r requirements.txt
```

### State Backend Configuration

```yaml
# In Terraform/FlinkDeployment
flinkConfiguration:
  state.backend: filesystem
  state.checkpoints.dir: s3://your-bucket/checkpoints
  state.savepoints.dir: s3://your-bucket/savepoints
  execution.checkpointing.interval: 60s
```

### Async I/O for External Calls

If keeping external model server:

```java
// Use AsyncDataStream for non-blocking HTTP calls
AsyncDataStream.unorderedWait(
    inputStream,
    new AsyncModelInferenceFunction("http://ml-model-server:8000"),
    1000,  // timeout ms
    TimeUnit.MILLISECONDS,
    100    // max concurrent requests
).addSink(sink);
```

### Resource Management

**For ML Inference Jobs:**
```yaml
taskManager:
  resource:
    memory: "4096m"  # More memory for model loading
    cpu: 2
  
jobManager:
  resource:
    memory: "2048m"
    cpu: 1
```

---

## Next Steps & Infrastructure Needs

### Immediate Requests for Cloud Team

#### 1. Object Storage (S3-compatible)
**Purpose**: Store models, checkpoints, and data

**Request:**
```
- S3 bucket: s3://sasktel-flink-platform/
  - /models/          # ML model artifacts
  - /checkpoints/     # Flink state checkpoints
  - /savepoints/      # Flink savepoints
  - /jars/            # Optional: job JARs
  - /data/            # Input/output data

- Access:
  - Service account: sasktel-data-team-flink
  - Permissions: Read/Write
  - Mount to Flink pods via environment variables or IRSA
```

#### 2. Kafka Topics
**Purpose**: Data streaming sources and sinks

**Request:**
```
Topics needed:
- input-data-topic         (source for raw data)
- ml-inference-results     (sink for predictions)
- dlq-errors              (dead letter queue)

Configuration per topic:
- Partitions: 6 (start with, scale later)
- Replication factor: 3
- Retention: 7 days (adjust per use case)
- Compression: lz4
```

#### 3. Harbor Registry Cleanup
**Request:**
```
- Create repository: flink-platform/jobs
- Implement image retention policy (keep last 10 versions)
- Remove large unnecessary images (e.g., ones with embedded models)
```

#### 4. Monitoring & Logging
**Optional but Recommended:**
```
- Prometheus for metrics collection
- Grafana dashboards for Flink metrics
- ELK/Loki for log aggregation
```

### Development Roadmap

#### Phase 1: Simplify ML Pipeline (Week 1-2)
1. Convert Flair model to ONNX format
2. Test ONNX inference locally
3. Build POC with embedded model in Flink
4. Compare performance vs external server

#### Phase 2: Production Setup (Week 3-4)
1. Set up S3 backend for checkpoints/models
2. Configure Kafka topics
3. Implement error handling and monitoring
4. Deploy to staging environment

#### Phase 3: Optimization (Week 5-6)
1. Tune parallelism and resources
2. Add metrics and alerting
3. Document operational procedures
4. Prepare for production launch

### Decision Point: Model Serving Architecture

**Quick Assessment:**

| Question | Answer | Recommendation |
|----------|--------|----------------|
| Model size < 500MB? | Yes/No | If Yes → Embedded ONNX |
| Model updates < monthly? | Yes/No | If Yes → Embedded ONNX |
| Multiple teams need model? | Yes/No | If Yes → External Server |
| Need A/B testing? | Yes/No | If Yes → External Server |
| Team prefers simplicity? | Yes/No | If Yes → Embedded ONNX |

**Default Recommendation**: Start with **Embedded ONNX** for operational simplicity.

---

## Quick Reference Commands

### OpenShift/Kubernetes
```bash
# View all resources
kubectl get all -n sasktel-data-team-flink

# Watch pods in real-time
kubectl get pods -n sasktel-data-team-flink -w

# View logs
kubectl logs -f pod/data-team-flink-taskmanager-1-2

# Port forward to Flink UI
kubectl port-forward service/data-team-flink-rest 8081:8081

# Execute into pod
kubectl exec -it pod/data-team-flink-5c4c767f8d-9w8z8 -- /bin/bash

# Describe resource
kubectl describe pod data-team-flink-taskmanager-1-2
```

### Flink Operations
```bash
# Submit job via CLI
./bin/flink run -d /opt/flink/usrlib/my-job.jar

# List running jobs
./bin/flink list

# Cancel job
./bin/flink cancel <job-id>

# Trigger savepoint
./bin/flink savepoint <job-id> s3://bucket/savepoints/
```

### Docker/Harbor
```bash
# Build image
docker build -t harbor.company.com/flink-platform:1.0.0 .

# Push to registry
docker push harbor.company.com/flink-platform:1.0.0

# Pull image
docker pull harbor.company.com/flink-platform:1.0.0
```

---

## Glossary

| Term | Definition |
|------|------------|
| **JobManager** | Flink coordinator that schedules tasks and manages state |
| **TaskManager** | Flink worker that executes tasks |
| **Task Slot** | Unit of parallelism; each TaskManager has multiple slots |
| **Operator Chaining** | Optimization where operators run in same thread |
| **Checkpoint** | Periodic snapshot of job state for fault tolerance |
| **Savepoint** | Manual snapshot for job upgrades or migrations |
| **Backpressure** | Automatic slowdown when downstream can't keep up |
| **Watermark** | Timestamp tracking for event-time processing |
| **ClusterIP** | Kubernetes service type for internal cluster access |
| **Route** | OpenShift resource for external HTTP/HTTPS access |
| **Harbor** | Enterprise container registry (Docker registry) |

---

## Additional Resources

- **Flink Documentation**: https://nightlies.apache.org/flink/flink-docs-stable/
- **Flink Kubernetes Operator**: https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-stable/
- **OpenShift Documentation**: https://docs.openshift.com/
- **ONNX Runtime**: https://onnxruntime.ai/
- **Terraform Flink Provider**: (if using custom provider)

---

**Document Version**: 1.0  
**Last Updated**: October 2025  
**Owner**: SaskTel Data Team  
**Status**: Active Development