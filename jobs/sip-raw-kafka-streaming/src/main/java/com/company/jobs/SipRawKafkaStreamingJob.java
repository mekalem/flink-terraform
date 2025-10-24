package com.company.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.formats.json.JsonDeserializationSchema;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.time.Duration;
import java.util.LinkedList;
import java.text.SimpleDateFormat;
import java.util.TimeZone;
/**
 * Flink job for detecting anomalous SIP call patterns in real-time
 * 
 * This job replicates the Splunk query logic:
 * - Filters for international calls (Terminating, non-US callers)
 * - Extracts country dialing code prefix (first 4 chars)
 * - Counts calls per country code in 5-minute windows
 * - Maintains 60-minute rolling statistics (12 windows of 5 min)
 * - Detects anomalies when calls exceed 3 standard deviations from mean
 * - Filters for only significant spikes (>10 calls)
 */
public class SipRawKafkaStreamingJob {
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Enable checkpointing for fault tolerance
        // env.enableCheckpointing(60000); // checkpoint every 60 seconds
        
        // Create JsonDeserializationSchema for SipCallEvent POJO
        JsonDeserializationSchema<SipCallEvent> jsonFormat = 
            new JsonDeserializationSchema<>(SipCallEvent.class);
        
        // Configure Kafka source with proper JSON deserialization
        KafkaSource<SipCallEvent> source = KafkaSource.<SipCallEvent>builder()
            .setBootstrapServers("10.228.26.81:9092")
            .setTopics("sip-raw")
            .setGroupId("data-team-consumer-group")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(jsonFormat)  // Use JsonDeserializationSchema
            .build();

        // Step 1: Parse JSON from Kafka
        // OPTION 1: Use Processing Time (simpler, no watermark issues)
        DataStream<SipCallEvent> parsedCalls = env.fromSource(
            source,
            WatermarkStrategy.noWatermarks(),  // Use processing time, no watermarks needed
            "Kafka Source"
        );
        
        // OPTION 2: Use Event Time with Kafka record timestamp
        // DataStream<SipCallEvent> parsedCalls = env.fromSource(
        //     source,
        //     WatermarkStrategy.<SipCallEvent>forBoundedOutOfOrderness(Duration.ofSeconds(30))
        //         .withTimestampAssigner((event, timestamp) -> {
        //             // Use the Kafka record timestamp (automatically provided)
        //             return timestamp;  // DON'T use System.currentTimeMillis()!
        //         }),
        //     "Kafka Source"
        // );

        // Debug: Print all incoming events
        parsedCalls.print("RAW-EVENTS");

        // Step 2: Filter for relevant calls (Terminating, international, non-US)
        DataStream<SipCallEvent> filteredCalls = parsedCalls
            .filter(call -> 
                call.from_address != null && 
                !call.from_address.startsWith("+1") && 
                call.from_address.startsWith("+")
                // Add more filters if you have direction/serviceProvider fields:
                // && call.direction != null && call.direction.equals("Terminating")
                // && call.service_provider != null && call.service_provider.startsWith("volte")
            );

        // Debug: Print filtered events with timestamps
        filteredCalls
            .map(call -> {
                String time = formatTimeCST(System.currentTimeMillis());
                return String.format("[%s] %s", time, call.toString());
            })
            .print("FILTERED-CALLS");

        // Step 3: Extract country code prefix (first 4 characters)
        DataStream<Tuple2<String, Long>> callsWithPrefix = filteredCalls
            .map(call -> {
                String prefix = call.from_address.length() >= 4 
                    ? call.from_address.substring(0, 4) 
                    : call.from_address;
                return new Tuple2<>(prefix, 1L);
            })
            .returns(org.apache.flink.api.common.typeinfo.Types.TUPLE(
                org.apache.flink.api.common.typeinfo.Types.STRING,
                org.apache.flink.api.common.typeinfo.Types.LONG
            ));

        // Debug: Print prefixes
        callsWithPrefix.print("WITH-PREFIX");

        // Step 4: Count calls per prefix in 5-minute tumbling windows
        // CHANGED: Using TumblingProcessingTimeWindows instead of TumblingEventTimeWindows
        DataStream<CallCount> windowedCounts = callsWithPrefix
            .keyBy(tuple -> tuple.f0)
            .window(TumblingProcessingTimeWindows.of(Time.minutes(5)))  // Processing time!
            .aggregate(new CallCountAggregator(), new CallCountWindowFunction());

