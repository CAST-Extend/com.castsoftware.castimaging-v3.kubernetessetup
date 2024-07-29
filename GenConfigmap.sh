kubectl create configmap -n castimaging-v3 neo4jconf --from-file=/home/jar/CastImaging-v3_Helm/config/imaging/neo4j/configuration/neo4j.conf --dry-run=client -o yaml > templates/viewer-neo4j-configmap.yaml

kubectl create configmap -n castimaging-v3 etlappconfig --from-file=/home/jar/CastImaging-v3_Helm/config/imaging/etl/app.config --dry-run=client -o yaml > templates/viewer-etl-configmap.yaml

kubectl create configmap -n castimaging-v3 openaiappconfig --from-file=/home/jar/CastImaging-v3_Helm/config/imaging/open_ai-manager/app.config --dry-run=client -o yaml > templates/viewer-aimanager-configmap.yaml

kubectl create configmap -n castimaging-v3 servernginxconf --from-file=/home/jar/CastImaging-v3_Helm/config/imaging/server/nginx/conf/nginx.conf --dry-run=client -o yaml > templates/viewer-server-configmap.yaml
echo --- >> templates/viewer-server-configmap.yaml
kubectl create configmap -n castimaging-v3 serverappconfig --from-file=/home/jar/CastImaging-v3_Helm/config/imaging/server/app.config --dry-run=client -o yaml >> templates/viewer-server-configmap.yaml
