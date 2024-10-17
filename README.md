# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Azure Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- A Kubernetes cluster
- Helm installed on your system (https://helm.sh/docs/intro/quickstart/ )
- kubectl and Azure CLI configured on your system to communicate with your cluster
- CAST Imaging Docker images uploaded to your Azure Container Registry (ACR)
- Clone the Git repo branch 3.0.0-usa using _git clone -b 3.0.0-usa https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources
## System Requirement and Environment Setup

- AKS environment with minimum node VM size B16ms
- AKS v1.29.7 or higher
- Azure/ubuntu Linux SKU
- Azure Container Registry(ACR)
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details
## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are uploaded to ACR and that Helm is installed on your system.

**1. Create a Kubernetes Namespace for CAST Imaging**

Login to Azure instance

``` 
az login 
``` 

Connect Kubernetes client (kubectl) to connect to Azure Kubernetes Service (AKS) cluster created for CAST Imaging deployment. Replace <Resource_Group> with AKS resource group name and <AKS_CLUSTER> with AKS Cluster name.

``` 
az aks get-credentials --resource-group <Resource_Group> --name <AKS_CLUSTER>
```

Create namesapce using below command, it will create namespace with name castimaging-v3

```
kubectl create ns castimaging-v3
```
**2. Update Configuration Files for CAST Imaging**

Update the configuration files before applying them. A sample configuration for Persistent Volumes is available. 

Update **value.yaml** to reflect your deployment environment - Update line 39 with name of node for AKS cluster and name & tag for container images.

    Update the image name and tag based on the available images. 

Modify the storage YAML files for storage requirement specific to your deployment based on the number of application and other parameters.

    ex_console-pv.yaml
    ex_extendproxy-storage.yaml
    ex_imagingviewer-storage.yaml
    
    Optional: If you prefer to use a different name for the storage class instead of the default castimaging-storage, ensure to update all related configuration files accordingly.

Run the below commands to create storage, persistance volume and persistance volumne claim. 

```
kubectl apply -f ex_storageclass.yaml
kubectl apply -f ex_imagingviewer-storage.yaml
kubectl apply -f ex_console-pvc.yaml
kubectl apply -f ex_extendproxy-storage.yaml
```
**3. Install CAST Imaging using Helm**

```
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
```
Get kubernetes pods status, it will approx 2-3 min for PODS to start, PODS viewer-aimanager*, viewer-etl-*, viewer-neo4j-* and viewer-server- will not run successfully. This is expected as additional steps required to make them work.
```
kubectl get pods -n castimaging-v3
```
**4. Additional configuration steps**

**4.1 Network Setting**
 - Prepare a CDN like Azure Front Door, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the console-gatewayservice (with a DNS i.e castimagingv3.com).
   The DNS should also have an SSL certificate.

 - Ensure the DNS is configured for the NGINX_HOST parameter in the templates/console-authenticationservice-deployment.yaml file.
 	- For example, replace NGINX_HOST from default value https://test.castsoftware.com with https://dev.imaginghost.com

 - Update the DNS for the KC_HOSTNAME, KEYCLOAK_FRONTEND_URL, and KC_HOSTNAME_ADMIN_URL parameters in the templates/console-ssoservice-deployment.yaml file.
 	- For example,
    
		Replace KC_HOSTNAME from default value test.castsoftware.com to dev.imaginghost.com

		Replace KEYCLOAK_FRONTEND_URL from default value https://test.castsoftware.com/auth to https://dev.imaginghost.com/auth

 		Replace KC_HOSTNAME_ADMIN_URL from default value https://test.castsoftware.com/auth to https://dev.imaginghost.com/auth

 - Make configuration for redirecting from DNS to external IP.

**4.2 Imaging Viewer folders updates**

To ensure the correct folder setup and permissions, the Viewer pods need to be restarted temporarily as the root user and paused using a **sleep** command

- To restart the pods as root, add the following to the container definition in the deployment YAML file:
  ```
  securityContext:
   runAsUser: 0
  ```
- To pause the process, insert a "sleep 3000" command. For example, in the viewer-etl-deployment.yaml at line 41
  ```
  command: ['sh', '-c', "sleep 3000 && /opt/imaging/imaging-etl/config/init.sh"]
  ```

This will allow the necessary folder and file updates to be made during the pause:

1) To create folders and set permissions: by connecting to the pod with shell from kubernetes dashboard
2) To copy any required configuration files into the pod using the "kubectl cp" command:
   For instance, to copy csv files from the local config folder to the viewer-server pod, get the pod name and run:
