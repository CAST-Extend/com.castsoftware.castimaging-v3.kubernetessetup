#!/bin/bash

NAMESPACE=castimaging-v3
NUMBER_OF_ANALYSYS_NODES=1

echo "Scaling up..."

kubectl scale statefulset  console-postgres               --replicas=1     -n "$NAMESPACE"
kubectl rollout status statefulset/console-postgres --timeout=0            -n "$NAMESPACE"

kubectl scale deployment  console-sso-service            --replicas=1     -n "$NAMESPACE"
kubectl rollout status deployment/console-sso-service --timeout=0         -n "$NAMESPACE"
kubectl scale deployment  console-control-panel          --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  console-gateway-service        --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  console-authentication-service --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  console-service                --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  console-dashboards             --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  extendproxy                    --replicas=1     -n "$NAMESPACE"

kubectl scale statefulset viewer-neo4j-core              --replicas=1     -n "$NAMESPACE"
kubectl rollout status statefulset/viewer-neo4j-core --timeout=0          -n "$NAMESPACE"
kubectl scale deployment  viewer-server                  --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  viewer-etl                     --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  viewer-aimanager               --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  viewer-api                     --replicas=1     -n "$NAMESPACE"
kubectl scale deployment  mcp-server                     --replicas=1     -n "$NAMESPACE"

# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet
# (rollout status does not support it) and its autoscaler must be restarted
if kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl scale statefulsets.apps.kruise.io console-analysis-node-core --replicas="$NUMBER_OF_ANALYSYS_NODES" -n "$NAMESPACE"
    if kubectl get deployment console-analysis-node-autoscaler -n "$NAMESPACE" >/dev/null 2>&1; then
        kubectl scale deployment console-analysis-node-autoscaler --replicas=1 -n "$NAMESPACE"
    fi
    kubectl wait statefulsets.apps.kruise.io/console-analysis-node-core --for=jsonpath='{.status.readyReplicas}'="$NUMBER_OF_ANALYSYS_NODES" --timeout=-1s -n "$NAMESPACE"
else
    kubectl scale statefulset console-analysis-node-core     --replicas="$NUMBER_OF_ANALYSYS_NODES"     -n "$NAMESPACE"
    kubectl rollout status statefulset/console-analysis-node-core --timeout=0 -n "$NAMESPACE"
fi