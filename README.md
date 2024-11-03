# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Amazon Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- CAST Imaging Docker images
- Clone the Git repo branch 3.1.1-eks-cast using _git clone -b 3.1.1-eks-cast https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources

## System Requirement and Environment Setup

- EKS environment: follow the instructions in EKS-Setup.md to create your EKS cluster
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details

## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are available from registry and that Helm and kubectl are installed on your system.


**1. Network Setting**

 - AWS CloudFront setup:
    - Get the console-gateway-service service EXTERNAL-IP:
    	- run "kubectl get service -n castimaging-v3 console-gateway-service"
    	- For instance: _a8ec2379b09fexxxxxxxxx-532570000.us-east-2.elb.amazonaws.com_
	- Create a new CloudFront in AWS Console
		- In AWS Console, go to CloudFront and click _Create distribution_
			- Set "Origin domain" value to the console-gateway-service service EXTERNAL-IP
				- For instance: _a8ec2379b09fexxxxxxxxx-532570000.us-east-2.elb.amazonaws.com_
			- Protocol: _HTTP only_
			- HTTP Port: _8090_
			- Name: _castimaging-v3_
			- Web Application Firewall: _Do not enable security protections_
			- _Description (optional)_: enter a description
            - IPv6: _Off_
			- Click _Create Distribution_ 
		- Go to _Behaviors_ tab
			- In _Viewer protocol policy_: select _HTTPS only_
	- Open the Distribution that has just been created and copy the _Distribution domain name_ value
	- Update the _FrontEndHost_ variable in values.yaml
		- FrontEndHost: xxxxxxxxxxx.cloudfront.net
 	- Apply helm chart changes:
    	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.1.1 ."
	- CAST Imaging will be available at https://xxxxxxxxxxx.cloudfront.net


**2. Run the installation**

 - helm-install.bat


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

## Setup an AWS EFS - Elastic File Storage (OPTIONAL)

All pods will use EBS (block storage) by default.
For the console-analysis-node StatefulSet, it is however possible to configure an EFS (file storage) in order to enable file sharing and thus, scale-up (ability to run more than one console-analysis-node pod, when needed).

Prior to running the initial helm-install, follow these steps:
- Create an EFS:
	- Open AWS Console and go to EFS:
		- Press _Create file system_
		- Assign a _Name_
		- Press _Create_
	- Create an Access Point inside the new EFS:
		- Select the _Access point_ tab
		- Press _Create access point_
			- Name: castimaging-shared-datadir
			- Root directory path: /castimaging-shared-datadir
			- Root directory creation permissions
				- Owner user ID: 10001
				- Owner group ID: 10001
				- Access point permissions: 0777
			- Press _Create access point_
	- Copy the newly created _File System ID_ and _Access point ID_
- Rename templates/ex_storage-bsfs.yaml into templates/storage-bsfs.yaml
- Rename templates/storage-bs.yaml into templates/ex_storage-bs.yaml
- Update the EFSsystemID and EFSaccessPointID variables in values.yaml
- Update the Security Group of the EFS to allow access (inbound rule) from the NodeGroup Security Group of the EKS cluster, on port 2049 (NFS)
- Proceed with the installation: _1. Run the installation_
