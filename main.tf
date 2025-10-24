
# -----------------------------------------------------------------------------
# Provider: Kubernetes
# -----------------------------------------------------------------------------
# Configures the Kubernetes provider for resource management, with annotation
# and label ignore lists to avoid conflicts with FluxCD, OLM, and other operators.
# -----------------------------------------------------------------------------
provider "kubernetes" {
  config_path = "~/.kube/config"
  ignore_annotations = [
    "^reconcile\\.external-secrets\\.io\\/*",
    "^openshift\\.io\\/*",
    "^fluxcd\\.controlplane\\.io/prune$",
    "^kustomize\\.toolkit\\.fluxcd.io/ssa$",
  ]
  ignore_labels = [
    "^kustomize\\.toolkit\\.fluxcd.io\\/*",
    "^reconcile\\.external-secrets\\.io\\/*",
    "^olm\\.operatorgroup\\.*\\/*",
    "^openshift\\.io\\/*",
    "^app\\.kubernetes\\.io/instance$",
    "^app\\.kubernetes\\.io/managed-by$",
    "^app\\.kubernetes\\.io/name$",
    "^app\\.kubernetes\\.io/part-of$",
    "^app\\.kubernetes\\.io/version$",
    "^fluxcd\\.controlplane\\.io/name$",
    "^fluxcd\\.controlplane\\.io/namespace$",
  ]
}


resource "kubernetes_service_account_v1" "sasktel_data_team_flink_proxy" {
  metadata {
    name      = "flink-proxy"
    namespace = "sasktel-data-team-flink"
    annotations = {
      "serviceaccounts.openshift.io/oauth-redirectreference.data-team-flink-rest" = <<EOF
{"kind":"OAuthRedirectReference","apiVersion":"v1","reference":{"kind":"Route","name":"data-team-flink-rest"}}
EOF
    }
  }
}

resource "random_string" "oauth_cookie_secret" {
  length  = 32
  special = false
  upper   = true
  lower   = true
}


resource "kubernetes_deployment_v1" "flink_oauth_proxy" {
  metadata {
    name      = "flink-oauth-proxy"
    namespace = "sasktel-data-team-flink"
    labels = {
      app = "flink-oauth-proxy"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "flink-oauth-proxy"
      }
    }
    template {
      metadata {
        labels = {
          app = "flink-oauth-proxy"
        }
      }
      spec {
        service_account_name = "flink-proxy"
        container {
          name  = "oauth-proxy"
          image = "quay.io/openshift/origin-oauth-proxy:4.18.0"
          args = [
            "--provider=openshift",
            "--https-address=",
            "--http-address=:8080",
            "--upstream=http://data-team-flink-rest:8081",
            "--cookie-secret=${base64encode(random_string.oauth_cookie_secret.result)}",
            "--openshift-service-account=flink-proxy"
          ]
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "flink_oauth_proxy" {
  metadata {
    name      = "flink-oauth-proxy"
    namespace = "sasktel-data-team-flink"
    labels = {
      app = "flink-oauth-proxy"
    }
  }
  spec {
    selector = {
      app = "flink-oauth-proxy"
    }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

locals {
  # Construct the full image URL
  full_image_url = "${var.harbor_registry}/${var.harbor_project}/${var.image_name}:${var.image_tag}"
}

# Session Cluster 
resource "kubernetes_manifest" "flink_session_cluster" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"
    metadata = {
      name      = "data-team-flink"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      # image        = "flink:1.16"
      image        = local.full_image_url 
      flinkVersion = "v1_16"
      # mode         = "standalone"  # This is the important to stop dynamic resource allocation, `native` default
      flinkConfiguration = {
        "taskmanager.numberOfTaskSlots" = "20"
        # These make the logs visible in the Flink UI
        "web.log.path"         = "/opt/flink/log/flink.log"
        "taskmanager.log.path" = "/opt/flink/log/flink-taskmanager.log"
        "env.log.dir"          = "/opt/flink/log"
        "web.cancel.enable"    = "true"
        "web.submit.enable"    = "true"
      }
      # Configure log4j to write to both console AND file
      logConfiguration = {
        "log4j-console.properties" = <<-EOT
          rootLogger.level = INFO
          rootLogger.appenderRef.console.ref = ConsoleAppender
          rootLogger.appenderRef.file.ref = FileAppender
          
          # Console appender (for kubectl logs)
          appender.console.type = Console
          appender.console.name = ConsoleAppender
          appender.console.layout.type = PatternLayout
          appender.console.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %-60c %x - %m%n
          
          # File appender (for Flink UI)
          appender.file.type = RollingFile
          appender.file.name = FileAppender
          appender.file.fileName = /opt/flink/log/flink.log
          appender.file.filePattern = /opt/flink/log/flink.log.%i
          appender.file.layout.type = PatternLayout
          appender.file.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p %-60c %x - %m%n
          appender.file.policies.type = Policies
          appender.file.policies.size.type = SizeBasedTriggeringPolicy
          appender.file.policies.size.size = 5MB
          appender.file.strategy.type = DefaultRolloverStrategy
          appender.file.strategy.max = 5
        EOT
      }

      serviceAccount = "flink"
      jobManager = {
        resource = {
          memory = "2048m"
          cpu    = 1
        }
      }
      taskManager = {
        replicas = 1  # This should force TaskManager creation
        resource = {
          memory = "2048m"
          cpu    = 1
        }
      }

      # Ensure log directory exists and is writable
      podTemplate = {
        apiVersion = "v1"
        kind       = "Pod"
        metadata = {
          name = "task-manager-pod-template"
        }
        spec = {
          containers = [{
            name = "flink-main-container"
            volumeMounts = [{
              name      = "flink-logs"
              mountPath = "/opt/flink/log"
            }]
          }]
          volumes = [{
            name = "flink-logs"
            emptyDir = {}
          }]
        }
      }
    }
  }
  wait {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
}



# Option 4: If you need to use your custom JAR immediately,
# create a simple HTTPS server (most practical short-term solution)
resource "kubernetes_manifest" "custom_jar_https_server" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "custom-jar-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "custom-jar-server"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "custom-jar-server"
          }
        }
        spec = {
          initContainers = [{
            name  = "extract-custom-jars"
            image        = local.full_image_url 
            command = ["sh", "-c"]
            args = ["find /opt/flink -name '*.jar' -exec cp {} /shared/ \\;"]
            volumeMounts = [{
              name      = "jar-storage"
              mountPath = "/shared"
            }]
          }]
          containers = [{
            name  = "python-https-server"
            image = "python:3.9-alpine"
            command = ["python", "-m", "http.server", "8443"]
            workingDir = "/shared"
            ports = [{
              containerPort = 8443
            }]
            volumeMounts = [{
              name      = "jar-storage"
              mountPath = "/shared"
            }]
          }]
          volumes = [{
            name = "jar-storage"
            emptyDir = {}
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "custom_jar_server_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "custom-jar-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      selector = {
        app = "custom-jar-server"
      }
      ports = [{
        port       = 8443
        targetPort = 8443
      }]
    }
  }
}

# Job 1: Finance Credits ML Inference Job
resource "kubernetes_manifest" "finance_credits_ml_inference_job" {
  depends_on = [kubernetes_manifest.custom_jar_https_server]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "finance-credits-ml-inference"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        # Access your custom JAR via HTTP (internal cluster traffic)
        jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/finance-credits-ml-inference.jar"
        parallelism = 1
        upgradeMode = "stateless"
        state       = "running"
        args = [
          # Add your custom job arguments
        ]
      }
    }
  }
}

