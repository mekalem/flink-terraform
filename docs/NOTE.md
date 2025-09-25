You have access to the following projects and can switch between them with 'oc project <projectname>':

  * sasktel-data-team-flink
    sasktel-telco-cloud-development-gitops


What We Know
You're working in the sasktel-data-team-flink namespace (means folder)

The pods (including taskmanager and flink-oauth-proxy) are running fine there.

But when you run oc get routes -n sasktel-data-team-flink, you get “No resources found”.

And when you try oc get routes -n data-team-flink, you get a “Forbidden” error—because your user AlemM1 doesn’t have permission to list routes in that namespace.

It looks like:

The Flink deployment is in sasktel-data-team-flink.

But no route has been created yet to expose the Flink UI externally.

1. Check for Services
Let’s confirm the Flink UI service exists:
``` bash
oc get svc -n sasktel-data-team-flink

give us 
NAME                   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
data-team-flink        ClusterIP   None             <none>        6123/TCP,6124/TCP   4d16h
data-team-flink-rest   ClusterIP   172.30.134.247   <none>        8081/TCP            4d16h
flink-oauth-proxy      ClusterIP   172.30.154.50    <none>        8080/TCP            4d17h

```


| NAME	                    | TYPE	        | CLUSTER-IP	| EXTERNAL-IP	| PORT(S)	            |   Purpose                                   |
|-----------------------|------------|--------------|-------------|----------------------|--------------------------------------------------------|
| data-team-flink	            | ClusterIP	    | None	        | None	        | 6123/TCP, 6124/TCP	| Internal Flink communication (JobManager|↔ TaskManager)
| data-team-flink-rest	    | ClusterIP	    | (some IP)	    | None	        | 8081/TCP	            | Flink REST API & Dashboard UI               |
| flink-oauth-proxy	        | ClusterIP	    | (some IP)	    | None	        | 8080/TCP	            | OAuth proxy for securing the Flink UI       |
ClusterIP means these services are only reachable inside the cluster.

No External-IP means you can’t access them directly from your browser unless you expose them or use port-forwarding.

# How to Access the Flink UI
Since data-team-flink-rest is on port 8081, that’s your Flink Dashboard. But because it’s internal-only, you have two options:

## Option 1: Port Forward (Quick & Local)
```bash
oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink
```
Then open your browser and go to:
http://localhost:8081


## Option 2: Expose a Route (Permanent & Shareable)
If you want a proper URL like https://flink-ui.apps..., you need to expose the service:
``` bash
oc expose svc data-team-flink-rest --name=flink-ui --port=8081 -n sasktel-data-team-flink
```
Then run:
``` bash
oc get routes -n sasktel-data-team-flink
```

# How to Check Flink Jobs from the Terminal
If you can’t access the UI, you can still interact with Flink using its REST API.

1. Port-forward first:
``` bash
oc port-forward svc/data-team-flink-rest 8081:8081 -n sasktel-data-team-flink
```
2. Then use curl to query jobs:
``` bash
curl http://localhost:8081/jobs/overview
```
You’ll get a JSON response with job IDs, status, and other details.
3. To get details of a specific job:
``` bash
curl http://localhost:8081/jobs/<job-id>
```

You can also trigger savepoints, cancel jobs, or monitor metrics—all through the REST API.

# Bonus: Secure Access via OAuth Proxy
The flink-oauth-proxy service on port 8080 is likely there to protect the Flink UI with authentication. If your cluster uses OAuth, you might need to access the UI through that proxy instead of directly hitting 8081.

In that case, you’d expose the proxy service instead:
``` bash
oc expose svc flink-oauth-proxy --name=flink-ui --port=8080 -n sasktel-data-team-flink
```

# Main.tf explanation
## High-Level Architecture
We're setting up two main components:
1. OAuth Proxy - Handles authentication/security
2. Flink Cluster - The actual stream processing engine
## Component Breakdown
1. Kubernetes Provider
``` hcl
provider "kubernetes" {
  config_path = ""
  ignore_annotations = [...]
  ignore_labels = [...]
}
```
**What it does:** Tells Terraform how to connect to your Kubernetes/OpenShift cluster. The ignore_* fields prevent Terraform from managing certain auto-generated labels/annotations that OpenShift adds.

2. Service Account

``` hcl
resource "kubernetes_service_account_v1" "data_team_flink_proxy" {
  metadata {
    name      = "flink-proxy"
    namespace = "data-team-flink"
    annotations = {
      "serviceaccounts.openshift.io/oauth-redirectreference.data-team-flink-rest" = ...
    }
  }
}

```
**What it does:** Creates a "service account" - think of it as a special user account for applications (not humans). The annotation tells OpenShift "when someone authenticates via OAuth, redirect them to the data-team-flink-rest route."

3. OAuth Cookie Secret
``` hcl
resource "random_string" "oauth_cookie_secret" {
  length  = ...
  special = ..
}

```
What it does: Generates a random secret used to encrypt session cookies. This keeps user sessions secure.

4. OAuth Proxy Deployment

``` hcl
resource "kubernetes_deployment_v1" "flink_oauth_proxy" {
  # ... metadata ...
  spec {
    replicas = 1
    # ... selector ...
    template {
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
            "--cookie-secret=...",
            "--openshift-service-account=flink-proxy"
          ]
        }
      }
    }
  }
}
```

