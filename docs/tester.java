package com.sasktel.flink.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.JsonNode;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SimpleSipRawJob {
    
    private static final Logger LOG = LoggerFactory.getLogger(SimpleSipRawJob.class);

    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // Configure Kafka source for sip-raw topic
        KafkaSource<String> source = KafkaSource.<String>builder()
            .setBootstrapServers("data-platform-3-kafka-1:9092") // Update with your actual broker
            .setTopics("sip-raw")
            .setGroupId("simple-sip-raw-consumer")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();

        DataStream<String> rawStream = env.fromSource(
            source,
            WatermarkStrategy.noWatermarks(),
            "SIP Raw Kafka Source"
        );

        // Process and extract key fields from SIP messages
        DataStream<String> processedStream = rawStream
            .map(new SipCallSummaryProcessor())
            .filter(summary -> summary != null); // Filter out failed parsing

        // Print the processed summaries
        processedStream.print("SIP Call Summary");

        env.execute("Simple SIP Raw Streaming Job");
    }

    /**
     * Simple processor that creates human-readable summaries of SIP calls
     */
    public static class SipCallSummaryProcessor implements MapFunction<String, String> {
        private static final ObjectMapper objectMapper = new ObjectMapper();

        @Override
        public String map(String message) throws Exception {
            try {
                JsonNode jsonNode = objectMapper.readTree(message);
                
                String fromAddress = getStringValue(jsonNode, "from_address");
                String fromLocation = getStringValue(jsonNode, "from_location");
                String toAddress = getStringValue(jsonNode, "to_address");
                String toLocation = getStringValue(jsonNode, "to_location");
                String captureZone = getStringValue(jsonNode, "capture_zone");
                
                // Create a readable summary
                return String.format("CALL: %s (%s) -> %s (%s) [Zone: %s]",
                    fromAddress != null ? fromAddress : "Unknown",
                    fromLocation != null ? fromLocation : "Unknown Location",
                    toAddress != null ? toAddress : "Unknown",
                    toLocation != null ? toLocation : "Unknown Location",
                    captureZone != null ? captureZone : "Unknown Zone"
                );
                
            } catch (Exception e) {
                LOG.error("Failed to parse SIP message, treating as non-JSON: {}", message.substring(0, Math.min(100, message.length())));
                
                // If it's not JSON, treat as simple string
                if (!message.trim().startsWith("{")) {
                    return "NON-JSON: " + message;
                }
                
                return null; // Will be filtered out
            }
        }
        
        private String getStringValue(JsonNode node, String fieldName) {
            JsonNode field = node.get(fieldName);
            return field != null && !field.isNull() ? field.asText() : null;
        }
    }
}



package com.sasktel.flink.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.JsonNode;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;

public class SipRawKafkaStreamJob {

    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // Configure Kafka source for sip-raw topic
        KafkaSource<String> source = KafkaSource.<String>builder()
            .setBootstrapServers("data-platform-3-kafka-1:9092") // Update with your actual broker
            .setTopics("sip-raw")
            .setGroupId("sip-raw-consumer-group")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();

        DataStream<String> rawStream = env.fromSource(
            source,
            WatermarkStrategy.noWatermarks(),
            "SIP Raw Kafka Source"
        );

        // Process the stream - handle both JSON and simple strings
        DataStream<String> processedStream = rawStream.map(new MessageProcessor());

        // Print processed messages
        processedStream.print("Processed SIP Message");

        env.execute("SIP Raw Kafka Streaming Job");
    }

    /**
     * Custom function to process messages that could be JSON or simple strings
     */
    public static class MessageProcessor implements MapFunction<String, String> {
        private static final ObjectMapper objectMapper = new ObjectMapper();

        @Override
        public String map(String message) throws Exception {
            try {
                // Try to parse as JSON
                JsonNode jsonNode = objectMapper.readTree(message);
                return "JSON Message: " + jsonNode.toString();
            } catch (Exception e) {
                // If not JSON, treat as simple string
                return "String Message: " + message;
            }
        }
    }
}