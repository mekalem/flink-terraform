FROM flink:1.16

# Create the usrlib directory (it doesn't exist in base image)
RUN mkdir -p /opt/flink/usrlib
RUN mkdir -p /opt/flink/data

# Copy the job JAR
# COPY target/nlp-finance-credits-1.0.jar /opt/flink/usrlib/
# COPY target/nlp-finance-credits-1.0.jar /opt/flink/usrlib/nlp-finance-credits.jar
COPY target/finance-credits-ml-inference.jar /opt/flink/usrlib/finance-credits-ml-inference.jar
COPY target/nlp-finance-credits-producer.jar /opt/flink/usrlib/nlp-finance-credits-producer.jar

# Make sure permissions are correct
# RUN chmod +r /opt/flink/usrlib/$nlp-finance-credits.jar
# RUN chmod +r /opt/flink/usrlib/$nlp-finance-credits-producer.jar
# RUN chmod +r /opt/flink/usrlib/$finance-credits-ml-inference.jar

# Debug: Show what we actually copied
RUN echo "Files in /opt/flink/usrlib/:" && ls -la /opt/flink/usrlib/

# Copy any additional dependencies if needed
# Copy CSV data
COPY data/cleanedDataOct04.csv /opt/flink/data/cleanedDataOct04.csv

RUN chown -R flink:flink /opt/flink/usrlib /opt/flink/data

# Set the job JAR location for Flink
# ENV FLINK_JOB_JAR=/opt/flink/usrlib/nlp-finance-credits.jar
ENV FLINK_JOB_JAR=/opt/flink/usrlib/nlp-finance-credits-producer.jar
ENV FLINK_JOB_JAR=/opt/flink/usrlib/finance-credits-ml-inference.jar
