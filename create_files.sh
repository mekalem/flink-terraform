#!/bin/bash

# Navigate to project directory (run this after the structure creation script)
cd flink-data-platform

# Create .gitignore file
cat > .gitignore << 'EOF'
# Maven
target/
pom.xml.tag
pom.xml.releaseBackup
pom.xml.versionsBackup
pom.xml.next
release.properties
dependency-reduced-pom.xml

# IntelliJ IDEA
.idea/
*.iml
*.iws

# Eclipse
.project
.metadata
bin/
tmp/
*.tmp
*.bak
*.swp
*~.nib
local.properties
.classpath
.settings/
.loadpath

# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
*.tfvars
!*.tfvars.example

# OS
.DS_Store
Thumbs.db

# Logs
logs/
*.log

# Docker
.dockerignore
EOF

# Create README.md
cat > README.md << 'EOF'
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
EOF

# Create Makefile
cat > Makefile << 'EOF'
.PHONY: help build deploy create-job list-jobs clean

help: ## Show this help message
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

build: ## Build all jobs
	@echo "Building common utilities..."
	@cd jobs/common && mvn clean install -q
	@echo "Building all jobs..."
	@for job in $$(ls jobs/ | grep -v common); do \
		echo "Building $$job..."; \
		cd jobs/$$job && mvn clean package -q && cd ../..; \
	done
	@echo "✅ All jobs built successfully!"

build-job: ## Build specific job (usage: make build-job JOB=job-name)
	@if [ -z "$(JOB)" ]; then echo "Usage: make build-job JOB=job-name"; exit 1; fi
	@./deployment/scripts/build-and-deploy.sh $(JOB)

create-job: ## Create new job from template (usage: make create-job JOB=job-name)
	@if [ -z "$(JOB)" ]; then echo "Usage: make create-job JOB=job-name"; exit 1; fi
	@./deployment/scripts/create-job.sh $(JOB)

list-jobs: ## List all available jobs
	@echo "Available jobs:"
	@ls -d jobs/*/ | grep -v common | xargs -n 1 basename

deploy-dev: ## Deploy to development environment
	@cd infrastructure && terraform apply -var-file="environments/dev.tfvars"

deploy-staging: ## Deploy to staging environment
	@cd infrastructure && terraform apply -var-file="environments/staging.tfvars"

clean: ## Clean all build artifacts
	@find jobs -name target -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Cleaned all build artifacts"
EOF

# Make scripts executable
chmod +x deployment/scripts/build-and-deploy.sh
chmod +x deployment/scripts/create-job.sh

# Create placeholder script files (you'll add content later)
touch deployment/scripts/build-and-deploy.sh
touch deployment/scripts/create-job.sh
touch deployment/scripts/update-job.sh

# Create infrastructure files
touch infrastructure/variables.tf
touch infrastructure/outputs.tf
touch infrastructure/terraform.tfvars
touch infrastructure/environments/dev.tfvars
touch infrastructure/environments/staging.tfvars
touch infrastructure/environments/prod.tfvars

# Create common module files
touch jobs/common/pom.xml

# Create example job pom files
touch jobs/data-ingestion-job/pom.xml
touch jobs/ml-inference-job/pom.xml
touch jobs/analytics-job/pom.xml

# Create Java class files
touch jobs/common/src/main/java/com/company/flink/config/JobConfig.java
touch jobs/ml-inference-job/src/main/java/com/company/jobs/MLInferenceJob.java

# Create Dockerfile templates
touch jobs/data-ingestion-job/Dockerfile
touch jobs/ml-inference-job/Dockerfile
touch jobs/analytics-job/Dockerfile
touch docker/base/Dockerfile

# Create deployment templates
touch deployment/job-templates/base-job-template.yaml
touch deployment/job-templates/job-config-template.yaml
touch deployment/job-templates/pom.xml
touch deployment/job-templates/Dockerfile
touch deployment/job-templates/JobTemplate.java

# Create config files
touch deployment/configs/dev.yaml
touch deployment/configs/staging.yaml
touch deployment/configs/prod.yaml

# Create documentation files
touch docs/job-development.md
touch docs/deployment-guide.md
touch docs/troubleshooting.md

# Create CI/CD files
touch .github/workflows/build-jobs.yml
touch .github/workflows/deploy-jobs.yml

# Create application.conf for common module
cat > jobs/common/src/main/resources/application.conf << 'EOF'
kafka {
    bootstrap.servers = "localhost:9092"
    input.topic = "input-events"
    output.topic = "processed-events"
}

model {
    server.url = "http://model-server:8080"
}
EOF

echo "✅ All files and directories created!"
echo ""
echo "File structure summary:"
echo "📁 Infrastructure: infrastructure/"
echo "📁 Jobs: jobs/"
echo "📁 Deployment: deployment/"
echo "📁 Documentation: docs/"
echo "📄 Build automation: Makefile"
echo ""
echo "Next: Copy the code from the markdown artifact into these files"
echo "Start with: jobs/common/pom.xml, then infrastructure/variables.tf, etc."