**What it does:** This is the security gateway. Let me explain each argument:

--provider=openshift: Use OpenShift's built-in authentication
--http-address=:8080: The proxy listens on port 8080
--upstream=http://data-team-flink-rest:8081: Forward authenticated requests to Flink's web UI (port 8081)
--cookie-secret=...: Uses the random secret for session encryption
--openshift-service-account=flink-proxy: Uses the service account we created

Flow: User hits OAuth proxy → Proxy checks if they're logged in → If not, redirects to OpenShift login → If yes, forwards request to Flink


5. OAuth Proxy Service

``` hcl
resource "kubernetes_service_v1" "flink_oauth_proxy" {
  # ... metadata ...
  spec {
    selector = { app = "flink-oauth-proxy" }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}
```
**What it does:** Creates a "service" - essentially a stable network endpoint. Other pods can reach the OAuth proxy at flink-oauth-proxy:8080.


6. Flink Deployment (The Main Event)

``` hcl
resource "kubernetes_manifest" "flink_deployment" {
  manifest = {
    apiVersion = "flink.apache.org/v1beta1"
    kind       = "FlinkDeployment"

```
This uses a Custom Resource Definition (CRD) - essentially Kubernetes extensions for specific applications. The Flink Operator (which must be installed separately) watches for these FlinkDeployment resources.

Key configurations:

``` hcl
spec = {
  image        = "flink:1.16"
  flinkVersion = "v1_16"
  flinkConfiguration = {
    "taskmanager.numberOfTaskSlots" = "20"        # How many parallel tasks per TaskManager
    "job.autoscaler.enabled" = "true"             # Auto-scale based on load
    "job.autoscaler.stabilization.interval" = "1m" # Wait 1 min before scaling decisions
    "job.autoscaler.metrics.window" = "15m"       # Look at 15min of metrics
    "job.autoscaler.utilization.target" = "0.5"   # Target 50% CPU utilization
    "pipeline.max-parallelism" = "32"             # Max parallel instances
  }
}
```
## Resource allocation:

JobManager: 2GB RAM, 1 CPU (the "brain" - coordinates jobs)
TaskManager: 2GB RAM, 1 CPU (the "workers" - execute tasks)

## The actual job:
``` hcl
job = {
  jarURI      = "local:///opt/flink/examples/streaming/StateMachineExample.jar"
  parallelism = 2
  upgradeMode = "stateless"
  args = ["--repeatsAfterMinutes=60"]
}
```

job = {
  jarURI      = "local:///opt/flink/examples/streaming/StateMachineExample.jar"
  parallelism = 2
  upgradeMode = "stateless"
  args = ["--repeatsAfterMinutes=60"]
}

How It All Connects
1. Flink Operator (installed separately) sees your FlinkDeployment resource
2. Operator creates: JobManager pod, TaskManager pod(s), and a service called data-team-flink-rest (port 8081)
3. OAuth Proxy sits in front, forwarding authenticated requests to data-team-flink-rest:8081
4. Users access Flink UI through the OAuth proxy (probably via an OpenShift Route)

What You Know vs. What's Happening Here
Your Docker Setup:

1. You write Flink job code
2. Use Maven to build it (mvn clean package)
3. Get a JAR file in target/ folder
4. Upload JAR to Flink UI
5. Run job

This OpenShift/Terraform Setup:

1. Someone else writes Terraform code
2. Terraform creates the Flink cluster infrastructure
3. You still write Flink job code the same way
4. But instead of uploading via UI, your JAR gets deployed automatically

# Let's Break Down the Terraform Syntax
Think of Terraform like a recipe book for infrastructure:
``` hcl
resource "kubernetes_deployment_v1" "flink_oauth_proxy" {
```

This means: "Create a kubernetes deployment, call it 'flink_oauth_proxy' in my code"

``` hcl
metadata {
  name      = "flink-oauth-proxy"
  namespace = "data-team-flink"
}
```

This means: "In Kubernetes, name it 'flink-oauth-proxy' and put it in the 'data-team-flink' namespace"
Think of namespace like a folder - it groups related things together.
## Where Your Job Fits In
Looking at this part of the config:
``` hcl
job = {
  jarURI      = "local:///opt/flink/examples/streaming/StateMachineExample.jar"
  parallelism = 2
  upgradeMode = "stateless"
}
```

Right now, it's running a demo job (StateMachineExample.jar). This is where your job would go instead.
Your Development Workflow Would Be:
1. You Still Write Code (same as before)
2. You Still Build with Maven (same as before)
``` bash
mvn clean package
```
This creates target/my-job-1.0.jar
3. But Deployment is Different
Instead of uploading via UI, you'd:
**Option A:** Put your JAR in a container image
``` dockerfile
FROM flink:1.16
COPY target/my-job-1.0.jar /opt/flink/usrlib/
```
**Option B:** Upload to a shared location and reference it
``` hcl
job = {
  jarURI = "https://my-artifact-repo.com/my-job-1.0.jar"
  # or
  jarURI = "local:///opt/flink/usrlib/my-job-1.0.jar"
}
```