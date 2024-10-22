echo ARE YOU SURE?
pause
pause
kubectl delete pvc -n castimaging-v3 db-data
kubectl delete pvc -n castimaging-v3 castdir-console-analysis-node-core-0 
kubectl delete pvc -n castimaging-v3 confdir-viewer-neo4j-core-0          
kubectl delete pvc -n castimaging-v3 datadir-console-analysis-node-core-0                             
kubectl delete pvc -n castimaging-v3 logdir-viewer-neo4j-core-0           
kubectl delete pvc -n castimaging-v3 pvc-extendproxy-data                 
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-aimanager-config
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-aimanager-csv   
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-aimanager-logs  
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-etl-config      
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-etl-logs        
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-etl-upload      
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-server-config   
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-server-csv      
kubectl delete pvc -n castimaging-v3 pvc-imagingviewer-v3-server-log      