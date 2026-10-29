@echo off

if "%~1"=="" (set NAMESPACE=castimaging-v3) else (set NAMESPACE=%~1)

echo Scaling down...

REM With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
REM and its autoscaler must be stopped first or it scales the analysis node back up
kubectl get deployment console-analysis-node-autoscaler -n %NAMESPACE% >nul 2>&1
if not errorlevel 1 kubectl scale deployment console-analysis-node-autoscaler --replicas=0 -n %NAMESPACE%
set AN_STS=statefulsets.apps
kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n %NAMESPACE% >nul 2>&1
if not errorlevel 1 set AN_STS=statefulsets.apps.kruise.io

kubectl scale deployment  console-dashboards             --replicas=0 -n %NAMESPACE%
kubectl scale %AN_STS% console-analysis-node-core --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-service                --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-authentication-service --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-gateway-service        --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-control-panel          --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-sso-service            --replicas=0 -n %NAMESPACE%
kubectl scale statefulset console-postgres               --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-aimanager               --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-api                     --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-etl                     --replicas=0 -n %NAMESPACE%
kubectl scale deployment  viewer-server                  --replicas=0 -n %NAMESPACE%
kubectl scale statefulset viewer-neo4j-core              --replicas=0 -n %NAMESPACE%
kubectl scale deployment  extendproxy                    --replicas=0 -n %NAMESPACE%
kubectl scale deployment  mcp-server                     --replicas=0 -n %NAMESPACE%