```
   kubectl cp config\imaging\neo4j\csv\. castimaging-v3/viewer-server-c6fb588dd-88fwr:/opt/imaging/imaging-service/upload
	
```
Upon completion, root securityContext and sleep command can be removed and pod restarted.

List of updates to be made:

**4.2.1 Updates for Viewer Neo4j**
1) In the viewer-neo4j-statefulset-deployment.yaml file, comment line 50, then un-comment out lines 47, 48, and 51. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
   Check if viewer-neo4j POD is running, if not, scale to 0 and then scale to 1.
	```
 	kubectl scale --replicas=0 statefulset viewer-neo4j-core -n castimaging-v3
 	kubectl scale --replicas=1 statefulset viewer-neo4j-core -n castimaging-v3
   	```
   Get into the pod to execute the commands. Use either Kubernetes Dashboard or  kubectl command.
   For example **kubectl exec -it -n castimaging-v3 viewer-neo4j-core-0 -- /bin/bash**
	```
 	mkdir -p /var/lib/neo4j/config/neo4j5_data
	chmod -R 777 /var/lib/neo4j
	```
2) Files to be copied inside pod, **open a new terminal window** to run below command
   
   **REPLACE** _castimaging-v3/viewer-neo4j-core-0_ with actual namespace/POD name as per deployment environment (Assuming your namespace name is castimaging-v3, You can get the pod name using _kubectl get pods -n castimaging-v3_)
	```
	kubectl cp config\imaging\neo4j\. castimaging-v3/viewer-neo4j-core-0:/var/lib/neo4j/config
   	```
3) Update the file permissions and exit. 
   	```
	chmod -R 777 /var/lib/neo4j
    sudo chmod -R 777 /logs
	```
4) In the viewer-neo4j-statefulset-deployment.yaml file, un-comment line 50, then comment out lines 47, 48 and 51. After saving your changes, execute the following Helm upgrade command:
	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
 	```
 
**4.2.2 Updates for Viewer Server**
1. In the viewer-server-deployment.yaml, comment line 47, then un-comment out lines 46, 49 and 50. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
     Check if viewer-server POD is running, if not, scale to 0 and then scale to 1.
	```
 	kubectl scale --replicas=0 deployment viewer-server -n castimaging-v3
 	kubectl scale --replicas=1 deployment viewer-server -n castimaging-v3
   	```
  
    Get into the pod to execute the commands. Use either Kubernetes Dashboard or  kubectl command. For example **kubectl exec -it -n castimaging-v3 viewer-server-7d9c66448d-4hnxb -- /bin/sh**
	```
	chmod -R 777 /opt/imaging/imaging-service/logs
	chmod -R 777 /opt/imaging/imaging-service/upload
 	chmod -R 777 /opt/imaging/config
	```
2. Files to be copied inside pod,
   
   **REPLACE** _castimaging-v3/viewer-server-7d9c66448d-4hnxb_ with actual namespace/POD name as per deployment environment (Assuming your namespace name is castimaging-v3, You can get the pod name using _kubectl get pods -n castimaging-v3_)
	```
	kubectl cp config\imaging\server\. castimaging-v3/viewer-server-7d9c66448d-4hnxb:/opt/imaging/config
	kubectl cp config\imaging\neo4j\csv\. castimaging-v3/viewer-server-7d9c66448d-4hnxb:/opt/imaging/imaging-service/upload
	```
3. Command to be executed inside the pod
	```
	chmod -R 777 /opt/imaging/imaging-service/logs
	chmod -R 777 /opt/imaging/imaging-service/upload
 	chmod -R 777 /opt/imaging/config
	```
4. In the viewer-server-deployment.yaml file, un-comment line 47, then comment out lines 46, 49 and 50. After saving your changes, execute the following Helm upgrade command:
	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
 	```
   If error "sh: /opt/imaging/config/init.sh: not found" is reported in logs then vi the file /opt/imaging/config/init.sh, if any special character then run command, dos2unix init.sh, repeat point 4. 

 
