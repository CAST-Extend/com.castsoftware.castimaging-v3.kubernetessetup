@echo off

if "%~1"=="" (set NAMESPACE=castimaging-v3) else (set NAMESPACE=%~1)

echo Scaling up... 

kubectl scale statefulset  console-postgres               --replicas=1 -n %NAMESPACE%
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
REM With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
REM and its autoscaler (stopped by Util-ScaleDownAll) must be restarted
set AN_STS=statefulsets.apps
kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n %NAMESPACE% >nul 2>&1
if not errorlevel 1 set AN_STS=statefulsets.apps.kruise.io
kubectl scale %AN_STS% console-analysis-node-core --replicas=1 -n %NAMESPACE%
kubectl get deployment console-analysis-node-autoscaler -n %NAMESPACE% >nul 2>&1
if not errorlevel 1 kubectl scale deployment console-analysis-node-autoscaler --replicas=1 -n %NAMESPACE%
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
kubectl scale deployment  viewer-api                      --replicas=1 -n %NAMESPACE%
timeout /t 10 /nobreak >nul
kubectl scale deployment  extendproxy                    --replicas=1 -n %NAMESPACE%
kubectl scale deployment  mcp-server                     --replicas=1 -n %NAMESPACE%