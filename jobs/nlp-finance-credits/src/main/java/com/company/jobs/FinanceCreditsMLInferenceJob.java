    package com.company.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.AsyncDataStream;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.async.ResultFuture;
import org.apache.flink.streaming.api.functions.async.RichAsyncFunction;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Collections;
import java.util.concurrent.TimeUnit;

/**
 * Job 2: Real-time ML Inference Pipeline
 * Kafka → Model Server → Console Output
 */
public class FinanceCreditsMLInferenceJob {
    
    private static final String KAFKA_BOOTSTRAP_SERVERS = "10.228.26.81:9092";
    private static final String KAFKA_TOPIC = "data-team-nlp-finance-credits";
    private static final String KAFKA_GROUP_ID = "data-team-consumer-group";
    private static final String MODEL_SERVER_URL = "http://ml-model-server:8000";
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(4);
        
        System.out.println("==============================================");
        System.out.println("Kafka ML Inference Job Starting");
        System.out.println("Model Server: " + MODEL_SERVER_URL);
        System.out.println("Kafka Topic: " + KAFKA_TOPIC);
        System.out.println("==============================================");
        
        // Kafka source
        KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setTopics(KAFKA_TOPIC)
            .setGroupId(KAFKA_GROUP_ID)
            .setStartingOffsets(OffsetsInitializer.earliest())
            .setValueOnlyDeserializer(new SimpleStringSchema())
            .build();
        
