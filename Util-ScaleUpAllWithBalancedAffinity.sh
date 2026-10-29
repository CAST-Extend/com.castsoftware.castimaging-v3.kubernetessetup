#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=castimaging-v3
NUMBER_OF_ANALYSIS_NODES=1
TIMEOUT=900s

scale() {
    # $1 = kind  $2 = name  $3 = replicas
    echo "Scaling $1/$2 to $3 replica(s)..."
    if ! kubectl scale "$1" "$2" --replicas="$3" -n "$NAMESPACE"; then
        echo "ERROR: failed to scale $1/$2"
        exit 1
    fi
}

wait_ready() {
    # $1 = kind  $2 = name
    echo "Waiting for $1/$2 to roll out..."
    if ! kubectl rollout status "$1/$2" --timeout="$TIMEOUT" -n "$NAMESPACE"; then
        echo "ERROR: $1/$2 did not become ready within $TIMEOUT"
        exit 1
    fi
    echo "$1/$2 is ready."
    echo
}

wait_replicas() {
    # $1 = kind  $2 = name  $3 = replicas  (for kinds rollout status does not support)
    echo "Waiting for $1/$2 to have $3 ready replica(s)..."
    if ! kubectl wait "$1/$2" --for=jsonpath='{.status.readyReplicas}'="$3" --timeout="$TIMEOUT" -n "$NAMESPACE"; then
        echo "ERROR: $1/$2 did not become ready within $TIMEOUT"
        exit 1
    fi
    echo "$1/$2 is ready."
    echo
}

echo "Scaling up namespace $NAMESPACE..."
echo

# ----- Analysis nodes (scale now, wait later so other things start in parallel) -----

# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
# and its autoscaler (stopped by Util-ScaleDownAll) must be restarted
AN_STS="statefulset"
if kubectl get statefulsets.apps.kruise.io console-analysis-node-core -n "$NAMESPACE" >/dev/null 2>&1; then
    AN_STS="statefulsets.apps.kruise.io"
fi

scale "$AN_STS" console-analysis-node-core "$NUMBER_OF_ANALYSIS_NODES"
if kubectl get deployment console-analysis-node-autoscaler -n "$NAMESPACE" >/dev/null 2>&1; then
    scale deployment console-analysis-node-autoscaler 1
fi

# ----- Core data stores -----

scale statefulset console-postgres 1
wait_ready statefulset console-postgres

scale statefulset viewer-neo4j-core 1
wait_ready statefulset viewer-neo4j-core

# ----- Console services -----

scale deployment console-sso-service 1
wait_ready deployment console-sso-service

scale deployment console-control-panel 1
scale deployment console-gateway-service 1
scale deployment console-authentication-service 1
scale deployment console-service 1
scale deployment console-dashboards 1
scale deployment extendproxy 1

# ----- Now block until the analysis nodes are actually Ready -----

if [ "$AN_STS" = "statefulset" ]; then
    wait_ready statefulset console-analysis-node-core
else
    wait_replicas "$AN_STS" console-analysis-node-core "$NUMBER_OF_ANALYSIS_NODES"
fi

# ----- Viewer services -----

scale deployment viewer-server 1
scale deployment viewer-etl 1
scale deployment viewer-aimanager 1
scale deployment viewer-api 1
scale deployment mcp-server 1

echo
echo "Scale-up complete."
exit 0