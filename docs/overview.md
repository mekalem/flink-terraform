


Your grasp of the concepts is actually quite solid - let me just correct terminology and address your specific questions.
Terminology Corrections & Clarifications
OpenShift/Kubernetes Structure:

✅ "sasktel-data-team-flink" is an OpenShift project (equivalent to a Kubernetes namespace). Both terms are correct - OpenShift calls them "projects" but they're namespaces under the hood.
Your understanding of cluster resources is spot-on:

Pods: Running containers (your actual workloads)
Services: Network endpoints to access pods (ClusterIP, NodePort, LoadBalancer types)
Deployments: Define desired state for pods and manage ReplicaSets
ReplicaSets: Ensure specified number of pod replicas are running
Routes: OpenShift-specific resource that exposes services externally (similar to Kubernetes Ingress)



Flink Deployment Modes:

✅ Application Mode vs Session Mode - you've got this right
✅ Native vs Standalone deployment:

Native mode (your choice): Flink communicates directly with Kubernetes API to dynamically request/release resources. TaskManagers appear only when jobs need them.
Standalone mode: Flink doesn't talk to Kubernetes; the operator manages all resources externally. TaskManagers run continuously whether jobs need them or not.



Your Key Questions Answered
1. Stdout/Logging Issue in Kubernetes
This is a well-known issue with Flink on Kubernetes. By default, Flink containers use console logging (log4j-console.properties), which sends output to container stdout rather than files Stack OverflowApache. You have a few options:
Solution A (Recommended): Access logs via kubectl:
bashkubectl logs -n sasktel-data-team-flink <taskmanager-pod-name> -f
Solution B: Configure log4j to write to both console and files by modifying your Flink configuration ConfigMap to include file appenders in log4j-console.properties.
Solution C: Set up log aggregation using FluentD sidecars to forward logs to S3 or CloudWatch Use monitoring configuration to monitor Flink Kubernetes operator and Flink jobs - Amazon EMR - but this is more complex.
Your print() statements go to stdout, which only appears in kubectl logs, not in the Flink UI's "Logs" tab (which shows operational logs like errors/warnings).
2. Data Not Showing in UI (0 bytes processed)
This happens when Flink optimizes your pipeline by chaining operators together. When source and sink are directly connected without transformations, Flink fuses them into one operator, so intermediate metrics don't show.
Solutions:

Add .disableChaining() to your operators
Insert .map(x -> x) or.rebalance() (as you discovered) to force separation
Add actual transformations (filter, map, etc.)

This is normal Flink behavior and not Kubernetes-specific. The desktop version may show metrics differently in its UI.
3. ML Model Inference Pipeline - Best Practices
For your NLP Flair model inference, you have two main architectural patterns:
Remote Model Inference (Recommended for Production): Keep your model server separate and have Flink make API calls to it. This approach centralizes model management, allows easy updates/versioning, and enables A/B testing without disrupting your Flink jobs Real-Time Model Inference with Apache Kafka and Flink for Predictive AI and GenAI - Kai Waehner +2.
Embedded Model Inference: Load the model directly into Flink's JVM (using libraries like Deep Java Library for Java models). This provides best latency as it's local inference with no external service calls, and avoids coupling the availability and scalability of your model with your Flink application Real-Time Model Inference with Apache Kafka and Flink for Predictive AI and GenAI - Kai Waehner.
For your use case with a Python Flair model (.pt file), I recommend Remote Model Inference:
Architecture:
CSV Source → Kafka Topic (optional) → Flink Job → HTTP Request to Model Server → Sink (Kafka/DB/S3)
Why this approach:

Your model is Python-based (Flair/PyTorch) but Flink jobs are Java - keeping them separate makes sense
You can update/retrain models without redeploying Flink jobs
You can scale model serving independently
Multiple Flink jobs can share the same model server

Your current setup with ml-model-server pods is actually correct! Don't overthink it.
4. What to Request from Your Cloud Team
Here's what you should ask for:
Storage (Choose one):

S3-compatible Object Storage (MinIO, or cloud S3): Preferred for Flink. Store:

Model artifacts (.pt files)
Checkpoints/savepoints
Job JARs
Input/output data


HDFS: Alternative, but S3 is more cloud-native

Kafka Infrastructure:

Sink topics: For your ML inference results
Source topics: If you want to stream data rather than reading CSVs
Topic configurations: Retention, partitions, replication factor

Container Registry (Harbor):

Your current setup storing Docker images in Harbor is correct
However, don't store model files in Docker images - they bloat images and require rebuilds for model updates
Store only application code in images

