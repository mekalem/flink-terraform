# SIP Call Anomaly Detection - Implementation Guide

## Overview

This guide explains how to implement real-time anomaly detection on SIP call data using Apache Flink, converting your Splunk query into a streaming analytics job.

## Use Case: Telecom Fraud Detection

**Problem**: Detect abnormal international calling patterns that may indicate:
- SIP trunk fraud/hijacking
- Toll fraud attacks
- Compromised credentials
- Bot-driven call patterns

**Your Splunk Query (Simplified)**:
```splunk
| eval CNshort=substr(callingNumber,1,4)
| timechart span=5m count by CNshort
| streamstats window=12 mean(Calls) as rolling_average
| eval deviation = Calls - rolling_average
| streamstats window=12 stdev(deviation) as rolling_deviation
| eval threshold = 3 * rolling_deviation
| where Calls > upper_bound AND Calls > 10
```

**Translation to Flink**:
1. Extract country code prefix (first 4 chars)
2. Count calls in 5-minute tumbling windows
3. Maintain 12-window (60 min) rolling statistics per prefix
4. Calculate mean and standard deviation
5. Flag anomalies: calls > (mean + 3*stddev) AND calls > 10

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Kafka Topic: sip-raw                                        │
│   {"from_address": "+86...", "to_address": "+1...", ...}   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Flink Job: SIP Anomaly Detection                            │
│                                                              │
│  1. Parse JSON                                              │
│  2. Filter (Terminating, International, VoLTE)              │
│  3. Extract Country Prefix (e.g., "+123")                   │
│  4. Window: 5-minute tumbling windows                       │
│  5. Count: Calls per prefix per window                      │
│  6. KeyedProcessFunction: Per-prefix rolling stats          │
│     - Maintain last 12 windows (60 minutes)                 │
│     - Calculate: mean, stddev                               │
│     - Detect: calls > (mean + 3*stddev) && calls > 10      │
│  7. Output: Anomaly alerts                                  │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Kafka Topic: sip-anomalies                                  │
│   {"country_prefix": "+86", "calls": 150,                   │
│    "rolling_average": 45.2, "is_anomaly": true, ...}       │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Model

### Input (Kafka sip-raw topic)
```json
{
    "from_address": "+861234567890",
    "from_country_dialing_code": 86,
    "from_country_code": "CN",
    "from_country": "China",
    "from_location": "Beijing",
    "to_address": "+12345678901",
    "to_country_dialing_code": 1,
    "to_country": "USA",
    "to_country_code": "US",
    "to_location": "New York",
    "call_id": "abc-123-def",
    "capture_zone": "zone1",
    "direction": "Terminating",
    "service_provider": "volte-provider-1"
}
```

### Output (Kafka sip-anomalies topic)
```json
{
    "country_prefix": "+861",
    "calls": 150,
    "prev_calls": 45,
    "rolling_average": 42.5,
    "rolling_deviation": 12.3,
    "threshold": 36.9,
    "upper_bound": 79.4,
    "is_anomaly": true,
    "timestamp": 1704567890000,
    "severity": "CRITICAL"
}
```

---

## Windowing Strategy

### Why Event Time vs Processing Time?

**Event Time** (Recommended for Production):
- Uses timestamp from the event itself
- Handles out-of-order events correctly
- Accurate for historical replay
- **Use when**: Events have timestamps, order matters

**Processing Time** (Easier for Testing):
- Uses wall-clock time when Flink processes event
- Simpler to implement
- **Use when**: Quick prototyping, timestamps unreliable

### Window Types Explained

| Window Type | Description | Your Use Case |
|-------------|-------------|---------------|
| **TUMBLING** | Fixed, non-overlapping | ✅ YES - Count calls every 5 minutes |
| **SLIDING/HOP** | Overlapping windows | ⚠️ Could use for smoother detection |
| **SESSION** | Gap-based (activity bursts) | ❌ No - need fixed intervals |
| **CUMULATE** | Growing windows | ❌ No - need rolling windows |

**Chosen**: **Tumbling Event Time Windows of 5 minutes**

```java
.window(TumblingEventTimeWindows.of(Time.minutes(5)))
```

---

## Statistical Anomaly Detection

### Algorithm: Z-Score / Standard Deviation Method