        // Debug: Print window counts
               windowedCounts
            .map(count -> {
                String start = formatTimeCST(count.windowStart);
                String end = formatTimeCST(count.windowEnd);
                return String.format("Window[%s to %s] %s: %d calls", 
                    start, end, count.countryPrefix, count.calls);
            })
            .print("WINDOWED-COUNTS");

        // Step 5: Detect anomalies using rolling statistics
        DataStream<AnomalyAlert> anomalies = windowedCounts
            .keyBy(count -> count.countryPrefix)
            .process(new AnomalyDetectionFunction());

        // Debug: Print ALL anomalies (before filtering)
        anomalies.print("ALL-ANOMALIES");

        // Step 6: Filter for significant anomalies only
        DataStream<AnomalyAlert> significantAnomalies = anomalies
            .filter(alert -> alert.calls > 10 && alert.isAnomaly);

        // Step 7: Print to stdout with job identifier (for testing)
        significantAnomalies.print("SIP-ANOMALY");

        // // Step 8: Sink to Kafka for downstream processing
        // KafkaSink<String> sink = KafkaSink.<String>builder()
        //     .setBootstrapServers("your-kafka-broker:9092")
        //     .setRecordSerializer(KafkaRecordSerializationSchema.builder()
        //         .setTopic("sip-anomalies")
        //         .setValueSerializationSchema(new SimpleStringSchema())
        //         .build()
        //     )
        //     .build();

        // significantAnomalies
        //     .map(alert -> alert.toJson())
        //     .sinkTo(sink);

