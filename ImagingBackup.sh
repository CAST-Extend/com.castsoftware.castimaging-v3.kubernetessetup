#!/bin/bash
# =========================================================================
# Imaging Kubernetes Backup Script
# =========================================================================
# This script performs a full backup of an Imaging instance on K8s
# Ensure kubectl/oc is installed and configured before running this script
# =========================================================================

# Configuration
if [ $# -lt 2 ]; then
    echo "Usage: $0 <namespace> <backup_dir>"
    exit 1
fi
NAMESPACE="$1"
BACKUP_DIR="$2"
CLUSTER_CMD="kubectl"
# kubectl 1.30+ streams exec over WebSockets, which breaks large file transfers; force SPDY
export KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false
OPENSHIFT_CHECK="n"
BACKUP_CASTDIR="false"
# Large files are downloaded in chunks of this size, each one size-checked and retried
CHUNK_MB=256
CHUNK_BYTES=$((CHUNK_MB * 1048576))

# Download a file from a pod in CHUNK_MB chunks, checking each chunk's size and retrying it on mismatch
# (a single large kubectl exec stream can be cut short without kubectl reporting an error)
download_file() {
    local pod="$1" remote="$2" local_file="$3"
    local size chunks i expected got attempt
    size=$($CLUSTER_CMD exec $pod -n $NAMESPACE -- stat -c %s "$remote" 2>/dev/null)
    if [ -z "$size" ]; then
        echo "ERROR: Cannot read size of $remote in $pod"
        return 1
    fi
    chunks=$(( (size + CHUNK_BYTES - 1) / CHUNK_BYTES ))
    echo "  $size bytes in $chunks chunk(s)"
    : > "$local_file"
    for ((i = 0; i < chunks; i++)); do
        if [ $i -lt $((chunks - 1)) ]; then expected=$CHUNK_BYTES; else expected=$((size - i * CHUNK_BYTES)); fi
        for attempt in 1 2 3 4 5; do
            echo "  chunk $((i + 1))/$chunks..."
            # The trailing sleep keeps the stream open so data still in flight is not dropped when dd exits
            $CLUSTER_CMD exec $pod -n $NAMESPACE -- sh -c "dd if='$remote' bs=1M skip=$((i * CHUNK_MB)) count=$CHUNK_MB 2>/dev/null; sleep 5" > "$local_file.part"
            got=$(wc -c < "$local_file.part")
            [ "$got" -eq "$expected" ] && break
            echo "  chunk $((i + 1))/$chunks incomplete ($got of $expected bytes), retrying..."
        done
        if [ "$got" -ne "$expected" ]; then
            echo "ERROR: chunk $((i + 1))/$chunks of $remote still incomplete after $attempt attempts"
            rm -f "$local_file.part"
            return 1
        fi
        cat "$local_file.part" >> "$local_file"
    done
    rm -f "$local_file.part"
    got=$(wc -c < "$local_file")
    if [ "$got" -ne "$size" ]; then
        echo "ERROR: $local_file is $got bytes, expected $size"
        return 1
    fi
}

echo "========================================================================="
echo "Imaging Kubernetes Backup Procedure"
echo "========================================================================="
echo "Namespace: $NAMESPACE"
echo "Backup Directory: $BACKUP_DIR"
echo "========================================================================="
echo ""

if [[ "${OPENSHIFT_CHECK,,}" == "y" ]]; then
    CLUSTER_CMD="oc"
    echo "Using OpenShift oc commands"
    PG_DATA_PATH="/var/lib/pgsql/data"
else
    echo "Using standard Kubernetes kubectl commands"
    PG_DATA_PATH="/var/lib/postgresql/data"
fi
echo ""

echo "IMPORTANT: Ensure the Imaging instance is quiet (no activity in Console)"
echo "Press Ctrl+C to cancel, or press Enter to continue..."
read

# Create backup directory
echo "Creating backup directory..."
if ! mkdir -p "$BACKUP_DIR"; then
    echo "ERROR: Failed to create backup directory"
    exit 1
fi
echo "Backup directory created: $BACKUP_DIR"
echo ""


echo "========================================================================="
echo "Step 1: Backing up Analysis Node files..."
echo "========================================================================="

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
    
    # The shared directory is one volume mounted by every analysis node: back it up from the first pod
    # (not necessarily -0: with AnalysisNodeAutoscaling any ordinal can be the one running)
    if [ "$SHARED_DONE" == "false" ]; then
        SHARED_DONE=true
        echo "Connecting to $POD_NAME and creating shared directory backup..."
        $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -czpf /opt/cast/shared/shared-dir.tar.gz --exclude='/opt/cast/shared/shared-dir.tar.gz' --exclude='/opt/cast/shared/lost+found' /opt/cast/shared/*"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to create archive file"
            exit 1
        fi
        
        echo "Downloading shared-dir.tar.gz from $POD_NAME..."
        download_file $POD_NAME /opt/cast/shared/shared-dir.tar.gz "$BACKUP_DIR/shared-dir.tar.gz"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download shared-dir.tar.gz from $POD_NAME"
            exit 1
        fi
        
        echo "Cleaning up shared-dir backup file from $POD_NAME..."
        $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm -f /opt/cast/shared/shared-dir.tar.gz"
        echo ""
    fi
    
    # Backup CAST directory for all pods (optional)
    if [[ "${BACKUP_CASTDIR,,}" == "true" ]]; then
        echo "Connecting to $POD_NAME and creating CAST directory backup..."
        $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -czpf /usr/share/CAST/cast-dir.tar.gz --exclude='/usr/share/CAST/cast-dir.tar.gz' --exclude='/usr/share/CAST/lost+found' /usr/share/CAST/*"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to create archive file"
            exit 1
        fi

        echo "Downloading cast-dir.tar.gz from $POD_NAME..."
        download_file $POD_NAME /usr/share/CAST/cast-dir.tar.gz "$BACKUP_DIR/$POD_NAME-cast-dir.tar.gz"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download cast-dir.tar.gz from $POD_NAME"
            exit 1
        fi

        echo "Cleaning up cast-dir backup file from $POD_NAME..."
        $CLUSTER_CMD exec $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm -f /usr/share/CAST/cast-dir.tar.gz"
    else
        echo "Skipping CAST directory backup for $POD_NAME (BACKUP_CASTDIR is not set to true)"
    fi

    echo "Backup for $POD_NAME completed successfully."
    echo ""
done

echo "All Analysis Node backups completed successfully."
echo ""


echo "========================================================================="
echo "Step 2: Backing up CSS Postgres instance..."
echo "========================================================================="

echo "Finding postgres pod name..."
POSTGRES_POD=$($CLUSTER_CMD get pods -n $NAMESPACE | grep console-postgres | awk '{print $1}' | head -n 1)

if [ -n "$POSTGRES_POD" ]; then
    echo "Found postgres pod: $POSTGRES_POD"
    echo ""

    echo "Creating backup directory in postgres pod..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "mkdir -p $PG_DATA_PATH/backup"

    echo "Running pg_dumpall..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "pg_dumpall -v -U operator -p 5432 -f $PG_DATA_PATH/backup/all_databases.backup > $PG_DATA_PATH/backup/postgres_backup.log 2>&1"
    if [ $? -ne 0 ]; then
        echo "ERROR: pg_dumpall has encountered issues. Check log file."
        exit 1
    fi

    echo "Downloading all_databases.backup..."
    download_file $POSTGRES_POD $PG_DATA_PATH/backup/all_databases.backup "$BACKUP_DIR/all_databases.backup"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download all_databases.backup"
        exit 1
    fi

    echo "Downloading postgres backup log..."
    $CLUSTER_CMD cp $NAMESPACE/$POSTGRES_POD:$PG_DATA_PATH/backup/postgres_backup.log "$BACKUP_DIR/postgres_backup.log" || echo "WARNING: Failed to download postgres_backup.log, continuing..."

    echo "Cleaning up backup files from postgres pod..."
    $CLUSTER_CMD exec $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "rm -rf $PG_DATA_PATH/backup"

    echo "Postgres backup completed successfully."
    echo ""
else
    echo "WARNING: Could not find postgres pod, skipping postgres backup"
fi

echo "========================================================================="
echo "Step 3: Backing up Neo4j databases..."
echo "========================================================================="

echo "Connecting to viewer-neo4j-core-0..."
echo "Creating/cleaning backup directory..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"

echo "Running neo4j-admin database backup..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database backup --verbose --compress=true --include-metadata=all --pagecache=4G --to-path /var/lib/neo4j/config/neo4j5_data/backup --from=localhost:6362 '*' > /var/lib/neo4j/logs/backup_ImagingDatabases.log 2>&1"
if [ $? -ne 0 ]; then
    $CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/backup_ImagingDatabases.log "$BACKUP_DIR/backup_ImagingDatabases.log" || echo "WARNING: Failed to download backup_ImagingDatabases.log"
    echo "ERROR: Neo4j backup has encountered issues. Check log file."
    exit 1
fi

echo "Inspecting backup files..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database backup --inspect-path=/var/lib/neo4j/config/neo4j5_data/backup"

echo "Downloading backup log..."
$CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/backup_ImagingDatabases.log "$BACKUP_DIR/backup_ImagingDatabases.log" || echo "WARNING: Failed to download backup_ImagingDatabases.log, continuing..."

echo "Downloading Neo4j backup files..."
mkdir -p "$BACKUP_DIR/backup"
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "tar cf /var/lib/neo4j/config/neo4j5_data/neo4j.tar /var/lib/neo4j/config/neo4j5_data/backup"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create Neo4j backup archive"
    exit 1
fi
download_file viewer-neo4j-core-0 /var/lib/neo4j/config/neo4j5_data/neo4j.tar "$BACKUP_DIR/backup/neo4j.tar"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download Neo4j backup files"
    exit 1
fi

echo "Cleaning up backup files from neo4j pod..."
$CLUSTER_CMD exec viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/* /var/lib/neo4j/config/neo4j5_data/neo4j.tar"

echo "Neo4j backup completed successfully."
echo ""

echo "========================================================================="
echo "BACKUP COMPLETED SUCCESSFULLY"
echo "========================================================================="
echo ""
echo "All backup files have been saved to: $BACKUP_DIR"
echo ""
echo "Backup contents:"
echo "  - shared-dir.tar.gz (Analysis Node shared files)"
echo "  - xxx-cast-dir.tar.gz (Analysis Node CAST files, if BACKUP_CASTDIR=true)"
echo "  - all_databases.backup (Postgres databases)"
echo "  - postgres_backup.log (Postgres backup log)"
echo "  - backup/ (Neo4j database backups)"
echo "  - backup_ImagingDatabases.log (Neo4j backup log)"
echo ""
echo "Please review the postgres_backup.log and backup_ImagingDatabases.log files for any errors."
echo ""
echo "========================================================================="

echo "Press Enter to exit..."
read