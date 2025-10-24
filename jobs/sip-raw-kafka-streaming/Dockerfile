FROM flink:1.16

# Create the usrlib directory (it doesn't exist in base image)
RUN mkdir -p /opt/flink/usrlib

# Copy the job JAR
# COPY target/sip-raw-kafka-streaming-1.0.jar /opt/flink/usrlib/
COPY target/sip-raw-kafka-streaming-1.0.jar /opt/flink/usrlib/sip-raw-kafka-streaming.jar

# Make sure permissions are correct
# RUN chmod +r /opt/flink/usrlib/$sip-raw-kafka-streaming.jar

# Debug: Show what we actually copied
RUN echo "Files in /opt/flink/usrlib/:" && ls -la /opt/flink/usrlib/

# Copy any additional dependencies if needed
# COPY lib/* /opt/flink/lib/

# Set the job JAR location for Flink
ENV FLINK_JOB_JAR=/opt/flink/usrlib/sip-raw-kafka-streaming.jar
