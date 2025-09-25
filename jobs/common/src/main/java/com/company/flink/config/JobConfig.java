package com.company.flink.config;

import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;

public class JobConfig {
    private final Config config;
    
    public JobConfig() {
        this.config = ConfigFactory.load();
    }
    
    public String getKafkaBootstrapServers() {
        return config.getString("kafka.bootstrap.servers");
    }
    
    public String getInputTopic() {
        return config.getString("kafka.input.topic");
    }
    
    public String getOutputTopic() {
        return config.getString("kafka.output.topic");
    }
    
    public String getModelServerUrl() {
        return config.getString("model.server.url");
    }
}