# # Job 2: Nlp Finance Credits Producer Job
# resource "kubernetes_manifest" "nlp_finance_credits_producer_job" {
#   depends_on = [kubernetes_manifest.custom_jar_https_server]
  
#   manifest = {
#     apiVersion = "flink.apache.org/v1beta1"
#     kind       = "FlinkSessionJob"
#     metadata = {
#       name      = "nlp-finance-credits-producer"
#       namespace = "sasktel-data-team-flink"
#     }
#     spec = {
#       deploymentName = "data-team-flink"
      
#       job = {
#         # Change only the JAR filename at the end of the URL
#         jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/nlp-finance-credits-producer.jar"
#         parallelism = 1
#         upgradeMode = "stateless"
#         state       = "running"
#       }
#     }
#   }
# }


# # Job 1: Use custom JAR via the HTTPS server
# resource "kubernetes_manifest" "custom_analytics_job" {
#   depends_on = [kubernetes_manifest.custom_jar_https_server]
  
#   manifest = {
#     apiVersion = "flink.apache.org/v1beta1"
#     kind       = "FlinkSessionJob"
#     metadata = {
#       name      = "custom-analytics-job"
#       namespace = "sasktel-data-team-flink"
#     }
#     spec = {
#       deploymentName = "data-team-flink"
      
#       job = {
#         # Access your custom JAR via HTTP (internal cluster traffic)
#         jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/customer-analytics-1.0.jar"
#         parallelism = 1
#         upgradeMode = "stateless"
#         state       = "running"
#         args = [
#           # Add your custom job arguments
#         ]
#       }
#     }
#   }
# }

# # Job 2: Top Speed Windowing Example
# resource "kubernetes_manifest" "top_speed_windowing_job" {
#   depends_on = [kubernetes_manifest.custom_jar_https_server]
  
#   manifest = {
#     apiVersion = "flink.apache.org/v1beta1"
#     kind       = "FlinkSessionJob"
#     metadata = {
#       name      = "top-speed-windowing"
#       namespace = "sasktel-data-team-flink"
#     }
#     spec = {
#       deploymentName = "data-team-flink"
      
#       job = {
#         # Change only the JAR filename at the end of the URL
#         jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/TopSpeedWindowing.jar"
#         parallelism = 4
#         upgradeMode = "stateless"
#         state       = "running"
#       }
#     }
#   }
# }


resource "kubernetes_manifest" "flink_route_kafka_diameter_gy" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "data-team-flink-rest"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      to = {
        kind = "Service"
        name = "data-team-flink-rest"
      }
      port = {
        targetPort = 8081
      }
      tls = {
        termination = "edge"
      }
    }
  }
}


