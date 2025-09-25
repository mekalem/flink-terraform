#!/bin/bash

JOB_NAME=$1

if [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <job-name>"
    exit 1
fi

JOB_DIR="jobs/$JOB_NAME"
mkdir -p "$JOB_DIR/src/main/java/com/company/jobs"

# Create basic pom.xml
cat > "$JOB_DIR/pom.xml" << 'POMPOM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.company</groupId>
    <artifactId>JOB_NAME_PLACEHOLDER</artifactId>
    <version>1.0</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <flink.version>1.16.3</flink.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>com.company</groupId>
            <artifactId>flink-common</artifactId>
            <version>1.0</version>
        </dependency>

        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-streaming-java</artifactId>
            <version>${flink.version}</version>
            <scope>provided</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.2.4</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>com.company.jobs.JOB_CLASS_PLACEHOLDER</mainClass>
                                </transformer>
                            </transformers>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
POMPOM

# Replace placeholders in pom.xml
sed -i "s/JOB_NAME_PLACEHOLDER/$JOB_NAME/g" "$JOB_DIR/pom.xml"
JOB_CLASS=$(echo $JOB_NAME | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g' | sed 's/ //g')Job
sed -i "s/JOB_CLASS_PLACEHOLDER/$JOB_CLASS/g" "$JOB_DIR/pom.xml"

# Create basic Dockerfile
cat > "$JOB_DIR/Dockerfile" << 'DOCKERDOCKER'
FROM flink:1.16

# Create the usrlib directory (it doesn't exist in base image)
RUN mkdir -p /opt/flink/usrlib

# Copy the job JAR
# COPY target/JOB_NAME_PLACEHOLDER-1.0.jar /opt/flink/usrlib/
COPY target/JOB_NAME_PLACEHOLDER-1.0.jar /opt/flink/usrlib/JOB_NAME_PLACEHOLDER.jar

# Make sure permissions are correct
RUN chmod +r /opt/flink/usrlib/$JOB_NAME_PLACEHOLDER.jar

# Debug: Show what we actually copied
RUN echo "Files in /opt/flink/usrlib/:" && ls -la /opt/flink/usrlib/

# Copy any additional dependencies if needed
# COPY lib/* /opt/flink/lib/

# Set the job JAR location for Flink
ENV FLINK_JOB_JAR=/opt/flink/usrlib/JOB_NAME_PLACEHOLDER.jar
DOCKERDOCKER


# Replace placeholder in Dockerfile
sed -i "s/JOB_NAME_PLACEHOLDER/$JOB_NAME/g" "$JOB_DIR/Dockerfile"

# Create basic Java class
cat > "$JOB_DIR/src/main/java/com/company/jobs/$JOB_CLASS.java" << JAVAJAVA
package com.company.jobs;

import com.company.flink.config.JobConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.datastream.DataStream;

public class $JOB_CLASS {
    
    public static void main(String[] args) throws Exception {
        // Set up the streaming execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        JobConfig config = new JobConfig();
        
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
        
        // Execute the job
        env.execute("$JOB_NAME");
    }
}
JAVAJAVA

echo "✅ Created new job: $JOB_NAME"
echo "📁 Location: $JOB_DIR"
echo "🔧 Edit your job logic in: $JOB_DIR/src/main/java/com/company/jobs/$JOB_CLASS.java"
echo ""
echo "Next steps:"
echo "1. Edit the Java file to add your processing logic"
echo "2. Run: make build-job JOB=$JOB_NAME"
