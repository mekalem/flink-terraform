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