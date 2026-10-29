#!/bin/bash

NAMESPACE=${1:-castimaging-v3}

echo "Scaling down..."

# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
# and its autoscaler must be stopped first or it scales the analysis node back up
if kubectl get deployment console-analysis-node-autoscaler -n $NAMESPACE >/dev/null 2>&1; then
    kubectl scale deployment console-analysis-node-autoscaler --replicas=0 -n $NAMESPACE
fi
AN_STS="statefulsets.apps"
if kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n $NAMESPACE >/dev/null 2>&1; then
    AN_STS="statefulsets.apps.kruise.io"
fi

kubectl scale deployment console-dashboards --replicas=0 -n $NAMESPACE
kubectl scale $AN_STS console-analysis-node-core --replicas=0 -n $NAMESPACE
kubectl scale deployment console-service --replicas=0 -n $NAMESPACE
kubectl scale deployment console-authentication-service --replicas=0 -n $NAMESPACE
kubectl scale deployment console-gateway-service --replicas=0 -n $NAMESPACE
kubectl scale deployment console-control-panel --replicas=0 -n $NAMESPACE
kubectl scale deployment console-sso-service --replicas=0 -n $NAMESPACE
kubectl scale statefulset console-postgres --replicas=0 -n $NAMESPACE
kubectl scale deployment viewer-aimanager --replicas=0 -n $NAMESPACE
kubectl scale deployment viewer-api --replicas=0 -n $NAMESPACE
kubectl scale deployment viewer-etl --replicas=0 -n $NAMESPACE
kubectl scale deployment viewer-server --replicas=0 -n $NAMESPACE
kubectl scale statefulset viewer-neo4j-core --replicas=0 -n $NAMESPACE
kubectl scale deployment extendproxy --replicas=0 -n $NAMESPACE
kubectl scale deployment mcp-server --replicas=0 -n $NAMESPACE