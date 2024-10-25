set NAMESPACE=castimaging-v3
echo ABOUT TO DELETE ALL PVCs IN %NAMESPACE%, ARE YOU SURE?
pause
echo PLEASE CONFIRM DELETION (this will also permanently delete the PVs).
pause
kubectl delete pvc -n %NAMESPACE% db-data
kubectl delete pvc -n %NAMESPACE% castdir-console-analysis-node-core-0 
kubectl delete pvc -n %NAMESPACE% confdir-viewer-neo4j-core-0          
kubectl delete pvc -n %NAMESPACE% datadir-console-analysis-node-core-0                             
kubectl delete pvc -n %NAMESPACE% logdir-viewer-neo4j-core-0           
kubectl delete pvc -n %NAMESPACE% pvc-extendproxy-data                 
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-aimanager-config
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-aimanager-csv   
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-aimanager-logs  
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-etl-config      
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-etl-logs        
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-etl-upload      
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-server-config   
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-server-csv      
kubectl delete pvc -n %NAMESPACE% pvc-imagingviewer-v3-server-log      