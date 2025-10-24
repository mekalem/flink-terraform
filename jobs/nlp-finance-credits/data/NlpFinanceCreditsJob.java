package com.company.jobs;

import com.company.flink.config.JobConfig;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.file.src.FileSource;
import org.apache.flink.connector.file.src.reader.TextLineInputFormat;
import org.apache.flink.core.fs.Path;
import org.apache.flink.streaming.api.datastream.AsyncDataStream;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.async.ResultFuture;
import org.apache.flink.streaming.api.functions.async.RichAsyncFunction;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Collections;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

public class NlpFinanceCreditsJob {
    
    private static final String MODEL_SERVER_URL = "http://ml-model-server:8000";
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        JobConfig config = new JobConfig();
        
        env.setParallelism(4);
        
        // Read from file directory - monitors for new files
        FileSource<String> fileSource = FileSource
            .forRecordStreamFormat(
                new TextLineInputFormat(),
                new Path("/opt/flink/data/input/")  // Directory to monitor
            )
            .monitorContinuously(Duration.ofSeconds(10))  // Check every 10 seconds
            .build();
        
        DataStream<String> lines = env.fromSource(
            fileSource,
            WatermarkStrategy.noWatermarks(),
            "File Source"
        );
        
        // Skip header and parse CSV
        DataStream<TelcoRecord> parsedData = lines
            .filter(line -> !line.startsWith("CAN"))  // Skip CSV header
            .map(new CSVParser())
            .filter(record -> record != null);
        
        // Async ML inference
        DataStream<MLResult> mlResults = AsyncDataStream.unorderedWait(
            parsedData,
            new MLModelInference(MODEL_SERVER_URL),
            5000,
            TimeUnit.MILLISECONDS,
            100
        );
        
        // Print results
        mlResults
            .map(new ResultFormatter())
            .print();
        
        env.execute("NLP Finance Credits Job");
    }
    
    // Simple data classes
    public static class TelcoRecord {
        public String can;
        public String noteType;
        public String text;
        
        public TelcoRecord(String can, String noteType, String text) {
            this.can = can;
            this.noteType = noteType;
            this.text = text;
        }
    }
    
    public static class MLResult {
        public TelcoRecord record;
        public String[] services = new String[0];
        public String[] issues = new String[0];
        public String[] amounts = new String[0];
        public String[] persons = new String[0];
        public String[] actions = new String[0];
        public String[] organizations = new String[0];
        public String[] locations = new String[0];
        
        public MLResult(TelcoRecord record) {
            this.record = record;
        }
    }
    
    // Parse CSV line
    public static class CSVParser implements MapFunction<String, TelcoRecord> {
        @Override
        public TelcoRecord map(String line) throws Exception {
            try {
                // Adjust indices based on your CSV structure
                String[] parts = line.split(",(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)", -1);  // CSV with quoted fields
                
                String can = parts.length > 0 ? parts[0].replace("\"", "") : "";
                String noteType = parts.length > 1 ? parts[1].replace("\"", "") : "UNKNOWN";
                String text = parts.length > 2 ? parts[2].replace("\"", "") : "";
                
                return new TelcoRecord(can, noteType, text);
            } catch (Exception e) {
                System.err.println("Failed to parse CSV line: " + e.getMessage());
                return null;
            }
        }
    }
    
    // Async ML inference (same as before)
    public static class MLModelInference extends RichAsyncFunction<TelcoRecord, MLResult> {
        private final String modelServerUrl;
        private transient HttpClient httpClient;
        private transient ObjectMapper mapper;
        
        public MLModelInference(String url) {
            this.modelServerUrl = url;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
            mapper = new ObjectMapper();
        }
        
        @Override
        public void asyncInvoke(TelcoRecord record, ResultFuture<MLResult> resultFuture) throws Exception {
            ObjectNode payload = mapper.createObjectNode();
            payload.put("text", record.text);
            payload.put("note_type", record.noteType);
            payload.put("can", record.can);
            
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(modelServerUrl + "/predict"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(payload)))
                .timeout(Duration.ofSeconds(5))
                .build();
            
            CompletableFuture<HttpResponse<String>> responseFuture = 
                httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString());
            
            responseFuture.thenAccept(response -> {
                try {
                    MLResult result = new MLResult(record);
                    
                    if (response.statusCode() == 200) {
                        parseMLResponse(response.body(), result);
                    } else {
                        applyFallback(record.text, result);
                    }
                    
                    resultFuture.complete(Collections.singleton(result));
                } catch (Exception e) {
                    MLResult fallback = new MLResult(record);
                    applyFallback(record.text, fallback);
                    resultFuture.complete(Collections.singleton(fallback));
                }
            }).exceptionally(throwable -> {
                MLResult fallback = new MLResult(record);
                applyFallback(record.text, fallback);
                resultFuture.complete(Collections.singleton(fallback));
                return null;
            });
        }
        
        private void parseMLResponse(String responseBody, MLResult result) throws IOException {
            JsonNode json = mapper.readTree(responseBody);
            result.services = parseArray(json, "SERVICE");
            result.issues = parseArray(json, "ISSUE");
            result.amounts = parseArray(json, "AMOUNT");
            result.persons = parseArray(json, "PERSON");
            result.actions = parseArray(json, "ACTION");
            result.organizations = parseArray(json, "ORG");
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
        
        private void applyFallback(String text, MLResult result) {
            String lower = text.toLowerCase();
            if (lower.contains("$") || lower.contains("dollar")) {
                result.amounts = new String[]{"payment_related"};
            }
            if (lower.contains("internet") || lower.contains("phone")) {
                result.services = new String[]{"telecom_service"};
            }
            if (lower.contains("problem") || lower.contains("complaint")) {
                result.issues = new String[]{"customer_issue"};
            }
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
            json.put("original_text", result.record.text);
            
            json.set("SERVICE", mapper.valueToTree(result.services));
            json.set("ISSUE", mapper.valueToTree(result.issues));
            json.set("AMOUNT", mapper.valueToTree(result.amounts));
            json.set("PERSON", mapper.valueToTree(result.persons));
            json.set("ACTION", mapper.valueToTree(result.actions));
            json.set("ORG", mapper.valueToTree(result.organizations));
            json.set("LOCATION", mapper.valueToTree(result.locations));
            
            return mapper.writeValueAsString(json);
        }
    }
}