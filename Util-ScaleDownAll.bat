@echo off

set NAMESPACE=castimaging-v3

echo Scaling down... 

kubectl scale deployment  console-dashboards             --replicas=0 -n %NAMESPACE%
kubectl scale statefulset console-analysis-node-core     --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-service                --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-authentication-service --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-gateway-service        --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-control-panel          --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-sso-service            --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-postgres               --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-aimanager               --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-etl                     --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-server                  --replicas=0 -n %NAMESPACE%
kubectl scale statefulset viewer-neo4j-core              --replicas=0 -n %NAMESPACE%
REM kubectl scale deployment  extendproxy                    --replicas=0 -n %NAMESPACE%

timeout /t 30 /nobreak >nul