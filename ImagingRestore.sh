#!/bin/bash
# =========================================================================
# Imaging Kubernetes Restore Script
# =========================================================================
# This script restores an Imaging instance from backup files
# Ensure kubectl is installed and configured before running this script
# A freshly installed, empty Imaging instance must be running at target
# =========================================================================
# Configuration
NAMESPACE="castimaging-v3"
BACKUP_DIR="./mybackupfolder"
USE_OC=false
CLUSTER_CMD="kubectl"
OPENSHIFT_CHECK="n"

echo "========================================================================="
echo "Imaging Kubernetes Restore Procedure - SINGLE TENANT"
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
echo "Discovering console-analysis-node-core pods..."
POD_COUNT=0
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
    
    # Only restore shared directory for console-analysis-node-core-0
    if [ "$POD_NAME" == "console-analysis-node-core-0" ]; then
        echo "Checking if shared-dir.tar.gz exists..."
        if [ -f "$BACKUP_DIR/shared-dir.tar.gz" ]; then
            echo "Uploading shared-dir.tar.gz to $POD_NAME..."
            cat "$BACKUP_DIR/shared-dir.tar.gz" | $CLUSTER_CMD exec -n $NAMESPACE $POD_NAME -i -- sh -c "cat > /opt/cast/shared/shared-dir.tar.gz"
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
    
    # Restore CAST directory for all pods using pod-specific backup
    CAST_BACKUP="$BACKUP_DIR/$POD_NAME-cast-dir.tar.gz"
    echo "Checking if $POD_NAME-cast-dir.tar.gz exists..."
    if [ -f "$CAST_BACKUP" ]; then
        echo "Uploading $POD_NAME-cast-dir.tar.gz to $POD_NAME..."
        cat "$CAST_BACKUP" | $CLUSTER_CMD exec -n $NAMESPACE $POD_NAME -i -- sh -c "cat > /usr/share/CAST/cast-dir.tar.gz"
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
done
echo "All Analysis Node files restored successfully."
echo ""
echo "========================================================================="
echo "Step 2: Restoring CSS Postgres instance..."
echo "========================================================================="
echo "Stopping all services except postgres and neo4j..."
$CLUSTER_CMD scale deployment  console-dashboards             --replicas=0 -n $NAMESPACE
$CLUSTER_CMD scale statefulset console-analysis-node-core     --replicas=0 -n $NAMESPACE
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
    cat "$BACKUP_DIR/all_databases.backup" | $CLUSTER_CMD exec -n $NAMESPACE $POSTGRES_POD -i -- sh -c "cat > $PG_DATA_PATH/all_databases.backup"
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
    $CLUSTER_CMD cp $NAMESPACE/$POSTGRES_POD:$PG_DATA_PATH/postgres_restore.log "$BACKUP_DIR/postgres_restore.log"
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
echo "Creating temporary cypher scripts..."
cat > "$BACKUP_DIR/backup/neo4j_drop_create.cypher" <<'EOF'
drop database neo4j if exists;
drop database imaging if exists;
drop database packagereference if exists;
create database neo4j;
create database imaging;
create database packagereference;
stop database neo4j;
stop database imaging;
stop database packagereference;
EOF
echo "Starting restored databases..."
cat > "$BACKUP_DIR/backup/neo4j_start.cypher" <<'EOF'
start database neo4j;
start database imaging;
start database packagereference;
show databases;
EOF
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
$CLUSTER_CMD exec -n $NAMESPACE viewer-neo4j-core-0 -i -- sh -c "cat > /var/lib/neo4j/config/neo4j5_data/neo4j.tar" < "$BACKUP_DIR/backup/neo4j.tar"
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
echo "Dropping and recreating Neo4j databases..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_drop_create.cypher"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to execute neo4j_drop_create.cypher"
    exit 1
fi
rm "$BACKUP_DIR/backup/neo4j_drop_create.cypher"
echo "Restoring neo4j database..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=neo4j neo4j > /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if [ $? -ne 0 ]; then
    $CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log"
    echo "ERROR: neo4j database restore encountered issues. Check neo4j_restore.log file."
    exit 1
fi
echo "Restoring imaging database..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=imaging imaging >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if [ $? -ne 0 ]; then
    $CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log"
    echo "ERROR: imaging database restore encountered issues. Check neo4j_restore.log file."
    exit 1
fi
echo "Restoring packagereference database..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=packagereference packagereference >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if [ $? -ne 0 ]; then
    $CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log"
    echo "ERROR: packagereference database restore encountered issues. Check neo4j_restore.log file."
    exit 1
fi
echo "Starting databases..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_start.cypher"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to execute neo4j_start.cypher"
    exit 1
fi
rm "$BACKUP_DIR/backup/neo4j_start.cypher"
echo "Executing permission scripts..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"neo4j\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/neo4j/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"imaging\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/imaging/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"packagereference\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/packagereference/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
echo "Downloading Neo4j restore log..."
$CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "$BACKUP_DIR/neo4j_restore.log"
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