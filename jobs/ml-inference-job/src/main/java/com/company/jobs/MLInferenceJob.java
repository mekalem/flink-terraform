package com.company.jobs;

import com.company.flink.config.JobConfig;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

public class MLInferenceJob {
    
    public static void main(String[] args) throws Exception {
        // Set up the streaming execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        JobConfig config = new JobConfig();
        
        // Configure Kafka Source
        KafkaSource<String> source = KafkaSource.<String>builder()
            .setBootstrapServers(config.getKafkaBootstrapServers())
            .setTopics(config.getInputTopic())
            .setGroupId("ml-inference-consumer")
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();

        // Configure Kafka Sink
        KafkaSink<String> sink = KafkaSink.<String>builder()
            .setBootstrapServers(config.getKafkaBootstrapServers())
            .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                .setTopic(config.getOutputTopic())
                .setValueSerializationSchema(new SimpleStringSchema())
                .build())
            .build();

        // Build the processing pipeline
        DataStream<String> inputStream = env.fromSource(source, 
            WatermarkStrategy.noWatermarks(), "Kafka Source");
        
        DataStream<String> processedStream = inputStream
            .map(new MLInferenceFunction(config.getModelServerUrl()))
            .name("ML Inference");

        // Write results to Kafka
        processedStream.sinkTo(sink).name("Kafka Sink");

        // Execute the job
        env.execute("ML Inference Job");
    }

    public static class MLInferenceFunction implements MapFunction<String, String> {
        private final String modelServerUrl;
        private transient CloseableHttpClient httpClient;

        public MLInferenceFunction(String modelServerUrl) {
            this.modelServerUrl = modelServerUrl;
        }

        @Override
        public String map(String input) throws Exception {
            if (httpClient == null) {
                httpClient = HttpClients.createDefault();
            }

            try {
                HttpPost request = new HttpPost(modelServerUrl + "/predict");
                request.setEntity(new StringEntity(input));
                request.setHeader("Content-Type", "application/json");

                String response = EntityUtils.toString(
                    httpClient.execute(request).getEntity());
                
                return response;
            } catch (Exception e) {
                // Handle errors gracefully
                return "{\"error\": \"" + e.getMessage() + "\", \"input\": \"" + input + "\"}";
            }
        }
    }
}