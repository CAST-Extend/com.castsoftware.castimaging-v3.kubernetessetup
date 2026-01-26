@echo off

set NAMESPACE=castimaging-v3
set NUMBER_OF_ANALYSYS_NODES=3

echo Scaling up... 

kubectl scale deployment  console-postgres               --replicas=1     -n %NAMESPACE%
kubectl rollout status deployment/console-postgres --timeout=0            -n %NAMESPACE% 

kubectl scale deployment  console-sso-service            --replicas=1     -n %NAMESPACE%
kubectl rollout status deployment/console-sso-service --timeout=0         -n %NAMESPACE%
kubectl scale deployment  console-control-panel          --replicas=1     -n %NAMESPACE%
kubectl scale deployment  console-gateway-service        --replicas=1     -n %NAMESPACE%
kubectl scale deployment  console-authentication-service --replicas=1     -n %NAMESPACE%
kubectl scale deployment  console-service                --replicas=1     -n %NAMESPACE%
kubectl scale deployment  console-dashboards             --replicas=1     -n %NAMESPACE%
kubectl scale deployment  extendproxy                    --replicas=1     -n %NAMESPACE%

kubectl scale statefulset viewer-neo4j-core              --replicas=1     -n %NAMESPACE%
kubectl rollout status statefulset/viewer-neo4j-core --timeout=0          -n %NAMESPACE% 
kubectl scale deployment  viewer-server                  --replicas=1     -n %NAMESPACE%
kubectl scale deployment  viewer-etl                     --replicas=1     -n %NAMESPACE%
kubectl scale deployment  viewer-aimanager               --replicas=1     -n %NAMESPACE%
kubectl scale deployment  viewer-api                     --replicas=1     -n %NAMESPACE%
kubectl scale deployment  mcp-server                     --replicas=1     -n %NAMESPACE%

kubectl scale statefulset console-analysis-node-core     --replicas=%NUMBER_OF_ANALYSYS_NODES%     -n %NAMESPACE%
kubectl rollout status statefulset/console-analysis-node-core --timeout=0 -n %NAMESPACE%