package com.company.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.formats.json.JsonDeserializationSchema;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import java.time.Duration;

/**
 * Simplified version for initial testing
 * Counts calls per country prefix in 5-minute windows
 */
public class SipRawKafkaStreamingJob {
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Create JsonDeserializationSchema for SipCallEvent POJO
        JsonDeserializationSchema<SipCallEvent> jsonFormat = 
            new JsonDeserializationSchema<>(SipCallEvent.class);
        
        // Kafka source with proper JSON deserialization
        KafkaSource<SipCallEvent> source = KafkaSource.<SipCallEvent>builder()
            .setBootstrapServers("10.228.26.81:9092")
            .setTopics("sip-raw")
            .setGroupId("data-team-consumer-group")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(jsonFormat)  // Use JsonDeserializationSchema
            .build();

        DataStream<SipCallEvent> stream = env.fromSource(
            source,
            WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(30)),
            "Kafka Source"
        );

        // Parse and extract country prefix
        DataStream<Tuple2<String, Integer>> callsByPrefix = stream
            .map(event -> {
                String fromAddress = event.from_address != null ? event.from_address : "+0000";
                
                // Extract first 4 characters as country prefix
                String prefix = fromAddress.length() >= 4 
                    ? fromAddress.substring(0, 4) 
                    : fromAddress;
                
                return new Tuple2<>(prefix, 1);
            })
            .returns(org.apache.flink.api.common.typeinfo.Types.TUPLE(
                org.apache.flink.api.common.typeinfo.Types.STRING,
                org.apache.flink.api.common.typeinfo.Types.INT
            ));

        // Count calls per prefix in 5-minute windows
        DataStream<Tuple2<String, Integer>> windowedCounts = callsByPrefix
            .keyBy(tuple -> tuple.f0)
            .window(TumblingProcessingTimeWindows.of(Time.minutes(5)))
            .sum(1);

        // Print results with more context
        windowedCounts.map(result -> 
            String.format("Country Prefix: %s, Call Count: %d", result.f0, result.f1)
        ).print();

        env.execute("SIP Call Counter - Simple (Fixed JSON)");
    }

    /**
     * POJO for JSON deserialization
     * Field names MUST match your Kafka JSON keys exactly
     * Jackson will automatically map JSON to these fields
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
        
        // Default constructor required by Jackson
        public SipCallEvent() {}
        
        // Getters and setters (can be omitted if fields are public)
        // But good practice to have them
        
        @Override
        public String toString() {
            return String.format("SipCall{from=%s, to=%s, callId=%s}", 
                from_address, to_address, call_id);
        }
    }
}