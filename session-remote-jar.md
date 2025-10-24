# -----------------------------------------------------------------------------
# JAR Server - serves JAR files over HTTP so the operator can access them
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "jar_server_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "jar-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "jar-server"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "jar-server"
          }
        }
        spec = {
          initContainers = [{
            name  = "copy-jars"
            image = "container-registry.stholdco.com/technology-data-team/customer-analytics:latest"
            command = ["sh", "-c"]
            args = ["cp -r /opt/flink/examples/streaming/* /shared/"]
            volumeMounts = [{
              name      = "shared-jars"
              mountPath = "/shared"
            }]
          }]
          containers = [{
            name  = "nginx"
            image = "nginx:alpine"
            ports = [{
              containerPort = 80
            }]
            volumeMounts = [{
              name      = "shared-jars"
              mountPath = "/usr/share/nginx/html"
            }]
          }]
          volumes = [{
            name = "shared-jars"
            emptyDir = {}
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "jar_server_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "jar-server"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      selector = {
        app = "jar-server"
      }
      ports = [{
        port       = 80
        targetPort = 80
      }]
    }
  }
}

# -----------------------------------------------------------------------------
# Session Cluster (simplified without volume mounts)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "flink_session_cluster" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"
    metadata = {
      name      = "data-team-flink"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      image        = "container-registry.stholdco.com/technology-data-team/customer-analytics:latest"
      flinkVersion = "v1_16"
      flinkConfiguration = {
        "taskmanager.numberOfTaskSlots" = "20"
      }
      serviceAccount = "flink"
      jobManager = {
        resource = {
          memory = "2048m"
          cpu    = 1
        }
      }
      taskManager = {
        replicas = 1
        resource = {
          memory = "2048m"
          cpu    = 1
        }
      }
    }
  }
  wait = {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
}

# -----------------------------------------------------------------------------
# Session Job using HTTP URL to access JAR
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "customer_analytics_job" {
  depends_on = [
    kubernetes_manifest.flink_session_cluster,
    kubernetes_manifest.jar_server_deployment
  ]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "customer-analytics-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        # Now the operator can access the JAR via HTTP
        jarURI      = "http://jar-server.sasktel-data-team-flink.svc.cluster.local/customer-analytics-1.0.jar"
        parallelism = 1
        upgradeMode = "stateless"
        state       = "running"
        args = [
          # Add your job-specific arguments here
        ]
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Test with built-in WordCount JAR via HTTP
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "word_count_job" {
  depends_on = [
    kubernetes_manifest.flink_session_cluster,
    kubernetes_manifest.jar_server_deployment
  ]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "word-count-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        jarURI      = "http://jar-server.sasktel-data-team-flink.svc.cluster.local/WordCount.jar"
        parallelism = 1
        upgradeMode = "stateless"
        state       = "running"
        args = [
          "--input", "lorem ipsum dolor sit amet consectetur adipiscing elit"
        ]
      }
    }
  }
}