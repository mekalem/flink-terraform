package com.company.jobs;

import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.SourceFunction;
import org.apache.flink.api.common.functions.MapFunction;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;

/**
 * Job 1: Reads CSV file continuously and publishes to Kafka
 * CSV columns: CAN, START_x, cleaned_text_x, X_NOTE_TYPE, etc.
 * Output: JSON messages to Kafka matching model server format
 */
public class NlpFinanceCreditsProducerJob {
    
    // Configuration
    private static final String KAFKA_BOOTSTRAP_SERVERS = "10.228.26.81:9092";
    private static final String KAFKA_TOPIC = "data-team-nlp-finance-credits";
    private static final String CSV_FILE_PATH = "/opt/flink/data/cleanedDataOct04.csv";
    private static final int RECORDS_PER_SECOND = 10;  // Rate limiting
    private static final boolean LOOP_DATA = true;     // Loop when CSV ends
    
    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);  // Single producer for ordered data
        
        System.out.println("==============================================");
        System.out.println("CSV to Kafka Producer Job Starting");
        System.out.println("CSV File: " + CSV_FILE_PATH);
        System.out.println("Kafka Topic: " + KAFKA_TOPIC);
        System.out.println("Rate: " + RECORDS_PER_SECOND + " records/sec");
        System.out.println("==============================================");
        
        // Create CSV source
        DataStream<CSVRecord> csvStream = env
            .addSource(new ContinuousCSVSource(CSV_FILE_PATH, RECORDS_PER_SECOND, LOOP_DATA))
            .name("CSV Source");
        
        // Convert to JSON
        DataStream<String> jsonStream = csvStream
            .map(new CSVToJsonMapper())
            .filter(json -> json != null && !json.isEmpty())
            .name("CSV to JSON");
        
        // Create Kafka sink
        KafkaSink<String> kafkaSink = KafkaSink.<String>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                .setTopic(KAFKA_TOPIC)
                .setValueSerializationSchema(new SimpleStringSchema())
                .build())
            .build();
        
        // Write to Kafka
        jsonStream.sinkTo(kafkaSink).name("Kafka Sink");
        
        // // Print instead
        // jsonStream.print().name("Print Output");

        env.execute("CSV to Kafka Producer Job");
    }
    
    /**
     * Simple data class for CSV records
     */
    public static class CSVRecord {
        public String can;
        public String noteType;
        public String text;
        
        public CSVRecord(String can, String noteType, String text) {
            this.can = can;
            this.noteType = noteType;
            this.text = text;
        }
    }
    
    /**
     * Continuously reads CSV file and loops when finished
     */
    public static class ContinuousCSVSource implements SourceFunction<CSVRecord> {
        private final String filePath;
        private final int recordsPerSecond;
        private final boolean loop;
        private volatile boolean running = true;
        private long totalRecordsSent = 0;
        private int loopCount = 0;
        
        public ContinuousCSVSource(String filePath, int recordsPerSecond, boolean loop) {
            this.filePath = filePath;
            this.recordsPerSecond = recordsPerSecond;
            this.loop = loop;
        }
        
        @Override
        public void run(SourceContext<CSVRecord> ctx) throws Exception {
            System.out.println("[CSV Source] Starting to read from: " + filePath);
            
            long delayMs = 1000 / recordsPerSecond;  // Delay between records
            
            while (running) {
                loopCount++;
                System.out.println("[CSV Source] Starting loop #" + loopCount);
                
                List<CSVRecord> records = readCSVFile();
                
                if (records.isEmpty()) {
                    System.err.println("[CSV Source] No records found in CSV!");
                    break;
                }
                
                for (CSVRecord record : records) {
                    if (!running) break;
                    
                    synchronized (ctx.getCheckpointLock()) {
                        ctx.collect(record);
                        totalRecordsSent++;
                    }
                    
                    // Rate limiting
                    Thread.sleep(delayMs);
                    
                    // Log progress every 100 records
                    if (totalRecordsSent % 100 == 0) {
                        System.out.println("[CSV Source] Sent " + totalRecordsSent + " records");
                    }
                }
                
                System.out.println("[CSV Source] Completed loop #" + loopCount + 
                                 " (" + records.size() + " records, total: " + totalRecordsSent + ")");
                
                if (!loop) {
                    System.out.println("[CSV Source] Loop disabled, stopping");
                    break;
                }
                
                // Pause before restarting loop
                Thread.sleep(1000);
            }
            
            System.out.println("[CSV Source] Finished. Total records sent: " + totalRecordsSent);
        }
        
        private List<CSVRecord> readCSVFile() {
            List<CSVRecord> records = new ArrayList<>();
            
            try (BufferedReader br = new BufferedReader(new FileReader(filePath))) {
                String line;
                String headerLine = br.readLine();  // Read header
                
                if (headerLine == null) {
                    System.err.println("[CSV Source] Empty CSV file!");
                    return records;
                }
                
                System.out.println("[CSV Source] CSV Header: " + headerLine);
                
                // Parse header to find column indices
                String[] headers = headerLine.split(",");
                int canIndex = findColumnIndex(headers, "CAN");
                int noteTypeIndex = findColumnIndex(headers, "X_NOTE_TYPE");
                int textIndex = findColumnIndex(headers, "cleaned_text_x");
                
                if (canIndex == -1 || textIndex == -1) {
                    System.err.println("[CSV Source] Required columns not found!");
                    System.err.println("CAN index: " + canIndex + ", Text index: " + textIndex);
                    return records;
                }
                
                System.out.println("[CSV Source] Column indices - CAN: " + canIndex + 
                                 ", NOTE_TYPE: " + noteTypeIndex + ", TEXT: " + textIndex);
                
                // Read data rows
                while ((line = br.readLine()) != null) {
                    if (line.trim().isEmpty()) continue;
                    
                    try {
                        // Split by comma, handling quoted fields
                        String[] parts = line.split(",(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)", -1);
                        
                        if (parts.length <= Math.max(canIndex, textIndex)) {
                            continue;  // Skip invalid rows
                        }
                        
                        String can = cleanField(parts[canIndex]);
                        String noteType = noteTypeIndex >= 0 && parts.length > noteTypeIndex 
                                        ? cleanField(parts[noteTypeIndex]) 
                                        : "UNKNOWN";
                        String text = cleanField(parts[textIndex]);
                        
                        // Validate required fields
                        if (can.isEmpty() || text.isEmpty()) {
                            continue;
                        }
                        
                        records.add(new CSVRecord(can, noteType, text));
                        
                    } catch (Exception e) {
                        System.err.println("[CSV Source] Error parsing line: " + e.getMessage());
                    }
                }
                
                System.out.println("[CSV Source] Successfully read " + records.size() + " records");
                
            } catch (Exception e) {
                System.err.println("[CSV Source] Error reading CSV: " + e.getMessage());
                e.printStackTrace();
            }
            
            return records;
        }
        
        private int findColumnIndex(String[] headers, String columnName) {
            for (int i = 0; i < headers.length; i++) {
                if (headers[i].trim().equalsIgnoreCase(columnName)) {
                    return i;
                }
            }
            return -1;
        }
        
        private String cleanField(String field) {
            if (field == null) return "";
            return field.replace("\"", "").trim();
        }
        
        @Override
        public void cancel() {
            running = false;
            System.out.println("[CSV Source] Cancelled");
        }
    }
    
    /**
     * Converts CSV record to JSON format expected by model server
     * Output: {"can": "...", "note_type": "...", "text": "...", "timestamp": ...}
     */
    public static class CSVToJsonMapper implements MapFunction<CSVRecord, String> {
        private final ObjectMapper mapper = new ObjectMapper();
        
        @Override
        public String map(CSVRecord record) throws Exception {
            try {
                ObjectNode json = mapper.createObjectNode();
                json.put("can", record.can);
                json.put("note_type", record.noteType);
                json.put("text", record.text);
                json.put("timestamp", System.currentTimeMillis());
                
                return mapper.writeValueAsString(json);
                
            } catch (Exception e) {
                System.err.println("[CSV Mapper] Error creating JSON: " + e.getMessage());
                return null;
            }
        }
    }
}