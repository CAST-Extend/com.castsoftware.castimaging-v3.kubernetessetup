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
# -------------------
# Update config files
# -------------------
# app.config in etl, server, aimanager
# nginx.conf in server

# ----------------
# Database updates
# ----------------
update admin_center.properties set
value = 'console-postgres.castimaging-v3.svc.cluster.local' where prop_key = 'database.host';

update admin_center.properties set
value = 'http://console-gateway-service.castimaging-v3.svc.cluster.local:8090' where prop_key = 'keycloak.uri';

--update admin_center.properties set
--value = 'console-control-panel.castimaging-v3.svc.cluster.local' where prop_key = 'eureka.host';

update admin_center.properties set
value = '/shared/delivery'  where prop_key = 'application.paths.delivery-folder';
update admin_center.properties set
value = '/shared/deploy'  where prop_key = 'application.paths.deploy-folder';
update admin_center.properties set
value = '/shared/common-data' where prop_key = 'application.paths.shared-folder';

# ------------------
# Console PV folders
# ------------------
sudo rm -r /home/jar/pv/console-v3-db-data /home/jar/pv/console-v3-analysis-node-data /home/jar/pv/console-v3-analysis-node-cast* /home/jar/pv/console-v3-restapi-domains
sudo mkdir -p /home/jar/pv/console-v3-db-data /home/jar/pv/console-v3-restapi-domains
sudo mkdir -p /home/jar/pv/console-v3-analysis-node-cast0/CAST/Logs /home/jar/pv/console-v3-analysis-node-cast0/CASTMS/LISA
sudo mkdir -p /home/jar/pv/console-v3-analysis-node-cast1/CAST/Logs /home/jar/pv/console-v3-analysis-node-cast1/CASTMS/LISA
sudo mkdir -p /home/jar/pv/console-v3-analysis-node-cast2/CAST/Logs /home/jar/pv/console-v3-analysis-node-cast2/CASTMS/LISA
sudo mkdir -p /home/jar/pv/console-v3-analysis-node-data/deploy  /home/jar/pv/console-v3-analysis-node-data/delivery  /home/jar/pv/console-v3-analysis-node-data/common-data
sudo chmod -R 777 /home/jar/pv/console-v3-db-data /home/jar/pv/console-v3-analysis-node-data /home/jar/pv/console-v3-analysis-node-cast* /home/jar/pv/console-v3-restapi-domains

# ----------------------
# ExtendProxy PV folders
# ----------------------
sudo rm -r /home/jar/pv/console-v3-extendproxy
sudo mkdir -p /home/jar/pv/console-v3-extendproxy
sudo chmod 777 /home/jar/pv/console-v3-extendproxy

# ------------------------------------------
# Imaging Viewer PV folders and config files
# ------------------------------------------
# neo4j:
sudo rm -r /home/jar/pv/imagingviewer-v3/neo4j
sudo mkdir -p /home/jar/pv/imagingviewer-v3/neo4j/logs /home/jar/pv/imagingviewer-v3/neo4j/config /home/jar/pv/imagingviewer-v3/neo4j/config/neo4j5_data
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/neo4j/* /home/jar/pv/imagingviewer-v3/neo4j/config
sudo chmod -R 777  /home/jar/pv/imagingviewer-v3/neo4j
# server:
sudo rm -r /home/jar/pv/imagingviewer-v3/server
sudo mkdir -p /home/jar/pv/imagingviewer-v3/server/logs /home/jar/pv/imagingviewer-v3/server/config /home/jar/pv/imagingviewer-v3/server/csv
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/server/* /home/jar/pv/imagingviewer-v3/server/config
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/neo4j/csv/* /home/jar/pv/imagingviewer-v3/server/csv
sudo chmod -R 777  /home/jar/pv/imagingviewer-v3/server
# etl:
sudo rm -r /home/jar/pv/imagingviewer-v3/etl
sudo mkdir -p /home/jar/pv/imagingviewer-v3/etl/config /home/jar/pv/imagingviewer-v3/etl/logs /home/jar/pv/imagingviewer-v3/etl/upload
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/etl/* /home/jar/pv/imagingviewer-v3/etl/config
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/neo4j/csv/* /home/jar/pv/imagingviewer-v3/etl/upload
sudo chmod -R 777  /home/jar/pv/imagingviewer-v3/etl
# aimanager:
sudo rm -r /home/jar/pv/imagingviewer-v3/aimanager
sudo mkdir -p /home/jar/pv/imagingviewer-v3/aimanager/config /home/jar/pv/imagingviewer-v3/aimanager/logs /home/jar/pv/imagingviewer-v3/aimanager/csv
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/open_ai-manager/* /home/jar/pv/imagingviewer-v3/aimanager/config
sudo cp -r /home/jar/CastImaging-v3_Helm/config/imaging/neo4j/csv/* /home/jar/pv/imagingviewer-v3/aimanager/csv
sudo chmod -R 777  /home/jar/pv/imagingviewer-v3/aimanager

```