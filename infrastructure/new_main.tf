provider "kubernetes" {
  config_path = ""
  ignore_annotations = [
    "",
    # etc
  ]
  ignore_labels = [
    "",
    # etc
  ]
}

resource "kubernetes_service_account_v1" "data_team_flink_proxy" {
  metadata {
    name      = "flink-proxy"
    namespace = var.namespace
    annotations = {
      "serviceaccounts.openshift.io/oauth-redirectreference.data-team-flink-rest" = <<EOF
{"kind":"OAuthRedirectReference","apiVersion":"v1","reference":{"kind":"Route","name":"data-team-flink-rest"}}
EOF
    }
  }
}

resource "random_string" "oauth_cookie_secret" {
  length  = 32
  special = true
  upper   = true
  lower   = true
}

resource "kubernetes_deployment_v1" "flink_oauth_proxy" {
  metadata {
    name      = "flink-oauth-proxy"
    namespace = var.namespace
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
            "--cookie-secret=${random_string.oauth_cookie_secret.result}",
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
    namespace = var.namespace
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

# Session cluster (can run multiple jobs)
resource "kubernetes_manifest" "flink_session_cluster" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"
    metadata = {
      name      = "data-team-flink"
      namespace = var.namespace
    }
    spec = {
      image        = "flink:${var.flink_image_tag}"
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
      # No job section - this makes it a session cluster
    }
  }
  wait {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
}

# Create FlinkSessionJob for each job in the configuration
resource "kubernetes_manifest" "flink_jobs" {
  for_each = var.job_configs
  
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = each.key
      namespace = var.namespace
    }
    spec = {
      deploymentName = "data-team-flink"
      job = {
        jarURI      = each.value.jar_uri
        parallelism = each.value.parallelism
        upgradeMode = "stateless"
        args        = each.value.args
      }
    }
  }
  depends_on = [kubernetes_manifest.flink_session_cluster]
}

# Also create your original example job
resource "kubernetes_manifest" "state_machine_job" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "state-machine-example"
      namespace = var.namespace
    }
    spec = {
      deploymentName = "data-team-flink"
      job = {
        jarURI      = "local:///opt/flink/examples/streaming/StateMachineExample.jar"
        parallelism = 2
        upgradeMode = "stateless"
        args = [
          "--repeatsAfterMinutes=60"
        ]
      }
    }
  }
  depends_on = [kubernetes_manifest.flink_session_cluster]
}