**4.2.3 Updates for Viewer ETL**
1. In the viewer-etl-deployment.yaml file, comment line 40, then un-comment out lines 41, 43 and 44. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
     Check if viewer-etl POD is running, if not, scale to 0 and then scale to 1.
	```
 	kubectl scale --replicas=0 deployment viewer-etl -n castimaging-v3
 	kubectl scale --replicas=1 deployment viewer-etl -n castimaging-v3
   	```
    Get into the pod to execute the commands. Use either Kubernetes Dashboard or  kubectl command. For example **kubectl exec -it -n castimaging-v3 viewer-etl-6cccc5d569-sk2fm -- /bin/bash**
	```
	chmod -R 777  /opt/imaging/imaging-etl/config
	chmod -R 777  /opt/imaging/imaging-etl/logs
	chmod -R 777  /opt/imaging/imaging-etl/upload
	```
2. Files to be copied inside pod,
   
   **REPLACE** _castimaging-v3/viewer-etl-6cccc5d569-sk2fm_ with actual namespace/POD name as per deployment environment (Assuming your namespace name is castimaging-v3, You can get the pod name using _kubectl get pods -n castimaging-v3_)
	```
	kubectl cp config\imaging\etl\. castimaging-v3/viewer-etl-6cccc5d569-sk2fm:/opt/imaging/imaging-etl/config
	kubectl cp config\imaging\neo4j\csv\. castimaging-v3/viewer-etl-6cccc5d569-sk2fm:/opt/imaging/imaging-etl/upload
	```
3. Command to be executed inside the pod
	```
	chmod -R 777  /opt/imaging/imaging-etl/config
	chmod -R 777  /opt/imaging/imaging-etl/logs
	chmod -R 777  /opt/imaging/imaging-etl/upload
	```
4. In the viewer-etl-deployment.yaml file, un-comment line 40, then comment out lines 41, 43 and 44. After saving your changes, execute the following Helm upgrade command:
	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
 	```

**4.2.4 Updates for Viewer AI Manager**
1) In the viewer-aimanager-deployment.yaml file, comment line 36, then un-comment out lines 37, 39, and 40. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
     Check if viewer-aimanager POD is running, if not, scale to 0 and then scale to 1.
	```
 	kubectl scale --replicas=0 deployment viewer-aimanager -n castimaging-v3
 	kubectl scale --replicas=1 deployment viewer-aimanager -n castimaging-v3
   	```
   Get into the pod to execute the commands. Use either Kubernetes Dashboard or  kubectl command. For example **kubectl exec -it -n castimaging-v3 viewer-aimanager-6cccc5d569-sk2fm -- /bin/bash**
	 ```
	chmod -R 777  /opt/imaging/open_ai-manager/config
	chmod -R 777  /opt/imaging/open_ai-manager/logs
	chmod -R 777  /opt/imaging/open_ai-manager/csv
 	```
2. Files to be copied inside pod,
   
   **REPLACE** _castimaging-v3/viewer-aimanager-78896db4f6-zmbzh_ with actual namespace/POD name as per deployment environment (Assuming your namespace name is castimaging-v3, You can get the pod name using _kubectl get pods -n castimaging-v3_)
	```
	kubectl cp config\imaging\open_ai-manager\. castimaging-v3/viewer-aimanager-78896db4f6-fqn2x:/opt/imaging/open_ai-manager/config
	kubectl cp config\imaging\neo4j\csv\. castimaging-v3/viewer-aimanager-78896db4f6-fqn2x:/opt/imaging/open_ai-manager/csv
	```
3. Command to be executed inside the pod
	```
	chmod -R 777  /opt/imaging/open_ai-manager/config
	chmod -R 777  /opt/imaging/open_ai-manager/logs
	chmod -R 777  /opt/imaging/open_ai-manager/csv
	```
4. In the viewer-aimanager-deployment.yaml file, un-comment line 36, then comment out lines 37, 39, and 40. After saving your changes, execute the following Helm upgrade command:
	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
 	```
     Check if viewer-aimanager POD is running, if not, scale to 0 and then scale to 1.
	```
 	kubectl scale --replicas=0 deployment viewer-aimanager -n castimaging-v3
 	kubectl scale --replicas=1 deployment viewer-aimanager -n castimaging-v3
   	```

**4.2.5 Updates for Extend Proxy**
1) Commands to be executed inside pod:
	```
	chmod -R 777  /opt/cast_extend_proxy
	```

**5. Upload Extensions Bundle for Extend Proxy**

Access the Extend Proxy pod to run the commands needed to retrieve the public URL and API key, which are required for uploading the extensions bundle.
	
```
cat /opt/cast_extend_proxy/config.proxy.json
```
Take note of the PUBLIC_URL and APIKEY from the output, as well as the location of the extarchive file provided by CAST. Update the curl command below by replacing <APIKEY> with the APIKEY, <extend_proxy_url> with the external IP of extendproxy, and <extarchive_file_path> with the path to the extarchive file.

