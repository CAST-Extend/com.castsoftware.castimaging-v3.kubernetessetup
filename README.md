# CAST Imaging V3

This Helm chart facilitates the deployment of CAST Imaging 3.0.0 on a Azure Kubernetes cluster.

## Pre-requisites

- Kubernetes
- helm
- CAST Imaging Docker images

## System Requirement and Environment Setup

- Please refer CAST production documentation for storage requirements https://doc.castsoftware.com/requirements/
- Setup AKS environment with minimum node-vm-size B16ms
- AKS v1.29.7 or Higher
- Azure/ubuntu Linux SKU
- Azure Container Registry(ACR)
- Storage: SSD 500GB (256GB minimum) with option to allow expansion 

## Setup

Ensure that your Kubernetes cluster is running, all the CAST Imaging docker images are uploaded to ACR and that Helm is installed on your system.

**Create a Kubernetes Namespace**

Define the namespace where CAST Imaging will be installed. Use the following command to create the namespace:

```
kubectl create ns castimaging-v3

```
**Configure configuration files for CAST Imaging**

A sample configuration for Persistent Volumes is available. To apply this storage configuration, clone the Git repository and update the configuration files before using it. 
1. Update value.yaml file specific to your deployment environment
   - update the image name and tag based on images  
2. Update yaml file for persistant volumne and storage to replace <your-subscription-id> and <your-resource-group> with actual values for subscription-id and resource group name.
   - ex_console-pv.yaml
   - ex_extendproxy-storage.yaml
   - ex_imagingviewer-storage.yaml
```
kubectl apply -f ex_storageclass.yaml
kubectl apply -f ex_imagingviewer-storage.yaml
kubectl apply -f ex_console-pv.yaml
kubectl apply -f ex_console-pvc.yaml
kubectl apply -f ex_extendproxy-storage.yaml
```
**Install CAST Imaging**

Run below helm command to install Console
```
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .

# Get pods status in kubernetes:

kubectl get pods -n castimaging-v3

```

Additional configuration steps
```

#---------------------
# Network Setting
#--------------------
 - Expose an external IP (LoadBalancer) for the gateway kubernetes service
 - Prepare a CDN like Azure Front Door, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the gateway service (with a DNS i.e castimagingv3.com). The DNS should also have an SSL certificate.
 - DNS should be updated for NGINX_HOST value in console-authenticationservice-deployment.yaml and KC_HOSTNAME, KEYCLOAK_FRONTEND_URL, KC_HOSTNAME_ADMIN_URL(ssoservice) variable in deployment.yml
 - Make configuration for redirecting from DNS to external IP.

# ----------------
# Database updates
# ----------------

update admin_center.properties set
value = '/shared/delivery'  where prop_key = 'application.paths.delivery-folder';
update admin_center.properties set
value = '/shared/deploy'  where prop_key = 'application.paths.deploy-folder';
update admin_center.properties set
value = '/shared/common-data' where prop_key = 'application.paths.shared-folder';

# ------------------------------------------
# Imaging Viewer folders updates
# ------------------------------------------

In order to create some required folders and permissions, Viewer pods will need to be temporarily re-started as root and put on hold using a "sleep" command.
-> To restart as root, add this in the deployment yaml file, at container definition level:
          securityContext:
            runAsUser: 0
-> To put them on hold, insert a "sleep 30000" command. For instance, in the viewer-etl-deployment.yaml:
line 40:		command: ['sh', '-c', "sleep 30000;/opt/imaging/imaging-etl/config/init.sh"]

It will then become possible to perform the necessary folders and files updates:

1) To create folders and set permissions: by connecting to the pod with shell from kubernetes dashboard
	1.1) Create the below folders in the console-analysis-node
	  	/shared/common-data
	  	/shared/delivery
	  	/shared/deploy
	1.2) Set the permissions for the folders created
	 	sudo chmod 777 /shared
	 	sudo chmod -R 777 /shared/*
2) To copy any required configuration files into the pod using the "kubectl cp" command:
   For instance, to copy csv files from the local config folder to the viewer-server pod, get the pod name and run:
   > kubectl cp .\config\imaging\neo4j\csv\. viewer-server-c6fb588dd-88fwr:/opt/imaging/imaging-service/upload

Upon completion, root securityContext and sleep command can be removed and pod restarted.


# neo4j:
1) Command to be executed inside pod:
	mkdir -p /var/lib/neo4j/config/neo4j5_data
	chmod -R 777 /var/lib/neo4j
2) Files to be copied inside pod
	config\imaging\neo4j\. -> /var/lib/neo4j/config

# server:
1) Command to be executed inside pod:
	chmod -R 777 /opt/imaging/imaging-service/logs
	chmod -R 777 /opt/imaging/imaging-service/upload
2) Files to be copied inside pod
	config\imaging\server\. -> /opt/imaging/config
	config\imaging\neo4j\csv\. -> /opt/imaging/imaging-service/upload

# etl:
1) Command to be executed inside pod:
	chmod -R 777  /opt/imaging/imaging-etl/config
	chmod -R 777  /opt/imaging/imaging-etl/log
	chmod -R 777  /opt/imaging/imaging-etl/upload
2) Files to be copied inside pod
	config\imaging\etl\. -> /opt/imaging/imaging-etl/config
	config\imaging\neo4j\csv\. -> /opt/imaging/imaging-etl/upload

# aimanager:
1) Command to be executed inside pod:
	chmod -R 777  /opt/imaging/open_ai-manager/config
	chmod -R 777  /opt/imaging/open_ai-manager/log
	chmod -R 777  /opt/imaging/open_ai-manager/upload
2) Files to be copied inside pod
	config\imaging\open_ai-manager/* -> /opt/imaging/open_ai-manager/config
	config\imaging\neo4j\csv\. -> /opt/imaging/open_ai-manager/csv

# extend-proxy:
1) Command to be executed inside pod:
        chmod -R 777  /opt/cast_extend_proxy

To use extend-proxy, prepare a kubernetes serivce with external IP. And for security that should control under a DNS with SSL cerf.
```
