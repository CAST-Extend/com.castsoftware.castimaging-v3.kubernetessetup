# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Amazon Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- CAST Imaging Docker images
- Clone the Git repo branch 3.1.1-aks-cast using _git clone -b 3.1.1-aks-cast https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources

## System Requirement and Environment Setup

- AKS environment
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details

## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are available from registry and that Helm and kubectl are installed on your system.


**1. Prepare and Run the installation**

 - Review and adjust the parameter values at the top of the values.yaml file
	- Define K8S provider:
		- K8SProvider: AKS
	- In case a self-signed certificate needs to be used:
		- UseCustomTrustStore: true
			- The CA cert will need to be copied in console-authenticationservice-configmap.yaml
 - Create namespace:
	- Run "kubectl create ns castimaging-v3"
 - Run helm-install.bat


**2. Network Setting**

 - Prepare a CDN like Azure Front Door, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the console-gatewayservice (with a DNS i.e castimagingv3.com).
   The DNS should also have an SSL certificate.
 - Update the _FrontEndHost_ variable in values.yaml
 	- FrontEndHost: dev.imaginghost.com
- Apply helm chart changes:
   	- run helm-upgrade.bat
 - Make configuration for redirecting from DNS to external IP.


**3. Install Extend Proxy (optional)**

 - Pre-requisite: castimaging is already deployed
 - Retrieve the extendproxy service EXTERNAL-IP:
	- run "kubectl get service -n castimaging-v3 extendproxy"
 - In values.yaml, update the exthostname variable with the extendproxy service EXTERNAL-IP value:
	```
	ExtendProxy:
        enable: true
        exthostname: EXTERNAL-IP
	```
 - In values.yaml, also ensure that ExtendProxy.enable is set to true
 - run helm-upgrade.bat
 - Review the log of the extendproxy pod to see the administration URL and extend token
 - "CAST Extend URL" to be configured in Imaging Console: http://EXTERNAL-IP:8085


**4. Configure Extend Proxy**

Use the admin URL shown in extendproxy pod log file to connect to the admin page and configure it.
You can open the log file from the Kubernetes Dashboard.
Alternatively, get the extendproxy pod name by running "kubectl get pods -n castimaging-v3" then run "kubectl logs -n castimaging-v3 castextend-xxxxxxxx" to display the log


**5. Scale down / Scale up CAST Imaging**

You can stop/start CAST Imaging using:

- Util-ScaleDownAll.bat
- Util-ScaleUpAll.bat

 
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