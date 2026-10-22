#!/bin/bash
# =========================================================================
# Imaging Kubernetes Restore Script
# =========================================================================
# This script restores an Imaging instance from backup files
# Ensure kubectl is installed and configured before running this script
# A freshly installed, empty Imaging instance must be running at target
# =========================================================================
# Configuration
if [ $# -lt 2 ]; then
    echo "Usage: $0 <namespace> <backup_dir>"
    exit 1
fi
NAMESPACE="$1"
BACKUP_DIR="$2"
USE_OC=false
CLUSTER_CMD="kubectl"
# kubectl 1.30+ streams exec over WebSockets, which breaks large file transfers; force SPDY
export KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false
OPENSHIFT_CHECK="n"
BACKUP_CASTDIR="false"

# Upload a file to a pod, checking the uploaded size and retrying on mismatch
# (a single large kubectl exec stream can be cut short without kubectl reporting an error)
upload_file() {
    local local_file="$1" pod="$2" remote="$3"
    local size got attempt
    size=$(wc -c < "$local_file")
    for attempt in 1 2 3; do
        $CLUSTER_CMD exec -i $pod -n $NAMESPACE -- sh -c "cat > '$remote'" < "$local_file"
        got=$($CLUSTER_CMD exec $pod -n $NAMESPACE -- stat -c %s "$remote" 2>/dev/null)
        [ "$got" = "$size" ] && return 0
        echo "  upload incomplete (${got:-0} of $size bytes), retrying..."
    done
    echo "ERROR: upload of $local_file to $pod still incomplete after $attempt attempts"
    return 1
}

echo "========================================================================="
echo "Imaging Kubernetes Restore Procedure"
echo "========================================================================="
echo "Namespace: $NAMESPACE"
echo "Backup Directory: $BACKUP_DIR"
echo "========================================================================="
echo ""
echo "CRITICAL WARNINGS:"
echo "  - A freshly installed, empty Imaging instance must be running"
echo "  - The namespace must match the original backup source"
echo "  - All data in the target instance will be replaced"
echo ""
read -p "Type YES to continue with restore: " CONTINUE
if [[ "$CONTINUE" != "YES" ]]; then
    echo "Restore cancelled."
    exit 0
fi
echo ""
# Check if running on OpenShift
if [[ "$OPENSHIFT_CHECK" == "y" || "$OPENSHIFT_CHECK" == "Y" ]]; then
    USE_OC=true
    CLUSTER_CMD="oc"
    echo "Using OpenShift commands (oc)"
    PG_DATA_PATH="/var/lib/pgsql/data"
else
    echo "Using standard Kubernetes commands (kubectl)"
    PG_DATA_PATH="/var/lib/postgresql/data"
fi
echo ""

echo "========================================================================="
echo "Step 1: Restoring Analysis Node files..."
echo "========================================================================="
# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet
AN_STS="statefulsets.apps"
if $CLUSTER_CMD get statefulsets.apps.kruise.io console-analysis-node-core -n $NAMESPACE >/dev/null 2>&1; then
    AN_STS="statefulsets.apps.kruise.io"
fi
# The analysis node may have been left at 0 replicas (e.g. by an earlier interrupted restore)
AN_REPLICAS=$($CLUSTER_CMD get $AN_STS console-analysis-node-core -n $NAMESPACE -o jsonpath='{.spec.replicas}')
if [ "$AN_REPLICAS" = "0" ]; then
    echo "Analysis node is scaled to 0, scaling it to 1..."
    $CLUSTER_CMD scale $AN_STS console-analysis-node-core --replicas=1 -n $NAMESPACE
    if ! $CLUSTER_CMD wait $AN_STS/console-analysis-node-core --for=jsonpath='{.status.readyReplicas}'=1 --timeout=600s -n $NAMESPACE; then
        echo "ERROR: Analysis node did not become ready"
        exit 1
    fi
fi

echo "Discovering console-analysis-node-core pods..."
POD_COUNT=0
SHARED_DONE=false
# Get list of pods matching the pattern
PODS=$($CLUSTER_CMD get pods -n $NAMESPACE -o name | grep "^pod/console-analysis-node-core-")
# Count the pods
for pod in $PODS; do
    ((POD_COUNT++))
done
if [ $POD_COUNT -eq 0 ]; then
    echo "ERROR: No console-analysis-node-core pods found"
    exit 1
fi
echo "Found $POD_COUNT console-analysis-node-core pod(s)"
echo ""
# Loop through each pod
for POD_FULL in $PODS; do
    # Extract pod name from "pod/console-analysis-node-core-X"
    POD_NAME=${POD_FULL#pod/}
    
    echo "============================================"
    echo "Processing pod: $POD_NAME"
    echo "============================================"
    
    # The shared directory is one volume mounted by every analysis node: restore it through the first pod
    # (not necessarily -0: with AnalysisNodeAutoscaling any ordinal can be the one running)
    if [ "$SHARED_DONE" == "false" ]; then
        SHARED_DONE=true
        echo "Checking if shared-dir.tar.gz exists..."
        if [ -f "$BACKUP_DIR/shared-dir.tar.gz" ]; then
            echo "Uploading shared-dir.tar.gz to $POD_NAME..."
            upload_file "$BACKUP_DIR/shared-dir.tar.gz" $POD_NAME /opt/cast/shared/shared-dir.tar.gz
            if [ $? -ne 0 ]; then
                echo "ERROR: Failed to upload shared-dir.tar.gz to $POD_NAME"
                exit 1
            fi
            
            echo "Extracting shared-dir.tar.gz on $POD_NAME..."
            $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -xzpf /opt/cast/shared/shared-dir.tar.gz --strip-components=3 --ignore-failed-read -C /opt/cast/shared/"
            if [ $? -ne 0 ]; then
                echo "WARNING: issue encountered while extracting shared-dir.tar.gz on $POD_NAME"
            fi
            
            echo "Cleaning up shared-dir archive from $POD_NAME..."
            $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm /opt/cast/shared/shared-dir.tar.gz"
            echo ""
        else
            echo "WARNING: shared-dir.tar.gz not found in backup directory"
            echo ""
        fi
    fi
    
    # Restore CAST directory for all pods using pod-specific backup (optional)
    if [[ "${BACKUP_CASTDIR,,}" == "true" ]]; then
        CAST_BACKUP="$BACKUP_DIR/$POD_NAME-cast-dir.tar.gz"
        echo "Checking if $POD_NAME-cast-dir.tar.gz exists..."
        if [ -f "$CAST_BACKUP" ]; then
            echo "Uploading $POD_NAME-cast-dir.tar.gz to $POD_NAME..."
            upload_file "$CAST_BACKUP" $POD_NAME /usr/share/CAST/cast-dir.tar.gz
            if [ $? -ne 0 ]; then
                echo "ERROR: Failed to upload cast-dir.tar.gz to $POD_NAME"
                exit 1
            fi

            echo "Extracting cast-dir.tar.gz on $POD_NAME..."
            $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -xzpf /usr/share/CAST/cast-dir.tar.gz --strip-components=3 --ignore-failed-read -C /usr/share/CAST/"
            if [ $? -ne 0 ]; then
                echo "WARNING: issue encountered while extracting cast-dir.tar.gz on $POD_NAME"
            fi

            echo "Cleaning up cast-dir archive from $POD_NAME..."
            $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm /usr/share/CAST/cast-dir.tar.gz"

            echo "Restore for $POD_NAME completed successfully."
            echo ""
        else
            echo "ERROR: Backup file $POD_NAME-cast-dir.tar.gz not found"
            exit 1
        fi
    else
        echo "Skipping CAST directory restore for $POD_NAME (BACKUP_CASTDIR is not set to true)"
        echo ""
    fi
done
echo "All Analysis Node files restored successfully."
echo ""
echo "========================================================================="
echo "Step 2: Restoring CSS Postgres instance..."
echo "========================================================================="
echo "Stopping all services except postgres and neo4j..."
# With AnalysisNodeAutoscaling enabled the analysis node is an OpenKruise StatefulSet,
# and its autoscaler must be stopped first or it scales the analysis node back up
if $CLUSTER_CMD get deployment console-analysis-node-autoscaler -n $NAMESPACE >/dev/null 2>&1; then
    $CLUSTER_CMD scale deployment console-analysis-node-autoscaler --replicas=0 -n $NAMESPACE
fi
$CLUSTER_CMD scale deployment  console-dashboards             --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale $AN_STS console-analysis-node-core --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  console-service                --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  console-authentication-service --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  console-gateway-service        --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  console-control-panel          --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  console-sso-service            --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  viewer-aimanager               --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  viewer-api                     --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  viewer-etl                     --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  viewer-server                  --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  extendproxy                    --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale deployment  mcp-server                     --replicas=0 -n $NAMESPACE
echo "Waiting for services to scale down..."
sleep 10
echo ""
echo "Finding postgres pod name..."
POSTGRES_POD=$($CLUSTER_CMD get pods -n $NAMESPACE | grep console-postgres | awk '{print $1}')
if [ -n "$POSTGRES_POD" ]; then
    echo "Found postgres pod: $POSTGRES_POD"
    echo ""
    echo "Uploading all_databases.backup to postgres pod..."
    upload_file "$BACKUP_DIR/all_databases.backup" $POSTGRES_POD $PG_DATA_PATH/all_databases.backup
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to upload all_databases.backup"
        exit 1
    fi
    echo "Dropping existing databases in postgres..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "psql -U postgres -c 'drop schema control_panel cascade;'"
    echo "Restoring postgres databases from backup..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "psql -U postgres -f $PG_DATA_PATH/all_databases.backup > $PG_DATA_PATH/postgres_restore.log 2>&1"
    if [ $? -ne 0 ]; then
        echo "echo ERROR: Postgres restore encountered issues. Check log file."
        exit 1
    fi
    echo ""
    echo "Running ANALYZE commands..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "psql -U operator -p 5432 -c 'ANALYZE;' -d keycloak"
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "psql -U operator -p 5432 -c 'ANALYZE;' -d postgres"
    echo "Downloading postgres restore log..."
    $CLUSTER_CMD cp $NAMESPACE/$POSTGRES_POD:$PG_DATA_PATH/postgres_restore.log "$BACKUP_DIR/postgres_restore.log" || echo "WARNING: Failed to download postgres_restore.log, continuing..."
    echo "Cleaning up backup files from postgres pod..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "rm -f $PG_DATA_PATH/all_databases.backup $PG_DATA_PATH/postgres_restore.log"
    echo "Postgres restore done."
else
    echo "WARNING: Could not find postgres pod, skipping postgres restore"
fi
echo "========================================================================="
echo "Step 3: Restoring Neo4j databases..."
echo "========================================================================="
echo "Creating/cleaning backup directory..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"
upload_file "$BACKUP_DIR/backup/neo4j.tar" viewer-neo4j-core-0 /var/lib/neo4j/config/neo4j5_data/neo4j.tar
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to upload Neo4j backup files"
    exit 1
fi
echo "Expanding Neo4j backup files..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "tar -xf /var/lib/neo4j/config/neo4j5_data/neo4j.tar --strip-components=5 -C /var/lib/neo4j/config/neo4j5_data/"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to expand Neo4j backup files"
    exit 1
fi
echo "Discovering databases in backup..."
# One <db>-YYYY-MM-DDTHH-MM-SS.backup file per database; system is not restored
DB_LIST=$($CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cd /var/lib/neo4j/config/neo4j5_data/backup && ls -1 *.backup | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}\.backup\$//' | sort -u | grep -vx system")
if [ -z "$DB_LIST" ]; then
    echo "ERROR: No Neo4j database backups found in neo4j.tar"
    exit 1
fi
echo "Databases to restore:" $DB_LIST
echo "Creating temporary cypher scripts..."
{
    for DB in $DB_LIST; do echo "drop database \`$DB\` if exists;"; done
    for DB in $DB_LIST; do echo "create database \`$DB\`;"; done
    for DB in $DB_LIST; do echo "stop database \`$DB\`;"; done
} > "$BACKUP_DIR/backup/neo4j_drop_create.cypher"
{
    for DB in $DB_LIST; do echo "start database \`$DB\`;"; done
    echo "show databases;"
} > "$BACKUP_DIR/backup/neo4j_start.cypher"
echo "Uploading cypher scripts..."
$CLUSTER_CMD cp -n $NAMESPACE "$BACKUP_DIR/backup/neo4j_drop_create.cypher"	viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup/neo4j_drop_create.cypher
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to upload neo4j_drop_create.cypher"
    exit 1
fi
$CLUSTER_CMD cp -n $NAMESPACE "$BACKUP_DIR/backup/neo4j_start.cypher"	viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup/neo4j_start.cypher
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to upload neo4j_start.cypher"
    exit 1
fi
echo "Dropping and recreating Neo4j databases..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_drop_create.cypher"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to execute neo4j_drop_create.cypher"
    exit 1
fi
rm "$BACKUP_DIR/backup/neo4j_drop_create.cypher"
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -f /var/lib/neo4j/logs/neo4j_restore.log"
for DB in $DB_LIST; do
    echo "Restoring $DB database..."
    $CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=$DB $DB >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
    if [ $? -ne 0 ]; then
        $CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log" || echo "WARNING: Failed to download neo4j_restore.log"
        echo "ERROR: $DB database restore encountered issues. Check neo4j_restore.log file."
        exit 1
    fi
done
echo "Starting databases..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_start.cypher"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to execute neo4j_start.cypher"
    exit 1
fi
rm "$BACKUP_DIR/backup/neo4j_start.cypher"
echo "Executing permission scripts..."
for DB in $DB_LIST; do
    $CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"$DB\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/$DB/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
done
echo "Downloading Neo4j restore log..."
$CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log" || echo "WARNING: Failed to download neo4j_restore.log, continuing..."
echo "Cleaning up archive files..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -f /var/lib/neo4j/config/neo4j5_data/neo4j.tar"
echo "Cleaning up Neo4j restore log from pod..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -f /var/lib/neo4j/logs/neo4j_restore.log"
echo "Restarting Neo4j pod..."
$CLUSTER_CMD scale statefulset viewer-neo4j-core --replicas=0 -n $NAMESPACE
echo "Waiting for Neo4j to stop..."
while true; do
    if $CLUSTER_CMD get statefulset viewer-neo4j-core -n $NAMESPACE | grep -q "0/0"; then
        break
    fi
    sleep 5
done
echo "Neo4j has been stopped successfully."
echo ""
echo "========================================================================="
echo "Final Step: Starting all Imaging services..."
echo "========================================================================="
echo ""
echo "IMPORTANT: You must now start all Imaging services by either:"
echo "  1. Running Util-ScaleUpAll.sh script from the Imaging helm chart folder"
echo "  2. Running: helm upgrade $NAMESPACE --namespace $NAMESPACE ."
echo "========================================================================="
echo "RESTORE COMPLETED"
echo "========================================================================="
echo ""
echo "Log files have been saved to: $BACKUP_DIR"
echo "  - postgres_restore.log (Postgres restore log)"
echo "  - neo4j_restore.log (Neo4j restore and permissions log)"
echo ""
echo "Please review these log files for any errors or warnings."
echo ""
echo "Next steps:"
echo "  1. Start all remaining services using helm upgrade or Util-ScaleUpAll script"
echo "  2. Verify the Imaging instance is functioning correctly"
echo "  3. Check the Console for any issues"
echo ""
echo "========================================================================="
read -p "Press Enter to continue..."