Correct Workflow:
1. Model Training → Save .pt to S3/MinIO
2. Build minimal model server image (just Python + dependencies)
3. Model server reads .pt from S3 at startup
4. Flink job calls model server API
5. Results go to Kafka sink topic

Configuration:
# flink-config or main.tf
state.backend: filesystem
state.checkpoints.dir: s3://your-bucket/checkpoints
state.savepoints.dir: s3://your-bucket/savepoints

Recommendations for Next Steps

Immediate: Keep your model server setup as-is, but move the .pt file from the Docker image to S3/object storage
Have model server load from S3 at startup using environment variables for the path
Create Kafka sink topic for inference results
Update requirements.txt to be as minimal as possible (only runtime dependencies)
Set up Flink state backend to S3 for checkpointing
Test end-to-end: CSV → Flink → Model Server → Kafka


1. Multiple JARs in One Flink Image - YES, You Can!
You have two main approaches:
Option A: Multi-JAR Image (Recommended for Session Mode)
Build one Flink image with all your JARs:
dockerfile# docker/base/Dockerfile
FROM flink:1.18-java11

# Copy all your job JARs to a custom directory
COPY jobs/data-ingestion-job/target/data-ingestion-*.jar /opt/flink/usrlib/
COPY jobs/ml-inference-job/target/ml-inference-*.jar /opt/flink/usrlib/
COPY jobs/analytics-job/target/analytics-*.jar /opt/flink/usrlib/

# Or copy common libraries
COPY jobs/common/target/common-*.jar /opt/flink/lib/

# Optional: Add external connectors
# RUN wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/.../flink-connector-kafka-*.jar
Then in your Terraform/FlinkDeployment config:
yamlspec:
  image: harbor.yourcompany.com/flink-platform:1.0.0
  job:
    jarURI: local:///opt/flink/usrlib/ml-inference-job.jar  # Reference by name
    # OR
    # jarURI: local:///opt/flink/usrlib/data-ingestion-job.jar
Pros:

One image for all jobs
Faster deployments (no image rebuild)
Perfect for session mode with multiple jobs
Similar to how Flink examples/ folder works

Cons:

Larger image size
All jobs get redeployed when any job changes
Less isolation between jobs

Option B: Individual Job Images (Recommended for Application Mode)
Each job gets its own image:
dockerfile# jobs/ml-inference-job/Dockerfile
FROM flink:1.18-java11

# Only this job's JAR
COPY target/ml-inference-*.jar /opt/flink/usrlib/job.jar

