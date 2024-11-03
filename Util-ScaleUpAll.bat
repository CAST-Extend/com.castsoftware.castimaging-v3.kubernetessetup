@echo off

set NAMESPACE=castimaging-v3

echo Scaling up... 

kubectl scale deployment  console-postgres               --replicas=1 -n %NAMESPACE%
timeout /t 20 /nobreak >nul
kubectl scale deployment  console-sso-service            --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  console-control-panel          --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  console-gateway-service        --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  console-authentication-service --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  console-service                --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale statefulset console-analysis-node-core      --replicas=1 -n %NAMESPACE%
timeout /t 1  /nobreak >nul
kubectl scale deployment console-dashboards              --replicas=1 -n %NAMESPACE%

kubectl scale statefulset viewer-neo4j-core              --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  viewer-server                  --replicas=1 -n %NAMESPACE%
timeout /t 1  /nobreak >nul
kubectl scale deployment  viewer-etl                     --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  viewer-aimanager                --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
REM kubectl scale deployment  extendproxy                    --replicas=1 -n %NAMESPACE%