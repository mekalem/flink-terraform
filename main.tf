
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
      image        = "flink:1.16"
      # image        = "container-registry.stholdco.com/technology-data-team/customer-analytics:latest" 

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


# Job 2: Word Count Example (additional job)
resource "kubernetes_manifest" "top-speed-windowing" {
  # depends_on = [kubernetes_manifest.flink_session_cluster]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "top-speed-windowing"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"  # Reference the same session cluster
      
      job = {
        # Another built-in example JAR
        # jarURI      = "/opt/flink/examples/streaming/WordCount.jar"
        # jarURI      = "local:///opt/flink/examples/streaming/customer-analytics-1.0.jar"
        # jarURI      = "https://repo1.maven.org/maven2/org/apache/flink/flink-examples-streaming/2.1.0/flink-examples-streaming-2.1.0-WordCount.jar"
        jarURI      =  "https://repo1.maven.org/maven2/org/apache/flink/flink-examples-streaming_2.12/1.15.3/flink-examples-streaming_2.12-1.15.3-TopSpeedWindowing.jar"
        parallelism = 4
        upgradeMode = "stateless"
        state       = "running"
        # args = [
        #   "--repeatsAfterMinutes=60"
        # ]
      }
    }
  }
}

# Job 3:  State Machine Example
resource "kubernetes_manifest" "session_windowing_job" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "session-windowing-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"
      
      job = {
        jarURI      =  "https://repo1.maven.org/maven2/org/apache/flink/flink-examples-streaming_2.12/1.15.3/flink-examples-streaming_2.12-1.15.3-TopSpeedWindowing.jar"
        parallelism = 2
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