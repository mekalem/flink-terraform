# Session Cluster (no job specified - can run multiple jobs)
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
      # NO job section - this makes it a session cluster
    }
  }
  wait {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
}

# Your original example job as FlinkSessionJob
resource "kubernetes_manifest" "state_machine_job" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "state-machine-example"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"  # Reference to session cluster above
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

# Customer Analytics Job
resource "kubernetes_manifest" "customer_analytics_job" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkSessionJob"
    metadata = {
      name      = "customer-analytics"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      deploymentName = "data-team-flink"  # Reference to session cluster above
      job = {
        jarURI      = "local:///opt/flink/jobs/customer-analytics.jar"
        parallelism = 2
        upgradeMode = "stateless"
      }
    }
  }
  depends_on = [kubernetes_manifest.flink_session_cluster]
}