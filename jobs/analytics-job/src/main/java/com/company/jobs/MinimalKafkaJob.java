package com.sasktel.flink.jobs;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class MinimalKafkaJob {

    // public static void main(String[] args) throws Exception {
    //     StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

    //     KafkaSource<String> source = KafkaSource.<String>builder()
    //         .setBootstrapServers("data-platform-3-kafka-1:9092") // Use Docker hostname
    //         .setTopics("input_stream")
    //         .setGroupId("minimal-job-group")
    //         .setStartingOffsets(OffsetsInitializer.latest())
    //         .setValueOnlyDeserializer(new SimpleStringSchema())
    //         .build();

    //     DataStream<String> stream = env.fromSource(
    //         source,
    //         WatermarkStrategy.noWatermarks(),
    //         "Kafka Source"
    //     );

    //     stream.print(); // This is the operator Flink needs

    //     env.execute("Minimal Kafka Print Job");
    // }

    public static void main(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.fromElements("Hello Flink!").print();
        env.execute("Sanity Check Job");
    }

}



