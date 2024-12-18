# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Amazon Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- CAST Imaging Docker images
- Clone the Git repo branch 3.1.1-cloud using _git clone -b 3.1.1-cloud https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources

## System Requirement and Environment Setup

- EKS environment: you may follow the instructions in EKS-ClusterSetup.md to create your EKS cluster
- Retrieve cluster credentials: "aws eks update-kubeconfig --region xx-xxxx-x --name my-cluster"
- Install kubectl and helm
	- For kubectl: 
		- Follow instructions: https://kubernetes.io/docs/tasks/tools/
	- For helm:
		- Binary Download: https://github.com/helm/helm/releases
		- Documentation: https://helm.sh/docs/intro/quickstart
	- Retrieve cluster credentials:
		- aws eks update-kubeconfig --region my-region --name my-cluster

## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are available from registry and that Helm and kubectl are installed on your system.


**1. Prepare and Run the installation**

 - Review and adjust the parameter values at the top of the values.yaml file
	- Define K8S provider:
		- K8SProvider: EKS
 - Create namespace:
	- Run "kubectl create ns castimaging-v3"
 - Run helm-install.bat


**2. Network Setting**

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
    	- run helm-upgrade.bat
	- CAST Imaging will be available at https://xxxxxxxxxxx.cloudfront.net


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
- Update the Security Group of the EFS (check its Network section) to allow access (inbound rule on NFS port 2049) from the Security Group of the Node Instances/AutoScalingGroup
- Proceed with the installation: _1. Run the installation_
