# Flink Data Platform

Enterprise-grade Apache Flink data processing platform with automated job deployment.

## Quick Start

```bash
# Create a new job
make create-job JOB=my-processor

# Build and deploy
make build-job JOB=my-processor
make deploy-dev
```

## Project Structure

- `jobs/` - Flink job implementations
- `infrastructure/` - Terraform infrastructure code
- `deployment/` - Deployment scripts and templates
- `docs/` - Documentation

## Commands

- `make help` - Show all available commands
- `make list-jobs` - List all jobs
- `make build` - Build all jobs
- `make create-job JOB=name` - Create new job from template
