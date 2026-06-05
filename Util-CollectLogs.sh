#!/bin/bash
NAMESPACE="${1:-castimaging-v3}"
DEST="./Logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DEST"

# neo4j
echo "=== Pod: viewer-neo4j-core-0 ==="
kubectl exec viewer-neo4j-core-0 -n $NAMESPACE -- tar cf - /var/lib/neo4j/logs > $DEST/viewer-neo4j-logs.tar

# Analysis nodes
for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^console-analysis-node-core-'); do
  echo "=== Pod: $pod ==="
  kubectl exec $pod -n $NAMESPACE -- tar cf - /usr/share/CAST/CAST/Logs > $DEST/$pod-Logs.tar
done

# Other pods
declare -A LOG_PATHS=(
  [viewer-server]="/opt/imaging/imaging-service/logs"
  [viewer-etl]="/opt/imaging/imaging-etl/logs"
  [console-postgres]="/var/lib/postgresql/data/log"

)
for SVC in "${!LOG_PATHS[@]}"; do
  POD=$(kubectl get pod -n $NAMESPACE -l imaging.service=$SVC -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$POD" ]; then
    echo "No pod found for $SVC, skipping."
    continue
  fi
  echo "=== Copying logs from $POD ($SVC) ==="
  kubectl cp -n $NAMESPACE $POD:${LOG_PATHS[$SVC]} $DEST/$SVC
done

# Retrieving standard output log from all pods
echo "=== Retrieving std-out logs from all pods ==="
for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Pod: $pod ===" >> $DEST/all-pods-stdout.log
  kubectl logs $pod -n $NAMESPACE --all-containers=true --prefix=true --tail=-1 >> $DEST/all-pods-stdout.log
done

echo "All logs collected in $DEST"