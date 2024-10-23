# CAST Imaging Version 3.x

This guide outlines the process for setting up **CAST Imaging** in a **Amazon Kubernetes Cluster environment** using Helm charts.

## Prerequisites

- CAST Imaging Docker images
- Clone the Git repo branch 3.0.0-eks-cast using _git clone -b 3.0.0-eks-cast https://github.com/CAST-Extend/com.castsoftware.castimaging-v3.kubernetessetup_
- A valid CAST Imaging License
- OPTIONAL: Deploy Kubernetes Dashboard (https://github.com/kubernetes/dashboard) to troubleshoot containers, and manage the cluster resources

## System Requirement and Environment Setup

- EKS environment: follow the instructions in EKS-Setup.md to create your EKS cluster
- Refer to the CAST product documentation https://doc.castsoftware.com for any additional details

## Installation Steps for CAST Imaging

Before starting the installation, ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are available from registry and that Helm and kubectl are installed on your system.

Before procedding, you have to validate the name of the Storage Class name to be used during the setup of Persistent volumes:
 - Run "kubectl get sc" to see the available Storage Classes. For instance:

		NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
 		gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  5d15h

 - Update values.yaml file with the name of the Storage Class (usually gp2 or gp3):

		storage:
  			className: gp2  # Reference storage class

**1. Run the installation batch**

 - install-castimaging.bat


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
			- Name: _castimging-v3_
			- Web Application Firewall: _Do not enable security protections_
			- _Description (optional)_: enter a description
			- Click _Create Distribution_ 
		- Go to _Behaviors_ tab
			- Delete all behaviors except the _Default (*)_ one
			- In _Viewer protocol policy_: select _HTTPS only_
	- Open the Distribution that has just been created and copy the _Distribution domain name_ value
	- Update the _CloudFrontDomain_ variable in values.yaml
		- CloudFrontDomain: xxxxxxxxxxx.cloudfront.net
 	- Apply helm chart changes:
    	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 ."
	- CAST Imaging will be available at https://xxxxxxxxxxx.cloudfront.net


**3. Install Extend Proxy (optional)**

 - Rename template/ex_extendproxy-service.yaml into template/extendproxy-service.yaml
 - Apply helm chart changes:
	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 ."
 - Get the extendproxy service EXTERNAL-IP:
	- run "kubectl get service -n castimaging-v3 extendproxy"
	- For instance: a3330000000000452xxxxxxxxxxx-1907755555.us-east-2.elb.amazonaws.com
 - Update the exthostname variable in values.yaml with this value, for instance:
	```
	ExtendProxy:
          exthostname: a3330000000000452xxxxxxxxxxx-1907755555.us-east-2.elb.amazonaws.com
	```
 - Rename template/ex_extendproxy-deployment.yaml into template/extendproxy-deployment.yaml
 - Apply helm chart changes:
	- run "helm upgrade castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 ."
 - Review the log of the extendproxy pod to see the administration URL and extend token


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