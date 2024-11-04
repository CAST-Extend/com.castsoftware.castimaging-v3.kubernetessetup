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


**1. Run the installation**

 - helm-install.bat


**2. Network Setting**

 - Prepare a CDN like Azure Front Door, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the console-gatewayservice (with a DNS i.e castimagingv3.com).
   The DNS should also have an SSL certificate.
 - Update the _FrontEndHost_ variable in values.yaml
 	- FrontEndHost: dev.imaginghost.com
- Apply helm chart changes:
   	- run helm-upgrade.bat
 - Make configuration for redirecting from DNS to external IP.


**3. Install Extend Proxy (optional)**

 - Rename template/ex_extendproxy-service.yaml into template/extendproxy-service.yaml
 - Apply helm chart changes:
	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.1.1 ."
 - Get the extendproxy service EXTERNAL-IP:
	- run "kubectl get service -n castimaging-v3 extendproxy"
 - Update the exthostname variable in values.yaml with this value, for instance:
	```
	ExtendProxy:
          exthostname: w.x.y.z
	```
 - Rename template/ex_extendproxy-deployment.yaml into template/extendproxy-deployment.yaml
 - Apply helm chart changes:
	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.1.1 ."
 - Review the log of the extendproxy pod to see the administration URL and extend token


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