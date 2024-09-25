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

Run below helm command to install Console
```
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .

# Get pods status in kubernetes:

kubectl get pods -n castimaging-v3

# Once all pods are "Running", access Imaging Console on http://console-gateway-service-xxx:8090
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

In order to create the some required folders and permissions, Viewer pods will need to be temporarily re-started as root and put on hold using a "sleep" command.
-> To restart as root, add this in the deployment yaml file, at container definition level:
          securityContext:
            runAsUser: 0
-> To put them on hold, insert a "sleep 30000" command. For instance, in the viewer-etl-deployment.yaml:
line 40:		command: ['sh', '-c', "sleep 30000;/opt/imaging/imaging-etl/config/init.sh"]

It will then besome possible to perform the necessary folders and files updates:

1) To create folders and set permissions: by connecting to the pod with shell from kubernetes dashboard
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

```
