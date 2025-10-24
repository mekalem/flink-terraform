package com.company.jobs;

import com.company.flink.config.JobConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.datastream.DataStream;


import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.JsonNode;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;

public class SipRawKafkaStreamingJob {
    
    public static void main(String[] args) throws Exception {
        // Set up the streaming execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        JobConfig config = new JobConfig();
        
        // Configure Kafka source for sip-raw topic
        KafkaSource<String> source = KafkaSource.<String>builder()
            .setBootstrapServers("10.228.26.81:9092") // broker
            .setTopics("sip-raw")
            .setGroupId("data-team-consumer-group")
            .setStartingOffsets(OffsetsInitializer.latest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();

        DataStream<String> stream = env.fromSource(
            source,
            WatermarkStrategy.noWatermarks(),
            "Kafka Source"
        );

        // stream.print();
        stream.rebalance().print();

        // Process the stream - handle both JSON and simple strings
        // DataStream<String> processedStream = rawStream.map(new MessageProcessor());


        // Simple JSON processor
        // DataStream<String> processedStream = rawStream.map(new JsonProcessor());


        // Print processed messages
        // processedStream.print("Processed SIP Message");

        // Execute the job
        env.execute("SIP Raw Kafka Streaming Job");
        
        // TODO: Add your data sources here
        // Example:
        // KafkaSource<String> source = KafkaSource.<String>builder()
        //     .setBootstrapServers(config.getKafkaBootstrapServers())
        //     .setTopics(config.getInputTopic())
        //     .build();
        //
        // DataStream<String> stream = env.fromSource(source, 
        //     WatermarkStrategy.noWatermarks(), "Kafka Source");
        
        // TODO: Add your processing logic here
        // stream.map(new MyProcessFunction()).print();
        
        // TODO: Add your sinks here
        
    }

    public static class JsonProcessor implements MapFunction<String, String> {
        private static final ObjectMapper mapper = new ObjectMapper();

        @Override
        public String map(String jsonMessage) throws Exception {
            JsonNode json = mapper.readTree(jsonMessage);
            
            String from = json.get("from_address").asText();
            String to = json.get("to_address").asText();
            String fromLoc = json.get("from_location").asText();
            String toLoc = json.get("to_location").asText();
            
            return String.format("CALL: %s (%s) -> %s (%s)", from, fromLoc, to, toLoc);
        }
    }
}