### ALL MODEL SERVER RESOURCES BELOW

# Create Kubernetes secret for S3 credentials
resource "kubernetes_secret" "s3_credentials" {
  metadata {
    name      = "s3-credentials"
    namespace = "sasktel-data-team-flink"
  }

  type = "Opaque"

  # Use 'data' - Terraform will base64 encode automatically
  data = {
    access-key-id     = var.s3_access_key_id
    secret-access-key = var.s3_secret_access_key
  }
}

resource "kubernetes_manifest" "ml_model_server" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "ml-model-server"
      namespace = "sasktel-data-team-flink"
      labels = {
        app = "ml-model-server"
      }
    }
    spec = {
      replicas = 2
      selector = {
        matchLabels = {
          app = "ml-model-server"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "ml-model-server"
          }
        }
        spec = {
          containers = [{
            name            = "model-server"
            image           = "${var.harbor_registry}/${var.harbor_project}/ml-model-server:latest"
            imagePullPolicy = "Always"
            
            ports = [{
              containerPort = 8000
              name          = "http"
            }]
            
            # Environment variables
            env = [
              {
                name  = "S3_BUCKET_NAME"
                value = var.s3_bucket_name
              },
              {
                name  = "S3_MODEL_KEY"
                value = var.s3_model_key
              },
              {
                name  = "S3_ENDPOINT_URL"
                value = var.s3_endpoint_url
              },
              {
                name = "AWS_ACCESS_KEY_ID"
                valueFrom = {
                  secretKeyRef = {
                    name = kubernetes_secret.s3_credentials.metadata[0].name
                    key  = "access-key-id"
                  }
                }
              },
              {
                name = "AWS_SECRET_ACCESS_KEY"
                valueFrom = {
                  secretKeyRef = {
                    name = kubernetes_secret.s3_credentials.metadata[0].name
                    key  = "secret-access-key"
                  }
                }
              },
              {
                name  = "AWS_REGION"
                value = var.aws_region
              },
              {
                name  = "USE_S3_MODEL"
                value = "true"
              },
              {
                name  = "PORT"
                value = "8000"
              }
            ]
            
            resources = {
              requests = {
                memory = "2Gi"
                cpu    = "1"
              }
              limits = {
                memory = "4Gi"
                cpu    = "2"
              }
            }
            
            livenessProbe = {
              httpGet = {
                path = "/health"
                port = 8000
              }
              initialDelaySeconds = 60
              periodSeconds       = 30
              timeoutSeconds      = 5
              failureThreshold    = 3
            }
            
            readinessProbe = {
              httpGet = {
                path = "/ready"
                port = 8000
              }
              initialDelaySeconds = 30
              periodSeconds       = 10
              timeoutSeconds      = 5
              failureThreshold    = 3
            }
          }]
        }
      }
    }
  }
  
  depends_on = [kubernetes_secret.s3_credentials]
}

## OG
# resource "kubernetes_manifest" "ml_model_server" {
#   manifest = {
#     apiVersion = "apps/v1"
#     kind       = "Deployment"
#     metadata = {
#       name      = "ml-model-server"
#       namespace = "sasktel-data-team-flink"
#       labels = {
#         app = "ml-model-server"
#       }
#     }
#     spec = {
#       replicas = 2
#       selector = {
#         matchLabels = {
#           app = "ml-model-server"
#         }
#       }
#       template = {
#         metadata = {
#           labels = {
#             app = "ml-model-server"
#           }
#         }
#         spec = {
#           containers = [{
#             name  = "model-server"
#             image = "${var.harbor_registry}/${var.harbor_project}/ml-model-server:latest"
#             imagePullPolicy = "Always"
            
#             ports = [{
#               containerPort = 8000
#               name          = "http"
#             }]
            
#             # No volume mounts needed - model is in the image
            
#             resources = {
#               requests = {
#                 memory = "2Gi"
#                 cpu    = "1"
#               }
#               limits = {
#                 memory = "4Gi"
#                 cpu    = "2"
#               }
#             }
            
#             livenessProbe = {
#               httpGet = {
#                 path = "/health"
#                 port = 8000
#               }
#               initialDelaySeconds = 60
#               periodSeconds       = 30
#               timeoutSeconds      = 5
#               failureThreshold    = 3
#             }
            
#             readinessProbe = {
#               httpGet = {
#                 path = "/ready"
#                 port = 8000
#               }
#               initialDelaySeconds = 30
#               periodSeconds       = 10
#               timeoutSeconds      = 5
#               failureThreshold    = 3
#             }
#           }]
#         }
#       }
#     }
#   }
# }

# Service for model server
resource "kubernetes_manifest" "ml_model_server_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "ml-model-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      selector = {
        app = "ml-model-server"
      }
      ports = [{
        port       = 8000
        targetPort = 8000
        name       = "http"
      }]
      type = "ClusterIP"
    }
  }
}

resource "kubernetes_manifest" "ml_model_server_route" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "ml-model-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      to = {
        kind = "Service"
        name = "ml-model-server"
      }
      port = {
        targetPort = 8000
      }
      tls = {
        termination = "edge"
      }
    }
  }
}