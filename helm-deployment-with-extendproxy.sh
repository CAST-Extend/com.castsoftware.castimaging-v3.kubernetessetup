#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="castimaging-v3"

# Update the path to your custom values file
# Among the provided values: enable Extend Proxy and set its exthostname
CUSTOM_VALUES="./values-custom.yaml"

EXTENDPROXY_LOGS=$(mktemp /tmp/extendproxy_logs.XXXXXX.txt)

cleanup() { rm -f "$EXTENDPROXY_LOGS"; }
trap cleanup EXIT

echo "----------------------------------------------"
echo "Installing helm chart..."
echo "----------------------------------------------"
helm install "$NAMESPACE" --create-namespace --namespace "$NAMESPACE" -f "$CUSTOM_VALUES" .
kubectl rollout status deployment/console-service --timeout=900s -n "$NAMESPACE"

echo "Retrieving logs from pod extendproxy-0..."
if ! kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace "$NAMESPACE" > "$EXTENDPROXY_LOGS"; then
    echo "ERROR: Failed to retrieve logs from pod extendproxy-0."
    exit 1
fi

echo "----------------------------------------------"
echo "Extracting Apikey for Extend Proxy..."
echo "----------------------------------------------"
APIKEY=$(grep "Apikey for Extend Proxy:" "$EXTENDPROXY_LOGS" | awk '{print $5}')

if [[ -z "$APIKEY" ]]; then
    echo "No extendproxy/Apikey found."
    exit 1
fi

echo "Found extendproxy Apikey: $APIKEY"

echo "----------------------------------------------"
echo "Running helm upgrade with extracted Apikey..."
echo "----------------------------------------------"
if ! helm upgrade "$NAMESPACE" --namespace "$NAMESPACE" -f "$CUSTOM_VALUES" --set "ExtendApiKey=$APIKEY" .; then
    echo "ERROR: helm upgrade failed."
    exit 1
fi

kubectl scale deployment  console-service             --replicas=0 -n "$NAMESPACE"
kubectl scale deployment  console-control-panel       --replicas=0 -n "$NAMESPACE"
kubectl scale statefulset console-analysis-node-core  --replicas=0 -n "$NAMESPACE"

kubectl rollout status deployment/console-service              --timeout=120s -n "$NAMESPACE"
kubectl rollout status deployment/console-control-panel        --timeout=120s -n "$NAMESPACE"
kubectl rollout status statefulset/console-analysis-node-core  --timeout=120s -n "$NAMESPACE"

if ! helm upgrade "$NAMESPACE" --namespace "$NAMESPACE" -f "$CUSTOM_VALUES" --set "ExtendApiKey=$APIKEY" .; then
    echo "ERROR: helm upgrade failed."
    exit 1
fi

echo ""
kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace "$NAMESPACE" | grep "Extend Proxy Admin Center"
echo "----------------------------------------------"
echo "You can add this ExtendApiKey to the values-custom.yaml file for future use:"
echo "ExtendApiKey: $APIKEY"
echo "----------------------------------------------"