        env.execute("SIP Call Anomaly Detection Job");
    }

    // ======================== Data Classes ========================

    /**
     * POJO for JSON deserialization
     * Field names MUST match your Kafka JSON keys exactly
     */
    public static class SipCallEvent {
        // Use exact field names from your JSON
        public String from_address;
        public Integer from_country_dialing_code;
        public String from_country_code;
        public String from_country;
        public String from_location;
        public String to_address;
        public Integer to_country_dialing_code;
        public String to_country;
        public String to_country_code;
        public String to_location;
        public String call_id;
        public String capture_zone;
        
        // Optional fields - add if your JSON has them
        // public String direction;
        // public String service_provider;

        // Default constructor required by Jackson
        public SipCallEvent() {}
        
        @Override
        public String toString() {
            return String.format("SipCall{from=%s, to=%s, from_country_code=%s, callId=%s}", 
                from_address, to_address, from_country_code, call_id);
        }
    }

    public static class CallCount {
        public String countryPrefix;
        public long calls;
        public long windowStart;
        public long windowEnd;

        public CallCount() {}

        public CallCount(String countryPrefix, long calls, long windowStart, long windowEnd) {
            this.countryPrefix = countryPrefix;
            this.calls = calls;
            this.windowStart = windowStart;
            this.windowEnd = windowEnd;
        }
        
        @Override
        public String toString() {
            return String.format("CallCount{prefix=%s, calls=%d, window=[%d-%d]}", 
                countryPrefix, calls, windowStart, windowEnd);
        }
    }

    public static class AnomalyAlert {
        public String countryPrefix;
        public long calls;
        public long prevCalls;
        public double rollingAverage;
        public double rollingDeviation;
        public double threshold;
        public double upperBound;
        public boolean isAnomaly;
        public long timestamp;

        public AnomalyAlert() {}
        
        @Override
        public String toString() {
            return String.format("Alert{prefix=%s, calls=%d, avg=%.2f, stdDev=%.2f, upperBound=%.2f, isAnomaly=%b}", 
                countryPrefix, calls, rollingAverage, rollingDeviation, upperBound, isAnomaly);
        }

        public String toJson() {
            try {
                ObjectMapper mapper = new ObjectMapper();
                ObjectNode json = mapper.createObjectNode();
                json.put("country_prefix", countryPrefix);
                json.put("calls", calls);
                json.put("prev_calls", prevCalls);
                json.put("rolling_average", String.format("%.2f", rollingAverage));
                json.put("rolling_deviation", String.format("%.2f", rollingDeviation));
                json.put("threshold", String.format("%.2f", threshold));
                json.put("upper_bound", String.format("%.2f", upperBound));
                json.put("is_anomaly", isAnomaly);
                json.put("timestamp", timestamp);
                json.put("severity", calls > upperBound * 2 ? "CRITICAL" : "WARNING");
                return mapper.writeValueAsString(json);
            } catch (Exception e) {
                return "{}";
            }
        }
    }

    // ======================== Functions ========================

    /**
     * Aggregate function to count calls in window
     */
    public static class CallCountAggregator implements AggregateFunction<Tuple2<String, Long>, Long, Long> {
        @Override
        public Long createAccumulator() {
            return 0L;
        }

        @Override
        public Long add(Tuple2<String, Long> value, Long accumulator) {
            return accumulator + value.f1;
        }

        @Override
        public Long getResult(Long accumulator) {
            return accumulator;
        }

        @Override
        public Long merge(Long a, Long b) {
            return a + b;
        }
    }

    /**
     * Window function to create CallCount objects with window metadata
     */
    public static class CallCountWindowFunction 
        extends ProcessWindowFunction<Long, CallCount, String, TimeWindow> {
        
        @Override
        public void process(String key, Context context, Iterable<Long> elements, 
                          Collector<CallCount> out) {
            long count = elements.iterator().next();
            long windowStart = context.window().getStart();
            long windowEnd = context.window().getEnd();
            
            out.collect(new CallCount(key, count, windowStart, windowEnd));
        }
    }

    /**
     * Anomaly detection using rolling statistics
     * Maintains 12 windows (60 minutes) of history per country prefix
     * Calculates mean, standard deviation, and detects outliers
     */
    public static class AnomalyDetectionFunction 
        extends KeyedProcessFunction<String, CallCount, AnomalyAlert> {
        
        // State to maintain rolling window of last 12 call counts
        private transient ValueState<RollingStats> statsState;

        @Override
        public void open(Configuration parameters) {
            ValueStateDescriptor<RollingStats> descriptor = 
                new ValueStateDescriptor<>("rolling-stats", RollingStats.class);
            statsState = getRuntimeContext().getState(descriptor);
        }

        @Override
        public void processElement(CallCount callCount, Context ctx, Collector<AnomalyAlert> out) 
            throws Exception {
            
            RollingStats stats = statsState.value();
            if (stats == null) {
                stats = new RollingStats();
            }

            // Add current count to rolling window
            stats.addValue(callCount.calls);

            // Calculate statistics
            double mean = stats.getMean();
            double deviation = callCount.calls - mean;
            double stdDev = stats.getStandardDeviation();
            double threshold = 3.0 * stdDev;
            double upperBound = mean + threshold;

            // Get previous call count
            long prevCalls = stats.getPreviousValue();

            // Check if anomaly
            boolean isAnomaly = callCount.calls > upperBound && callCount.calls > 10;

            // Create alert
            AnomalyAlert alert = new AnomalyAlert();
            alert.countryPrefix = callCount.countryPrefix;
            alert.calls = callCount.calls;
            alert.prevCalls = prevCalls;
            alert.rollingAverage = mean;
            alert.rollingDeviation = stdDev;
            alert.threshold = threshold;
            alert.upperBound = upperBound;
            alert.isAnomaly = isAnomaly;
            alert.timestamp = callCount.windowEnd;

            // Update state
            statsState.update(stats);

            // Emit alert (will be filtered later)
            out.collect(alert);
        }
    }

    /**
     * Helper class to maintain rolling statistics
     */
    public static class RollingStats implements java.io.Serializable {
        private static final int WINDOW_SIZE = 12; // 12 windows of 5 minutes = 60 minutes
        private LinkedList<Long> values = new LinkedList<>();
        private long sum = 0;
        private double sumOfSquares = 0;

        public void addValue(long value) {
            values.addLast(value);
            sum += value;
            sumOfSquares += value * value;

            // Remove oldest value if window is full
            if (values.size() > WINDOW_SIZE) {
                long removed = values.removeFirst();
                sum -= removed;
                sumOfSquares -= removed * removed;
            }
        }

        public double getMean() {
            if (values.isEmpty()) return 0.0;
            return (double) sum / values.size();
        }

        public double getStandardDeviation() {
            if (values.size() < 2) return 0.0;
            
            double mean = getMean();
            double variance = (sumOfSquares / values.size()) - (mean * mean);
            
            // Handle potential negative variance due to floating point errors
            if (variance < 0) variance = 0;
            
            return Math.sqrt(variance);
        }

        public long getPreviousValue() {
            if (values.size() < 2) return 0;
            return values.get(values.size() - 2);
        }

        public int getWindowSize() {
            return values.size();
        }
    }

        private static String formatTimeCST(long milliseconds) {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS");
        sdf.setTimeZone(TimeZone.getTimeZone("America/Regina"));
        return sdf.format(milliseconds);
    }
}