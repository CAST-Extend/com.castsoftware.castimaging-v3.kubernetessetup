# CAST Imaging V3

This Helm Chart is for the deployment of Cast Imaging 3.0.0 on Kubernetes

## Pre-requisites

- Kubernetes
- helm

## Setup

Make sure your kubernetes cluster is up and helm is installed on your system.

Create kubernetes namespace where you want to install Imaging Console system

Below command will create namespace console
```
kubectl create ns castimaging-v3

```

Create Imaging storage
```
# A sample storage configuration based on Persistent Volumes of type "local" is provided for testing purposes.
#                 As "local", those Persistent Volumes are attached to a specific node 
#                 (kubtestx => to be replaced in nodeAffinity section of config files). 
#
# To apply the configuration, first create PV folders (see "Additional configuration steps" section below), then:

kubectl apply -f ex_storageclass.yaml
kubectl apply -f ex_imagingviewer-storage.yaml
kubectl apply -f ex_console-pv.yaml
kubectl apply -f ex_console-pvc.yaml
kubectl apply -f ex_extendproxy-storage.yaml
```
Expose an external IP (LoadBalancer) for the gateway kubernetes service

Prepare a CDN like Azure Front Door, Ingress Service or a web server (e.g., NGINX) as a reverse proxy to host the gateway service (with a DNS i.e castimagingv3.com). The DNS should also have an SSL certificate.

DNS should be updated for NGINX_HOST(authenticationservice) and KC_HOSTNAME, KEYCLOAK_FRONTEND_URL, KC_HOSTNAME_ADMIN_URL(ssoservice) variable in deployment.yml

Make configuration for redirecting from DNS to external IP.

Run below helm command to install Console
```
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .

# Get pods status in kubernetes:

kubectl get pods -n castimaging-v3

```

Additional configuration steps
```
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

To use extend-proxy, prepare an kubernetes serivce with external IP. And for security that should control under a DNS with SSL cerf.
```