# Job-specific dependencies
COPY target/lib/*.jar /opt/flink/lib/
Pros:

Smallest possible images
Independent deployment cycles
Better for Application Mode (one job = one cluster)
Clear isolation and versioning

Cons:

More images to manage
Slightly more CI/CD complexity

My Recommendation for Your Setup
Based on your structure, use Option A with a hybrid approach:
dockerfile# docker/base/Dockerfile - Base image with common deps
FROM flink:1.18-java11

# Add common dependencies that ALL jobs need
COPY jobs/common/target/common-utils.jar /opt/flink/lib/
# Add Kafka connector if all jobs use it
RUN wget -P /opt/flink/lib/ https://repo.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/1.18.0/flink-sql-connector-kafka-1.18.0.jar

# Build script to copy all job JARs
COPY build-artifacts.sh /tmp/
RUN /tmp/build-artifacts.sh
Updated File Structure:
docker/
├── base/
│   ├── Dockerfile                 # Base with common deps
│   └── build-artifacts.sh         # Script to gather JARs
├── Dockerfile.multi-jar          # Multi-JAR variant
└── Dockerfile.single-job         # Template for individual jobs
Build Script Example:
bash# deployment/scripts/build-and-push.sh
#!/bin/bash

# Build all job JARs
mvn clean package -DskipTests

# Build multi-JAR Flink image
docker build \
  -t harbor.yourcompany.com/flink-platform:${VERSION} \
  -f docker/Dockerfile.multi-jar \
  .

docker push harbor.yourcompany.com/flink-platform:${VERSION}

2. PyFlink vs Java Flink for Python ML Models
Since you have a Python-based Flink model (Flair/PyTorch), let's compare:
Option 1: Keep Java Flink + Python Model Server (Current - RECOMMENDED)
Your current setup:
Java Flink Job → HTTP Request → Python Model Server → Response
Pros:

✅ Separation of concerns: Flink does data processing, Python does ML
✅ Easy model updates: Just redeploy model server, no Flink changes
✅ Better resource management: Scale model serving independently
✅ Multiple jobs can share model server
✅ Mature ecosystem: Flink's Java API is more feature-complete
✅ No major changes to your current setup

Cons:

Network latency for HTTP calls
Need to manage two separate services

Option 2: PyFlink with Embedded Model
python# jobs/ml-inference-pyflink/main.py
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.functions import MapFunction
import torch
from flair.models import SequenceClassifier

class ModelInferenceFunction(MapFunction):
    def open(self, runtime_context):
        # Load model once during initialization
        self.model = SequenceClassifier.load('s3://bucket/model.pt')
    
    def map(self, value):
        # Inference on each record
        prediction = self.model.predict(value)
        return prediction

env = StreamExecutionEnvironment.get_execution_environment()
# Add JAR dependencies for Kafka connectors
env.add_jars("file:///opt/flink/lib/flink-sql-connector-kafka.jar")

stream = env.from_source(...)  # Kafka source
stream.map(ModelInferenceFunction()) \
      .sink_to(...)  # Kafka sink
How this changes your setup:
Changes Required:

Image Changes:

dockerfile# docker/pyflink/Dockerfile
FROM flink:1.18-java11

# Install Python 3.9+
RUN apt-get update && apt-get install -y python3.9 python3-pip

# Install PyFlink
RUN pip3 install apache-flink==1.18.0

# Install your ML dependencies
COPY requirements.txt /opt/
RUN pip3 install -r /opt/requirements.txt

# Copy Python job
COPY jobs/ml-inference-pyflink/ /opt/flink/pyflink-jobs/

Terraform Changes:

yaml# In your FlinkDeployment spec
spec:
  image: harbor.yourcompany.com/flink-pyflink:1.0.0
  job:
    jarURI: local:///opt/flink/opt/python/pyflink.zip  # PyFlink runtime
    entryClass: org.apache.flink.client.python.PythonDriver
    args:
      - "-pyclientexec"
      - "/usr/bin/python3"
      - "-py"
      - "/opt/flink/pyflink-jobs/main.py"
  flinkConfiguration:
    python.executable: /usr/bin/python3

New Dependency Management:

Need to manage both Java (for Flink connectors) AND Python dependencies
Larger images (Java + Python + ML libraries)
More complex debugging


State Backend:

Need to ensure Python objects are serializable
May need custom serializers



Pros:

✅ No network calls (embedded model)
✅ Lower latency
✅ Python-native code (easier if team knows Python)
✅ Can use Python ML ecosystem directly

Cons:

❌ PyFlink is less mature than Java API
❌ Larger images (Python + Java + ML deps)
❌ Harder to update models (need to redeploy Flink jobs)
❌ More complex state management
❌ Tighter coupling between data processing and ML
❌ Resource scaling is all-or-nothing (can't scale model separately)
❌ Your current team knowledge is Java-based


My Strong Recommendation: KEEP YOUR CURRENT APPROACH
Why:

You already have it working - don't fix what isn't broken
Better architectural separation - changes to ML models don't require Flink redeployments
Independent scaling - scale model server based on inference load, scale Flink based on throughput
Easier debugging - logs are separated, easier to troubleshoot
Team knowledge - your team already knows Java Flink
Production-ready - this pattern is battle-tested at scale

Optimize your current setup instead:
java// jobs/ml-inference-job/src/main/java/InferenceJob.java
public class ModelInferenceJob {
    public static void main(String[] args) {
        StreamExecutionEnvironment env = ...;
        
        DataStream<InputRecord> input = env
            .fromSource(kafkaSource, ..., "kafka-source");
        
        // Use AsyncDataStream for non-blocking HTTP calls
        AsyncDataStream.unorderedWait(
            input,
            new AsyncModelInferenceFunction("http://ml-model-server:8000"),
            1000,  // timeout ms
            TimeUnit.MILLISECONDS,
            100    // max concurrent requests
        ).addSink(kafkaSink);
    }
}

class AsyncModelInferenceFunction 
    extends RichAsyncFunction<InputRecord, PredictionResult> {
    
    private transient AsyncHttpClient client;
    
    @Override
    public void open(Configuration parameters) {
        // Create HTTP client once
        this.client = new AsyncHttpClient();
    }
    
    @Override
    public void asyncInvoke(InputRecord input, 
                           ResultFuture<PredictionResult> resultFuture) {
        // Non-blocking HTTP call
        client.post(modelServerUrl)
              .setBody(toJson(input))
              .execute()
              .thenAccept(response -> {
                  resultFuture.complete(
                      Collections.singleton(parseResponse(response))
                  );
              });
    }
}
TL;DR:

✅ Use Option A (Multi-JAR) for your image strategy
✅ Keep Java Flink + Python Model Server architecture
❌ Don't switch to PyFlink unless you have a compelling reason
✅ Optimize with AsyncIO for better HTTP performance

Want me to create example code for the multi-JAR setup or the async HTTP inference pattern?