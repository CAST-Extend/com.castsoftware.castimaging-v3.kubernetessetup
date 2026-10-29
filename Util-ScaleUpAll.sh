#!/bin/bash

NAMESPACE=${1:-castimaging-v3}

echo "Scaling up..."

kubectl scale statefulset console-postgres --replicas=1 -n $NAMESPACE
sleep 20
kubectl scale deployment console-sso-service --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment console-control-panel --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment console-gateway-service --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment console-authentication-service --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment console-service --replicas=1 -n $NAMESPACE
sleep 10
# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
# and its autoscaler (stopped by Util-ScaleDownAll) must be restarted
AN_STS="statefulsets.apps"
if kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n $NAMESPACE >/dev/null 2>&1; then
    AN_STS="statefulsets.apps.kruise.io"
fi
kubectl scale $AN_STS console-analysis-node-core --replicas=1 -n $NAMESPACE
if kubectl get deployment console-analysis-node-autoscaler -n $NAMESPACE >/dev/null 2>&1; then
    kubectl scale deployment console-analysis-node-autoscaler --replicas=1 -n $NAMESPACE
fi
sleep 1
kubectl scale deployment console-dashboards --replicas=1 -n $NAMESPACE

kubectl scale statefulset viewer-neo4j-core --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment viewer-server --replicas=1 -n $NAMESPACE
sleep 1
kubectl scale deployment viewer-etl --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment viewer-aimanager --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment viewer-api --replicas=1 -n $NAMESPACE
sleep 10
kubectl scale deployment extendproxy --replicas=1 -n $NAMESPACE
kubectl scale deployment mcp-server  --replicas=1 -n $NAMESPACE