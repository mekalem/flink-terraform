# Customer Analytics Job - Separate Flink Cluster
resource "kubernetes_manifest" "customer_analytics_deployment" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"
    metadata = {
      name      = "customer-analytics"
      namespace = "sasktel-data-team-flink"
    }
    spec = {
      # Use your custom image with your job
      # image        = "sasktel-registry/customer-analytics:${var.customer_analytics_version}"
      image        = "flink:1.16"
      flinkVersion = "v1_16"
      
      flinkConfiguration = {
        "taskmanager.numberOfTaskSlots"              = "10"
        "job.autoscaler.enabled"                     = "true"
        "job.autoscaler.stabilization.interval"      = "1m"
        "job.autoscaler.metrics.window"              = "15m"
        "job.autoscaler.utilization.target"          = "0.7"
        "job.autoscaler.target.utilization.boundary" = "0.3"
        "pipeline.max-parallelism"                   = "32"
        
        # Production configs
        "state.backend"                              = "rocksdb"
        "state.checkpoints.dir"                      = "s3://sasktel-flink-checkpoints/customer-analytics"
        "execution.checkpointing.interval"           = "60s"
        "execution.checkpointing.min-pause"          = "30s"
      }
      
      serviceAccount = "flink"
      
      jobManager = {
        resource = {
          memory = "4096m"
          cpu    = 2
        }
      }
      
      taskManager = {
        resource = {
          memory = "8192m"
          cpu    = 4
        }
      }
      
      job = {
        # Your compiled JAR inside the Docker image
        jarURI      = "local:///opt/flink/usrlib/customer-analytics.jar"
        parallelism = 8
        upgradeMode = "savepoint"  # Production: use savepoint for stateful upgrades
        state       = "running"
        
        args = [
          "--config.path=/opt/flink/conf/job-config.properties"
        ]
      }
    }
  }
  
  wait {
    fields = {
      "status.jobManagerDeploymentStatus" = "READY"
    }
  }
}