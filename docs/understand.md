Ok, so I'll explain my understanding of current process i have. Then I need you to please correct any misunderstand / terms, and use realtime agentic search to look at proper sources in web if needed. it all about building a data real time streaming platform using apache flink.

Ok so I have terraform as provisioning tool, setting up on clusters in openshift (which is enterprise / more extensive kubernetes really). Cool, its all in remote server i connect to. Cool.
What is actually setup when I login using OC login. Upon login, I see You have access to the following projects and can switch between them with 'oc project <projectname>': Of the ones listed, I am working in sasktel-data-team-flink namespace?folder?project? (not sure right term in oc, this is what, an openshift project?) Then pods like taskamanger, jobmanager, flink-oauth-proxy are running in there. SO the porjects groups related things together. So the flink deployment is inside this project. Now, when I do kubectl get all -n sasktel-data-team-flink. I get list of pods, services, deployment.apps, replicaset.apps, routes. Currentl, I have I have these. In general, highlevel, I know cluster IP are services reachable only inside the cluster, no external ip means we can't access them directly from browser unless expose in routes or portforwarding. WHich we have two routes exposed for these services. GOt it.  And the oauth proxy is service there to protext the flink ui with authentication later on when done right. cool. Now I need a bit of clarificatoin of what all these categories are as in pods, service, deployment etc... OK next, getting into flink details now. I have flink kubernetes operator running, not native kubernetes flink.. We can deploy in two modes. Application mode (1 to 1 relationship between job and cluster. so separate cluster, resources, per job running), or session mode (1 to many relationship between cluster and jobs, so 1 ui and shared resources of jobmanager/taskmanager etc for multiple jobs running). Cool. In applicatoin mode, because there its only started/deployed with job explicity assosiated, then in the get pods command /cluster, we will see pod for job manager AND taskamangers. NOW, in TOP of deployment TYPE in the Flink kubernetes operator aslo supports two MODES of deployment: native and standalone, you can specify mode in the config / main.tf if you want standalone or native. By default, its native. In  applicatoin mode this is doesn't make too much different to point out. In session mode though, it makes a big difference. In native mode, if no jobs are running, we won't see taskmanager pod allocated, thus in pods listing or in ui, taskamanger pod / slots will show as 0. It's only when job is submitted that we see allocated show up. THis allows flexibility in scheduling and allows flinks to talk to kubernetes to manage kubernetes resources. Vs standalone, not sure what that does, but docs say "Flink is unaware that it is running on Kubernetes and therefore all Kubernetes resources need to be managed externally, by the Kubernetes Operator.". Anyways, I prefer things to be ease in scalability and change, so i left it dynamic with native mode. COol.

Now. I have source code java I use to compile into jars/target, build into docker image, push flink image to harbor registery, for CI pipeline. (Please correct me if terms are wrong)

THen for CD, i have terrafor config / flink config that pulls image from harbor, get jar from specificd path. Then when terraform apply / deploy happens, jobs runs. Cools. I tested with simple example default jobs in streaming folder. Its simple job so runs fine. Then I had custom job created that subscribes to kafka source, does simple print to stdout, again did the ci pipeline / but also testing by submitting job jar in ui and it works. Now, this is where things get complicated. 
1. Something in the design of flink with kubernetes is different that flink as standalone desktop / executive download. Where in kubernetes, the taskamanager stdout never shows, the print from jobs never shows in taskamanger. but it does in flink desktop or whatever. I only see stdout in terminal logs check, not even in logs in ui, that log is operation log not stdout. 
2. From my understanding, most jobs that don't have processing / intermediate steps and only take in source and out sink, show / become coupled into one step and then in ui we don't see bytes processed, it shows working, but everything 0 for all data. UNLESS I do some crazy like split it using         stream.rebalance().print();
THEN I see data processed and see two steps in ui not groupe into one. Is ther a solution to see it without having to do this in kubernetes flink. I know again desktop regular .exe is fine, data shows. 
3. Noww, that you've caught up with my process, never job I want to set up in a machine learning model inferencing pipeline. Where Ideally I hAve a .pt in some persisstent storage, get data input, use the .pt somehow and get json back, and put into sink. simple right? BUT for now here's where I'm confused on standard and prodcution/good pricinciple/best way to do my use case. I have nlp flair trained model. Data rn is in csv, so I can read from it and loop through csv for now to mimic real time data flow OR go complex way of creating job that writes to kafka topic as a sink, then have another job that subscribe to this topic and then uses model. BUT, I'm not sure if we can do all processing in flink or we need model server with api endpoint to talk to model.pt file and etc. Rn I have model server but again, not sure / don't want to overcomplicate something that can be simplified. 
4. I need to know what to do next, what help to ask from my cloud team that provisoin the backend like i need for sure to setup s3 bucket or hdsf? because rn I just pushed model into folder and pushed python image, model, model-server into harbor. assuming this is wrong, and TAKES UP SPACE. since i had to do requirements.txt for flair model dependcies, so confused there too. I also might need them to setup some sink kafka topic for me this purpsode nd others. ok there help
 

 when i have new job jars, do they all ge town flink image build and pushed individually, can i not have one flink, push multiple jar into image /usrlib or ther libaraby similar to how example folder has multiple jars? also, whats less complicated, ideal if we have python based model, to do pyflink. if so how much would that change my current setup or process i described
 
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
NAME                                     READY   STATUS    RESTARTS   AGE
pod/custom-jar-server-544c4c8f69-jr6st   1/1     Running   0          5d1h
pod/data-team-flink-5c4c767f8d-9w8z8     1/1     Running   0          5d1h
pod/data-team-flink-taskmanager-1-2      1/1     Running   0          5d1h
pod/flink-oauth-proxy-95c575478-czr6v    1/1     Running   0          5d17h
pod/ml-model-server-76bcbdd44b-4wdp8     1/1     Running   0          42h
pod/ml-model-server-76bcbdd44b-bxj67     1/1     Running   0          42h

NAME                           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/custom-jar-server      ClusterIP     <none>        8443/TCP            5d1h
service/data-team-flink        ClusterIP   None             <none>        6123/TCP,6124/TCP   5d1h
service/data-team-flink-rest   ClusterIP       <none>        8081/TCP            5d1h
service/flink-oauth-proxy      ClusterIP       <none>        8080/TCP            5d17h
service/ml-model-server        ClusterIP       <none>        8000/TCP            42h

NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/custom-jar-server   1/1     1            1           5d1h
deployment.apps/data-team-flink     1/1     1            1           5d1h
deployment.apps/flink-oauth-proxy   1/1     1            1           5d17h
deployment.apps/ml-model-server     2/2     2            2           42h

NAME                                           DESIRED   CURRENT   READY   AGE
replicaset.apps/custom-jar-server-544c4c8f69   1         1         1       5d1h
replicaset.apps/data-team-flink-5c4c767f8d     1         1         1       5d1h
replicaset.apps/flink-oauth-proxy-95c575478    1         1         1       5d17h
replicaset.apps/ml-model-server-76bcbdd44b     2         2         2       42h

NAME                                            HOST/PORT                                                                     PATH   SERVICES               PORT   TERMINATION   WILDCARD
hide v          data-team-flink-rest   8081   edge          None
hide             ml-model-server        8000   edge          None



