# Kafka Subscribtion
- will subscribe to Telco Cloud topics
``` bash
sip-raw
snmp-trapd2json
kafka.tools.support
freeradius-accounting
```

- some in json format, some in simple string.

## Getting started 
1. Install  `https://github.com/edenhill/kcat`

for me i did 
### Use one of the available versions
``` bash
dnf copr enable bvn13/kcat
sudo dnf copr enable bvn13/kcat centos-stream-9-x86_64
sudo dnf update
sudo dnf install kafkacat
```
2. Run in terminal to see topic data
kcat -v -b "10.228.26.81:9092" -t freeradius-accounting -C -o end

## Creating Job
1. Create the first job
make create-job JOB=sip-raw-kafka-streaming


2. Edit the generated job file, then build it
make build-job JOB=sip-raw-kafka-streaming

3. Deploy to development
make deploy-dev

4. Other topics
  
kafka.tools.support
snmp-trapd2json
sip-raw

## Job Explained
### Visual Comparison
**Simple Job Flow:**
Memory Data → DataStream → Print

**Kafka Job Flow:**
Kafka Topic → Deserialize → Handle Timing → Transform → Process → Output
    ↑            ↑            ↑            ↑         ↑        ↑
KafkaSource  StringSchema  Watermarks   MapFunction JSON    Print

Your Simple Job Imports (Minimal Setup)
javapackage com.company.jobs;

import com.company.flink.config.JobConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.datastream.DataStream;
This minimal setup works when you're doing something like:
javaenv.fromElements("Hello Flink!").print();
You're creating data from memory, so you don't need external connectors or complex processing.
Kafka Streaming Job Imports (Full External Integration)
Let me explain each import and why it's needed:
Core Flink Streaming
javaimport org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.datastream.DataStream;

StreamExecutionEnvironment: The runtime context where your job executes
DataStream: Represents the stream of data flowing through your pipeline
Same as your simple job - these are fundamental to any streaming application

Kafka Connection
javaimport org.apache.flink.connector.kafka.source.KafkaSource;

KafkaSource: The actual connector that reads from Kafka topics
Why needed: Without this, Flink has no idea how to connect to Kafka
Your simple job doesn't need this because it creates data in-memory

Data Deserialization
javaimport org.apache.flink.api.common.serialization.SimpleStringSchema;

SimpleStringSchema: Tells Flink how to convert Kafka's raw bytes into Java Strings
Why needed: Kafka stores everything as byte arrays. This converts byte[] → String
Your simple job doesn't need this because "Hello Flink!" is already a String

Offset Management
javaimport org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;

OffsetsInitializer: Controls where to start reading from Kafka

OffsetsInitializer.latest() = start from newest messages
OffsetsInitializer.earliest() = start from oldest messages
OffsetsInitializer.offsets(Map<TopicPartition, Long>) = start from specific positions


Why needed: Kafka topics have millions of messages. Where do you start?
Your simple job doesn't need this because there's no historical data

Time and Event Processing
javaimport org.apache.flink.api.common.eventtime.WatermarkStrategy;

WatermarkStrategy: Handles event-time processing and late data

WatermarkStrategy.noWatermarks() = process data as it arrives (processing time)
WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(10)) = handle events up to 10 seconds out of order


Why needed: Real-world data streams have timing complexities
Your simple job doesn't need this because in-memory data has no timing issues

Data Processing
javaimport org.apache.flink.api.common.functions.MapFunction;

MapFunction: Transform each message (1-to-1 transformation)
Why needed: We want to process/transform the Kafka messages
Your simple job might not need this if you just print without transformation

JSON Processing
javaimport org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.JsonNode;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;

JsonNode/ObjectMapper: Parse and manipulate JSON data
Why needed: Your sip-raw topic contains both JSON and string data
Your simple job doesn't need this because "Hello Flink!" isn't JSON

## Errors explains
/home/meklit/Documents/flink-terraform/jobs/sip-raw-kafka-streaming/src/main/java/com/company/jobs/SipRawKafkaStreamingJob.java:[39,64] cannot find symbol
  symbol:   class MessageProcessor
  location: class com.company.jobs.SipRawKafkaStreamingJob
- Kafka can't find class on line 39

## Uploading jar via ui

1. upload jar
2. Fill in fields
    - Entry Class: The main class with the public static void main() method
      - value: alue: com.company.jobs.SipRawKafkaStreamingJob
    - Parallelism: How many parallel instances of the job to run
      - value: start with 1, inc for performance
    - Program Arguments: Command line arguments passed to your main(String[] args) method
      - value: leave empty. This job doesn't use any command line arguments
    - Savepoint Path: Path to a previous savepoint if you want to restore from a checkpoint
      - value: leave empty,for resuming from a previous state, not needed for first run
    - Allow Non Restored State: Whether to allow starting even if some state can't be restored
      - value: Good for development/testing


So your settings should be:
Entry Class: com.company.jobs.SipRawKafkaStreamingJob
Parallelism: 1
Program Arguments: (empty)
Savepoint Path: (empty)
Allow Non Restored State: ✓ (checked)

## Check Flink Job Logs
1. Check Flink Job Logs 
``` bash
# First, find your Flink pods
kubectl get pods | grep flink

# Check TaskManager logs (where your job actually runs)
kubectl logs -f <flink-taskmanager-pod-name>

# Or check JobManager logs
kubectl logs -f <flink-jobmanager-pod-name>
```


2. Check Flink UI Metrics
In the Flink Web UI:

Click on your running job
Go to "Overview" tab
Look for "Records Received" and "Records Sent" metrics
Go to "Subtasks" tab to see individual operator metrics
Check "Backpressure" tab for any issues


3. Look for Your Actual Log Output
``` bash
# Search specifically for your job's output
kubectl logs <taskmanager-pod> | grep -E "(Raw SIP|SIP Call|JSON Message)"

# Or search for Kafka-related logs
kubectl logs <taskmanager-pod> | grep -i kafka
```


# To cancel jobs in UI:

Click on the job name (not just the row)
In the job details page, look for "Cancel" button in the top-right area
If you don't see "Cancel", the UI might be configured to hide it

## Terminal Job Management:
``` bash
# List all jobs (running and completed)
kubectl exec -it <flink-jobmanager-pod> -- flink list

# Cancel a specific job by Job ID
kubectl exec -it <flink-jobmanager-pod> -- flink cancel <job-id>

# Stop all jobs (nuclear option)
kubectl exec -it <flink-jobmanager-pod> -- flink list -r | grep "Job ID" | awk '{print $4}' | xargs -I {} flink cancel {}
```


Why You're Not Seeing UI Metrics:
Flink automatically chains your operators into one: Source: SIP Raw Kafka Source -> Map -> Sink: Print to Std. Out
Since they're all in one operator, Flink can't measure bytes between them, so the UI shows 0 bytes. This is normal and expected.

In Kubernetes/Docker deployments, Flink's web UI doesn't show TaskManager stdout by default. The print() output goes to the pod logs, not the UI.


