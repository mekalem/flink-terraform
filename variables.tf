# variables.tf - Variable declarations with types and descriptions

variable "namespace" {
  description = "Kubernetes namespace for Flink"
  type        = string
  default     = "sasktel-data-team-flink"
}

variable "flink_image_tag" {
  description = "Flink base image tag"
  type        = string
  default     = "1.16"
}

variable "job_configs" {
  description = "Configuration for each Flink job"
  type = map(object({
    jar_uri     = string
    parallelism = number
    args        = list(string)
    resources = object({
      memory = string
      cpu    = number
    })
  }))
  default = {}
}

variable "harbor_registry" {
  description = "Harbor registry URL"
  type        = string
  default     = ""  # Will come from environment
}

variable "harbor_project" {
  description = "Harbor project name"
  type        = string
  default     = ""  # Will come from environment
}

variable "customer_analytics_image" {
  description = "Customer analytics Docker image"
  type        = string
  default     = ""  # Will be constructed
}

# Add more job image variables as needed
variable "ml_inference_image" {
  description = "Docker image for ML inference job"
  type        = string  
  default     = "flink:1.16"
} 

variable "image_name" {
  description = "Container image name"
  type        = string
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}


# Add S3 variables
variable "s3_bucket_name" {
  description = "S3 bucket name for model storage"
  type        = string
}

variable "s3_model_key" {
  description = "S3 object key for the model file"
  type        = string
}

variable "s3_endpoint_url" {
  description = "S3 endpoint URL"
  type        = string
}

variable "s3_access_key_id" {
  description = "S3 access key ID"
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "S3 secret access key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}