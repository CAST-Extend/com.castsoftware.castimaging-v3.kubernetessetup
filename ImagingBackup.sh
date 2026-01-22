#!/bin/bash
# =========================================================================
# Imaging Kubernetes Backup Script
# =========================================================================
# This script performs a full backup of an Imaging instance on K8s
# Ensure kubectl/oc is installed and configured before running this script
# =========================================================================

# Configuration
NAMESPACE="castimaging-v3"
BACKUP_DIR="./imaging_backup_$(date +%Y%m%d_%H%M%S)"
CLUSTER_CMD="kubectl"

echo "========================================================================="
echo "Imaging Kubernetes Backup Procedure"
echo "========================================================================="
echo "Namespace: $NAMESPACE"
echo "Backup Directory: $BACKUP_DIR"
echo "========================================================================="
echo ""

# Ask about OpenShift
read -p "Are you running on OpenShift? (y/n): " OPENSHIFT_CHECK
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
    
    # Only backup shared directory for console-analysis-node-core-0
    if [ "$POD_NAME" == "console-analysis-node-core-0" ]; then
        echo "Connecting to $POD_NAME and creating shared directory backup..."
        $CLUSTER_CMD exec -it $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -czpf /opt/cast/shared/shared-dir.tar.gz --exclude='/opt/cast/shared/shared-dir.tar.gz' --exclude='/opt/cast/shared/lost+found' /opt/cast/shared/*"
        if [ $? -ne 0 ]; then
            echo "WARNING: Some files may have been skipped due to permissions"
        fi
        
        echo "Downloading shared-dir.tar.gz from $POD_NAME..."
        $CLUSTER_CMD cp $NAMESPACE/$POD_NAME:/opt/cast/shared/shared-dir.tar.gz "$BACKUP_DIR/shared-dir.tar.gz"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download shared-dir.tar.gz from $POD_NAME"
            exit 1
        fi
        
        echo "Cleaning up shared-dir backup file from $POD_NAME..."
        $CLUSTER_CMD exec -it $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm -f /opt/cast/shared/shared-dir.tar.gz"
        echo ""
    fi
    
    # Backup CAST directory for all pods
    echo "Connecting to $POD_NAME and creating CAST directory backup..."
    $CLUSTER_CMD exec -it $POD_NAME -n $NAMESPACE -- /bin/bash -c "tar -czpf /usr/share/CAST/cast-dir.tar.gz --exclude='/usr/share/CAST/cast-dir.tar.gz' --exclude='/usr/share/CAST/lost+found' /usr/share/CAST/*"
    if [ $? -ne 0 ]; then
        echo "WARNING: Some files may have been skipped due to permissions"
    fi
    
    echo "Downloading cast-dir.tar.gz from $POD_NAME..."
    $CLUSTER_CMD cp $NAMESPACE/$POD_NAME:/usr/share/CAST/cast-dir.tar.gz "$BACKUP_DIR/$POD_NAME-cast-dir.tar.gz"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download cast-dir.tar.gz from $POD_NAME"
        exit 1
    fi
    
    echo "Cleaning up cast-dir backup file from $POD_NAME..."
    $CLUSTER_CMD exec -it $POD_NAME -n $NAMESPACE -- /bin/bash -c "rm -f /usr/share/CAST/cast-dir.tar.gz"
    
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
    $CLUSTER_CMD exec -it $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "mkdir -p $PG_DATA_PATH/backup"

    echo "Running pg_dumpall..."
    $CLUSTER_CMD exec -it $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "pg_dumpall -U operator -p 5432 -f $PG_DATA_PATH/backup/all_databases.backup > $PG_DATA_PATH/backup/postgres_backup.log 2>&1"
    if [ $? -ne 0 ]; then
        echo "WARNING: pg_dumpall may have encountered issues. Check log file."
    fi

    echo "Downloading all_databases.backup..."
    $CLUSTER_CMD cp $NAMESPACE/$POSTGRES_POD:$PG_DATA_PATH/backup/all_databases.backup "$BACKUP_DIR/all_databases.backup"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download all_databases.backup"
        exit 1
    fi

    echo "Downloading postgres backup log..."
    $CLUSTER_CMD cp $NAMESPACE/$POSTGRES_POD:$PG_DATA_PATH/backup/postgres_backup.log "$BACKUP_DIR/postgres_backup.log"

    echo "Cleaning up backup files from postgres pod..."
    $CLUSTER_CMD exec -it $POSTGRES_POD -n $NAMESPACE -- /bin/bash -c "rm -rf $PG_DATA_PATH/backup"

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
$CLUSTER_CMD exec -it viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -f /var/lib/neo4j/config/neo4j5_data/backup/*"

echo "Running neo4j-admin database backup..."
$CLUSTER_CMD exec -it viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database backup --verbose --compress=true --include-metadata=all --pagecache=4G --to-path /var/lib/neo4j/config/neo4j5_data/backup --from=localhost:6362 '*' > /var/lib/neo4j/logs/backup_ImagingDatabases.log 2>&1"
if [ $? -ne 0 ]; then
    echo "WARNING: Neo4j backup may have encountered issues. Check log file."
fi

echo "Inspecting backup files..."
$CLUSTER_CMD exec -it viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "neo4j-admin database backup --inspect-path=/var/lib/neo4j/config/neo4j5_data/backup"

echo "Downloading backup log..."
$CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/logs/backup_ImagingDatabases.log "$BACKUP_DIR/backup_ImagingDatabases.log"

echo "Downloading Neo4j backup files..."
mkdir -p "$BACKUP_DIR/backup"
$CLUSTER_CMD cp $NAMESPACE/viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup "$BACKUP_DIR/backup"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download Neo4j backup files"
    exit 1
fi

echo "Cleaning up backup files from neo4j pod..."
$CLUSTER_CMD exec -it viewer-neo4j-core-0 -n $NAMESPACE -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"

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
echo "  - xxx-cast-dir.tar.gz (Analysis Node CAST files)"
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