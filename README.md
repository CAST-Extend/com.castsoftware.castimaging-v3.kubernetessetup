# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Azure Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- A Kubernetes cluster
- Helm installed on your local machine (https://helm.sh/docs/intro/quickstart/ )
- kubectl and Azure CLI configured to communicate with your cluster
- CAST Imaging Docker images uploaded to your Azure Container Registry (ACR)
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources
## System Requirement and Environment Setup

- AKS environment with minimum node VM size B16ms
- AKS v1.29.7 or higher
- Azure/ubuntu Linux SKU
- Azure Container Registry(ACR)
- Storage: SSD 500GB (256GB minimum) with the option to allow expansion
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details
## Installation Steps for CAST Imaging

Ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are uploaded to ACR and that Helm is installed on your system.

**1. Create a Kubernetes Namespace for CAST Imaging**

```
kubectl create ns castimaging-v3
```
**2. Update Configuration Files for CAST Imaging**

A sample configuration for Persistent Volumes is available. Clone the Git repository and update the configuration files before applying them. 

Update **value.yaml** to reflect your deployment environment

    Update the image name and tag based on the available images. 

Modify the persistent volume and storage YAML files to replace <your-subscription-id>, <your-resource-group> and agent pool for nodeAffinity with your actual subscription ID, resource group name and aks agent pool name.

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
Get kubernetes pods status 
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
    Get into the pod to execute the commands (You can use Kubernetes Dashboard or command kubectl exec like 'kubectl exec -it viewer-neo4j-core-0 -- /bin/bash'
	```
 	mkdir -p /var/lib/neo4j/config/neo4j5_data
	chmod -R 777 /var/lib/neo4j
	```
2) Files to be copied inside pod
   
   **REPLACE** _castimaging-v3/viewer-neo4j-core-0_ with actual namespace/POD name as per deployment environment (Assuming your namespace name is castimaging-v3, You can get the pod name using _kubectl get pods -n castimaging-v3_)
	```
	kubectl cp config\imaging\neo4j\. castimaging-v3/viewer-neo4j-core-0:/var/lib/neo4j/config
   	```
4) Update the file permissions
   	```
	chmod -R 777 /var/lib/neo4j
	```
**4.2.2 Updates for Viewer Server**
1. In the viewer-server-deployment.yaml, comment line 47, then un-comment out lines 46, 49 and 50. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
    Get into the pod to execute the commands (You can use Kubernetes Dashboard or command kubectl exec like 'kubectl exec -it viewer-server-7d9c66448d-4hnxb -- /bin/bash'
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
4. In the viewer-etl-deployment.yaml file, un-comment line 47, then comment out lines 46, 49 and 50. After saving your changes, execute the following Helm upgrade command:
	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
 	```
 
**4.2.3 Updates for Viewer ETL**
1. In the viewer-etl-deployment.yaml file, comment line 40, then un-comment out lines 41, 43 and 44. After saving your changes, execute the following Helm upgrade command:
	 ```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
  	 ```
    Get into the pod to execute the commands (You can use Kubernetes Dashboard or command kubectl exec like 'kubectl exec -it viewer-etl-6cccc5d569-sk2fm -- /bin/bash'
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
   Get into the pod to execute the chmod commands (You can use Kubernetes Dashboard or command kubectl exec like 'kubectl exec -it viewer-etl-6cccc5d569-sk2fm -- /bin/bash'
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
   
**4.2.5 Updates for Extend Proxy**
1) Commands to be executed inside pod:
	```
	chmod -R 777  /opt/cast_extend_proxy
	```
To use extend-proxy, prepare a kubernetes serivce with external IP. And for security that should control under a DNS with SSL cerf.

**5. Scale the Pods in the order**
	
For Console: 
 	```
  	console-postgres -> console-ssoservice -> console-controlpanel -> console-gatewayservice -> console-authenticationservice -> console-consoleservice -> console-analysisnode
	```

For Viewer: 
  	```
   	viewer-neo4j -> viewer-server -> viewer-etl -> viewer-aimanager
	```
 
## Install Kubernetes Dashboard

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

_**Save the kubernetes POD logs to local disk**_

```
kubectl edit pvc datadir-console-analysis-node-core-0 -n castimaging-v3
```