        // Read from Kafka
        DataStream<String> kafkaStream = env
            .fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "Kafka Source");
        
        // Parse JSON
        DataStream<TelcoRecord> records = kafkaStream
            .map(new JsonParser())
            .filter(r -> r != null)
            .name("Parse JSON");
        
        // Async ML inference (200 concurrent requests)
        DataStream<MLResult> mlResults = AsyncDataStream.unorderedWait(
            records,
            new MLModelInference(MODEL_SERVER_URL),
            10000,  // 10 second timeout
            TimeUnit.MILLISECONDS,
            200     // Max 200 concurrent async requests
        ).name("ML Inference");
        
        // Print results (sampling to avoid log bloat)
        mlResults
            .filter(new SamplingFilter(10))  // Print every 10th result
            .map(new ResultFormatter())
            .print();
        
        env.execute("Kafka ML Inference Job");
    }
    
    // Data classes
    public static class TelcoRecord {
        public String can;
        public String noteType;
        public String text;
        public long timestamp;
        
        public TelcoRecord(String can, String noteType, String text, long timestamp) {
            this.can = can;
            this.noteType = noteType;
            this.text = text;
            this.timestamp = timestamp;
        }
    }
    
    public static class MLResult {
        public TelcoRecord record;
        public String[] services = new String[0];
        public String[] issues = new String[0];
        public String[] amounts = new String[0];
        public String[] persons = new String[0];
        public String[] actions = new String[0];
        public String[] orgs = new String[0];
        public String[] locations = new String[0];
        public long inferenceTimeMs;
        public long endToEndLatencyMs;
        
        public MLResult(TelcoRecord record) {
            this.record = record;
        }
    }
    
    // Parse JSON from Kafka
    public static class JsonParser implements MapFunction<String, TelcoRecord> {
        private final ObjectMapper mapper = new ObjectMapper();
        
        @Override
        public TelcoRecord map(String json) throws Exception {
            try {
                JsonNode node = mapper.readTree(json);
                String can = node.get("can").asText();
                String noteType = node.get("note_type").asText("UNKNOWN");
                String text = node.get("text").asText();
                long timestamp = node.has("timestamp") ? node.get("timestamp").asLong() : System.currentTimeMillis();
                
                return new TelcoRecord(can, noteType, text, timestamp);
            } catch (Exception e) {
                System.err.println("[JSON Parser] Error: " + e.getMessage());
                return null;
            }
        }
    }
    
    // Async ML inference
    public static class MLModelInference extends RichAsyncFunction<TelcoRecord, MLResult> {
        private final String modelServerUrl;
        private transient HttpClient httpClient;
        private transient ObjectMapper mapper;
        private long requestCount = 0;
        private long totalInferenceTime = 0;
        
        public MLModelInference(String url) {
            this.modelServerUrl = url;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .version(HttpClient.Version.HTTP_2)
                .build();
            mapper = new ObjectMapper();
            System.out.println("[ML Inference] Connected to: " + modelServerUrl);
        }
        
        @Override
        public void asyncInvoke(TelcoRecord record, ResultFuture<MLResult> resultFuture) throws Exception {
            long startTime = System.currentTimeMillis();
            
            // Create payload
            ObjectNode payload = mapper.createObjectNode();
            payload.put("text", record.text);
            payload.put("note_type", record.noteType);
            payload.put("can", record.can);
            
            // HTTP request
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(modelServerUrl + "/predict"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(payload)))
                .timeout(Duration.ofSeconds(8))
                .build();
            
            // Async call
            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                .thenAccept(response -> {
                    try {
                        long inferenceTime = System.currentTimeMillis() - startTime;
                        long endToEndLatency = System.currentTimeMillis() - record.timestamp;
                        
                        MLResult result = new MLResult(record);
                        result.inferenceTimeMs = inferenceTime;
                        result.endToEndLatencyMs = endToEndLatency;
                        
                        if (response.statusCode() == 200) {
                            parseResponse(response.body(), result);
                            
                            requestCount++;
                            totalInferenceTime += inferenceTime;
                            
                            // Log stats every 100 requests
                            if (requestCount % 100 == 0) {
                                long avgTime = totalInferenceTime / requestCount;
                                System.out.println(String.format(
                                    "[ML Inference] Processed: %d | Avg: %dms | Last: %dms | E2E: %dms",
                                    requestCount, avgTime, inferenceTime, endToEndLatency
                                ));
                            }
                        } else {
                            System.err.println("[ML Inference] HTTP " + response.statusCode());
                        }
                        
                        resultFuture.complete(Collections.singleton(result));
                    } catch (Exception e) {
                        System.err.println("[ML Inference] Error: " + e.getMessage());
                        resultFuture.complete(Collections.singleton(new MLResult(record)));
                    }
                })
                .exceptionally(throwable -> {
                    System.err.println("[ML Inference] Request failed: " + throwable.getMessage());
                    resultFuture.complete(Collections.singleton(new MLResult(record)));
                    return null;
                });
        }
        
        private void parseResponse(String body, MLResult result) throws Exception {
            JsonNode json = mapper.readTree(body);
            result.services = parseArray(json, "SERVICE");
            result.issues = parseArray(json, "ISSUE");
            result.amounts = parseArray(json, "AMOUNT");
            result.persons = parseArray(json, "PERSON");
            result.actions = parseArray(json, "ACTION");
            result.orgs = parseArray(json, "ORG");
            result.locations = parseArray(json, "LOCATION");
        }
        
        private String[] parseArray(JsonNode json, String key) {
            if (json.has(key) && json.get(key).isArray()) {
                ArrayNode arr = (ArrayNode) json.get(key);
                String[] result = new String[arr.size()];
                for (int i = 0; i < arr.size(); i++) {
                    result[i] = arr.get(i).asText();
                }
                return result;
            }
            return new String[0];
        }
    }
    
    // Sampling filter to avoid log bloat
    public static class SamplingFilter implements org.apache.flink.api.common.functions.FilterFunction<MLResult> {
        private final int sampleRate;
        private int count = 0;
        
        public SamplingFilter(int sampleRate) {
            this.sampleRate = sampleRate;
        }
        
        @Override
        public boolean filter(MLResult result) {
            count++;
            return count % sampleRate == 0;  // Print every Nth result
        }
    }
    
    // Format output
    public static class ResultFormatter implements MapFunction<MLResult, String> {
        private final ObjectMapper mapper = new ObjectMapper();
        
        @Override
        public String map(MLResult result) throws Exception {
            ObjectNode json = mapper.createObjectNode();
            json.put("can", result.record.can);
            json.put("note_type", result.record.noteType);
            json.put("inference_ms", result.inferenceTimeMs);
            json.put("e2e_latency_ms", result.endToEndLatencyMs);
            json.put("text", result.record.text.substring(0, Math.min(50, result.record.text.length())) + "...");
            
            json.set("SERVICE", mapper.valueToTree(result.services));
            json.set("ISSUE", mapper.valueToTree(result.issues));
            json.set("AMOUNT", mapper.valueToTree(result.amounts));
            json.set("PERSON", mapper.valueToTree(result.persons));
            
            return mapper.writerWithDefaultPrettyPrinter().writeValueAsString(json);
        }
    }
}