Distance-based anomaly detection where new data points are classified based on how dissimilar they are from past observations, using statistical measures like standard deviation.

```
For each country prefix (e.g., "+861"):
  1. Maintain rolling window: last 12 call counts (60 minutes)
     Example: [45, 42, 48, 50, 43, 46, 44, 47, 49, 45, 43, 150]
  
  2. Calculate Mean (μ):
     μ = (45 + 42 + ... + 150) / 12 = 54.3
  
  3. Calculate Standard Deviation (σ):
     σ = sqrt(Σ(xi - μ)² / n) = 28.4
  
  4. Set Threshold:
     threshold = 3 * σ = 85.2
     upper_bound = μ + threshold = 139.5
  
  5. Detect Anomaly:
     IF current_calls > upper_bound AND current_calls > 10
     THEN anomaly = true
     
     150 > 139.5 AND 150 > 10  →  ✅ ANOMALY!
```

### Why 3 Standard Deviations?

- **1σ**: 68% of data falls within (too sensitive)
- **2σ**: 95% of data falls within (moderate)
- **3σ**: 99.7% of data falls within (rare events only) ← **Your choice**

Adjust based on false positive tolerance.

---

## Implementation Phases

### Phase 1: Simple Counter (Testing) ✅

**Goal**: Verify data ingestion and basic windowing

```java
// Count calls per prefix every 5 minutes
stream
  .map(json -> extractPrefix(json))
  .keyBy(prefix -> prefix)
  .window(TumblingProcessingTimeWindows.of(Time.minutes(5)))
  .sum(1)
  .print();
```

**Test**:
```bash
# Should print something like:
(+861, 45)
(+447, 32)
(+861, 150)  ← spike!
```

### Phase 2: Add Filtering (Your Splunk Filters)

```java
.filter(call -> 
    call.direction.equals("Terminating") &&
    !call.fromAddress.startsWith("+1") &&
    call.fromAddress.startsWith("+") &&
    call.serviceProvider.startsWith("volte")
)
```

### Phase 3: Rolling Statistics (Full Anomaly Detection)

```java
.keyBy(count -> count.countryPrefix)
.process(new AnomalyDetectionFunction())
```

**This function maintains**:
- Per-key state (RollingStats object)
- Last 12 window counts
- Running mean and standard deviation
- Emits anomaly alerts

### Phase 4: Production Enhancements

1. **Better timestamp handling**
2. **Watermark configuration** (handle late events)
3. **Checkpointing** (fault tolerance)
4. **Metrics** (Prometheus integration)
5. **Alerting** (Kafka → Lambda → SNS)

---

## Configuration

### pom.xml Dependencies

```xml
<dependencies>
    <!-- Flink Core -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-streaming-java</artifactId>
        <version>1.18.0</version>
    </dependency>
    
    <!-- Kafka Connector -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-connector-kafka</artifactId>
        <version>3.0.0-1.18</version>
    </dependency>
    
    <!-- JSON Processing -->
    <dependency>
        <groupId>org.apache.flink</groupId>
        <artifactId>flink-shaded-jackson</artifactId>
        <version>2.14.2-17.0</version>
    </dependency>
</dependencies>
```

### Flink Configuration (flink-conf.yaml)

```yaml
# Checkpointing
execution.checkpointing.interval: 60s
execution.checkpointing.mode: EXACTLY_ONCE
state.backend: filesystem
state.checkpoints.dir: s3://sasktel-flink-platform/checkpoints/sip-anomaly
state.savepoints.dir: s3://sasktel-flink-platform/savepoints/sip-anomaly

# Parallelism (adjust based on throughput)






​Step 1: Filter & Extract
- Filter for terminating, international (non-+1), volte calls
- Extract first 4 chars of calling number (country prefix)

Step 2: Aggregate
- Create 5-minute time buckets
- Count calls per country prefix per bucket

Step 3: Statistical Analysis (per country prefix)
- Calculate rolling mean over 12 windows (60 minutes)
- Calculate deviations from that mean
- Calculate rolling standard deviation of those deviations
- Set threshold at 3σ above mean (99.7% confidence)

Step 4: Detect Anomalies
- Flag when current calls > (mean + 3σ) AND calls > 10

