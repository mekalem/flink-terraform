
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
      # image        = "container-registry.stholdco.com/technology-data-team/customer-analytics:latest" 
      image        = local.full_image_url 
      flinkVersion = "v1_16"
      # mode         = "standalone"  # This is the important to stop dynamic resource allocation, `native` default
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
        replicas = 1  # This should force TaskManager creation
        resource = {
          memory = "2048m"
          cpu    = 1
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
            # image = "container-registry.stholdco.com/technology-data-team/customer-analytics:latest"
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

# Use your custom JAR via the HTTPS server
resource "kubernetes_manifest" "custom_analytics_job" {
  depends_on = [kubernetes_manifest.custom_jar_https_server]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "custom-analytics-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        # Access your custom JAR via HTTP (internal cluster traffic)
        jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/customer-analytics-1.0.jar"
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
# Job 2: Top Speed Windowing Example
resource "kubernetes_manifest" "top_speed_windowing_job" {
  depends_on = [kubernetes_manifest.custom_jar_https_server]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "top-speed-windowing"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        # Change only the JAR filename at the end of the URL
        jarURI      = "http://custom-jar-server.sasktel-data-team-flink.svc.cluster.local:8443/TopSpeedWindowing.jar"
        parallelism = 4
        upgradeMode = "stateless"
        state       = "running"
      }
    }
  }
}

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