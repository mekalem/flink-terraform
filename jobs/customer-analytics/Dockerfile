# FROM flink:1.16

# # Create the usrlib directory (it doesn't exist in base image)
# RUN mkdir -p /opt/flink/usrlib

# # Copy the job JAR
# COPY target/customer-analytics-1.0.jar /opt/flink/examples/streaming/

# # Set the job JAR as the main application
# ENV FLINK_JOB_JAR=/opt/flink/examples/streaming/customer-analytics.jar

FROM flink:1.16

# Create the usrlib directory for custom jobs
RUN mkdir -p /opt/flink/usrlib

# Copy the job JAR to our custom location
COPY target/customer-analytics-1.0.jar /opt/flink/usrlib/customer-analytics.jar

# Make sure permissions are correct
RUN chmod +r /opt/flink/usrlib/customer-analytics.jar

# Debug: Show what we actually copied
RUN echo "Files in /opt/flink/usrlib/:" && ls -la /opt/flink/usrlib/

# Set the job JAR location for Flink
ENV FLINK_JOB_JAR=/opt/flink/usrlib/customer-analytics.jar