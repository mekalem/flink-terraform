
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

# -----------------------------------------------------------------------------
# NEW: Session Cluster (replaces the old FlinkDeployment)
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
      image        = "flink:1.16"
      flinkVersion = "v1_16"
      flinkConfiguration = {
        "taskmanager.numberOfTaskSlots"              = "20"
        "job.autoscaler.enabled"                     = "true"
        "job.autoscaler.stabilization.interval"      = "1m"
        "job.autoscaler.metrics.window"              = "15m"
        "job.autoscaler.utilization.target"          = "0.5"
        "job.autoscaler.target.utilization.boundary" = "0.3"
        "pipeline.max-parallelism"                   = "32"
      }
      serviceAccount = "flink"
      jobManager = {
        resource = {
          memory = "2048m"
          cpu    = 1
        }
      }
      taskManager = {
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

# -----------------------------------------------------------------------------
# Job 1: State Machine Example (same as your current job)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "state_machine_job" {
  # depends_on = [kubernetes_manifest.flink_session_cluster]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "state-machine-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"  # Reference the session cluster
      
      job = {
        # Same JAR and config as your working application mode job
        jarURI      = "local:///opt/flink/examples/streaming/StateMachineExample.jar"
        parallelism = 2
        upgradeMode = "stateless"
        state       = "running"
        args = [
          "--repeatsAfterMinutes=60"
        ]
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Job 2: Word Count Example (additional job)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "word_count_job" {
  # depends_on = [kubernetes_manifest.flink_session_cluster]
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "word-count-job"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"  # Reference the same session cluster
      
      job = {
        # Another built-in example JAR
        jarURI      = "local:///opt/flink/examples/streaming/WordCount.jar"
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