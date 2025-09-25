#!/bin/bash

# Create Flink Data Platform Project Structure

# Create main project directory

# Infrastructure directory
mkdir -p infrastructure

# Jobs directory structure
mkdir -p jobs/common/src/main/java/com/company/flink/config
mkdir -p jobs/common/src/main/java/com/company/flink/serializers
mkdir -p jobs/common/src/main/java/com/company/flink/sources
mkdir -p jobs/common/src/main/java/com/company/flink/sinks
mkdir -p jobs/common/src/main/java/com/company/flink/utils

# Example jobs
mkdir -p jobs/data-ingestion-job/src/main/java/com/company/jobs
mkdir -p jobs/ml-inference-job/src/main/java/com/company/jobs
mkdir -p jobs/analytics-job/src/main/java/com/company/jobs

# Deployment directory
mkdir -p deployment/job-templates
mkdir -p deployment/scripts
mkdir -p deployment/configs

# Docker directory
mkdir -p docker/base
mkdir -p docker/registry

# Documentation
mkdir -p docs

# CI/CD
mkdir -p .github/workflows

# Create configuration files directory
mkdir -p jobs/common/src/main/resources
mkdir -p jobs/data-ingestion-job/src/main/resources
mkdir -p jobs/ml-inference-job/src/main/resources
mkdir -p jobs/analytics-job/src/main/resources

# Create infrastructure environment configs
mkdir -p infrastructure/environments

echo "✅ Project structure created successfully!"
echo "📁 Created directory: flink-data-platform/"
echo ""
echo "Next steps:"
echo "1. Copy the code from the markdown artifact into the respective files"
echo "2. Navigate to flink-data-platform/ directory"
echo "3. Start creating your files with the provided code"
echo ""
echo "Directory structure:"
tree flink-data-platform/ 2>/dev/null || find flink-data-platform -type d | sed 's|[^/]*/|  |g'