```
curl -H "x-cxproxy-apikey:<API-KEY>" -F "data=@<extarchive_file_path>" <extend_proxy_url>:8085/api/synchronization/bundle/upload

```
After the updates, the curl command will look like this:

_curl -H "x-cxproxy-apikey:**XCGN1-F5172C2698CFF29E0E1EFDC9D21346FE684C81A8698E0833445C3F58269865DEE**" -F "data=@**D:\CAST\CastArchive_linux_x64.extarchive**" **http://172.xx.xxx.232:8085**/api/synchronization/bundle/upload_

Execute the CURL command, and if successful, it will produce output similar to the following: 

{"juid":"2cfee965-774f-1234-b656-f07113e34d83","getStatus":"http://test-nodepool1-123456-vmss000000:8085/api/synchronization?juid=2cfee965-774f-1234-b656-f07113e34d83"}

To validate the extension upload, run the following command, and you should see multiple files with the .nupkg extension in the directory /opt/cast_extend_proxy/data/packages/.

```
ls -l /opt/cast_extend_proxy/data/packages/  
```

**6. (OPTIONAL)Scale the Pods in the order**
Scale the PODs in the order listed if you have to scale for any reason. 

For Console: 
 	```
  	console-postgres -> console-sso-service -> console-control-panel -> console-gateway-service -> console-authentication-service -> console-console-service -> console-analysis-node-core -> console-dashboard
	```

For Viewer: 
  	```
   	viewer-neo4j-core -> viewer-server -> viewer-etl -> viewer-aimanager
	```
 
## Install Kubernetes Dashboard (OPTIONAL)

To install the Kubernetes Dashboard, run the command below. For more information, please refer to the Kubernetes Dashboard documentation at https://github.com/kubernetes/dashboard. Please note that internet access is required to retrieve the Helm repository from https://kubernetes.github.io/dashboard
 	
1. Add the helm repo to your local helm repository 
  	```	
   	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
 	```
2. Run the helm upgrade 
	```
	helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
	```
3. For Helm-based installation when kong is being installed by our Helm chart simply run:
 	```
   	kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
   	```
5. Now access Dashboard at: https://localhost:8443
   
6. Run command to generate the access token required for admin login, login to dashboard and select castimaging-v3 namespace from the dropdown menu to manage Imaging deployment. 
	```
 	kubectl -n kubernetes-dashboard create token admin-user
 	```
## Common Azure CLI and Kubectl commands

_**Login to Azure instance**_

``` 
az login 
``` 

_**Connect Kubernetes client (kubectl) to connect to a specific Azure Kubernetes Service (AKS) cluster**_

``` 
az aks get-credentials --resource-group rg_infra-2024 --name aks-cluster-infra-2024
```

_**Create namespace**_

``` 
kubectl create ns castimaging-v3

``` 

_**Create or update the resources using the YAML file**_

``` 
kubectl apply -f ex_storageclass.yaml
```

_**Copy files into the POD**_

``` 
kubectl cp config\imaging\neo4j\. castimaging-v3/viewer-neo4j-core-0:/var/lib/neo4j/config
```

_**Get the kubernetes POD logs**_
	
 ``` 
 kubectl logs console-gateway-service-67d549bfb4-pvdhj -n castimaging-v3
```

_**Save the kubernetes POD logs to local disk**_

```
kubectl logs console-gateway-service-67d549bfb4-pvdhj -n castimaging-v3 -c console-sso-service > D:\CAST\Logs\console-sso-service.txt
```

_**Execute a command in a running pod within a Kubernetes cluster**_

```
kubectl exec -it console-analysis-node-core-0 -n castimaging-v3 -- /bin/sh
```

_**Get configmap details for specific namespace in Kubernetes cluster**_

```
kubectl get configmap -n castimaging-v3
```

_**Get details of PersistentVolumeClaims(PVC) for specific namespace in Kubernetes cluster**_

```
kubectl get pvc castdir-console-analysis-node-core-0 -n castimaging-v3
```

_**Edit PersistentVolumeClaims(PVC) for specific namespace in Kubernetes cluster**_

```
kubectl edit pvc datadir-console-analysis-node-core-0 -n castimaging-v3
```

_**Copy files from PVC attached to POD to current local drive**_

```
kubectl cp -n castimaging-v3 castimaging-v3/console-analysis-node-core-0:/usr/share/CAST/CASTMS/. .
```


