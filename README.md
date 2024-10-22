# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Amazon Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- A Kubernetes cluster
- Helm installed on your system (https://helm.sh/docs/intro/quickstart/ )
- kubectl and EKS CLI configured on your system to communicate with your cluster
- CAST Imaging Docker images
- Clone the Git repo branch 3.0.0-eks-cast using _git clone -b 3.0.0-eks-cast https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources

## System Requirement and Environment Setup

- EKS environment: follow the instructions in EKS-Setup.md to create your EKS cluster
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details
## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are available from registry and that Helm is installed on your system.

**1. Run the installation batch**

c:\templatefolder\install-castimaging.bat


**2. Network Setting**

 - Prepare a CDN, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the console-gatewayservice (with a DNS i.e castimagingv3.com).
   The DNS should also have an SSL certificate.

 - Ensure the DNS is configured for the NGINX_HOST parameter in the templates/console-authenticationservice-deployment.yaml file.
 	- For example, replace NGINX_HOST from default value https://test.castsoftware.com with https://dev.imaginghost.com

 - Update the DNS for the KC_HOSTNAME, KEYCLOAK_FRONTEND_URL, and KC_HOSTNAME_ADMIN_URL parameters in the templates/console-ssoservice-deployment.yaml file.
 	- For example,
    
		Replace KC_HOSTNAME from default value test.castsoftware.com to dev.imaginghost.com

		Replace KEYCLOAK_FRONTEND_URL from default value https://test.castsoftware.com/auth to https://dev.imaginghost.com/auth

 		Replace KC_HOSTNAME_ADMIN_URL from default value https://test.castsoftware.com/auth to https://dev.imaginghost.com/auth

 - Make configuration for redirecting from DNS to external IP.


**3. Install Extend Proxy**

Follow instructions in install-extendproxy.bat

**4. Configure Extend Proxy**

Use the admin URL shown in extendproxy pod log file to connect to the admin page and configure it.
You can open the log file from the Kubernetes Dashboard.
Alternatively, get the extendproxy pod name by running "kubectl get pods -n castimaging-v3" then run "kubectl logs -n castimaging-v3 castextend-xxxxxxxx" to display the log

**5. (OPTIONAL)Scale the Pods in the order**
Scale the PODs in the order listed if you have to scale for any reason. 

For Console: 
 	```
  	console-postgres -> console-ssoservice -> console-controlpanel -> console-gatewayservice -> console-authenticationservice -> console-consoleservice -> console-analysisnode
	```

For Viewer: 
  	```
   	viewer-neo4j -> viewer-server -> viewer-etl -> viewer-aimanager
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