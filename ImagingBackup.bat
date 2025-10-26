@echo off
REM =========================================================================
REM Imaging 3.4.x Kubernetes Backup Script
REM =========================================================================
REM This script performs a full backup of an Imaging 3.4.x instance on K8s
REM Ensure kubectl/oc is installed and configured before running this script
REM =========================================================================

setlocal enabledelayedexpansion

REM Configuration
set NAMESPACE=castimaging-v3
set BACKUP_DIR=.\imaging_backup_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set BACKUP_DIR=%BACKUP_DIR: =0%
set CLUSTER_CMD=kubectl

echo =========================================================================
echo Imaging 3.4.x Kubernetes Backup Procedure
echo =========================================================================
echo Namespace: %NAMESPACE%
echo Backup Directory: %BACKUP_DIR%
echo =========================================================================
echo.

REM Ask about OpenShift
set /p OPENSHIFT_CHECK="Are you running on OpenShift? (y/n): "
if /i "%OPENSHIFT_CHECK%"=="y" (
    set CLUSTER_CMD=oc
    echo Using OpenShift oc commands
    set PG_DATA_PATH=/var/lib/pgsql/data
) else (
    echo Using standard Kubernetes kubectl commands
	set PG_DATA_PATH=/var/lib/postgresql/data
)
echo.

echo IMPORTANT: Ensure the Imaging instance is quiet (no activity in Console)
echo Press Ctrl+C to cancel, or
pause

REM Create backup directory
echo Creating backup directory...
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
if errorlevel 1 (
    echo ERROR: Failed to create backup directory
    exit /b 1
)
echo Backup directory created: %BACKUP_DIR%
echo.

echo =========================================================================
echo Step 1: Backing up Analysis Node files...
echo =========================================================================

echo Discovering console-analysis-node-core pods...
set POD_COUNT=0

REM First, count how many pods exist
for /f "tokens=*" %%i in ('%CLUSTER_CMD% get pods -n %NAMESPACE% -o name ^| findstr /b "pod/console-analysis-node-core-"') do (
    set /a POD_COUNT+=1
)

if %POD_COUNT%==0 (
    echo ERROR: No console-analysis-node-core pods found
    exit /b 1
)

echo Found %POD_COUNT% console-analysis-node-core pod(s)
echo.

REM Loop through each pod
for /f "tokens=*" %%i in ('%CLUSTER_CMD% get pods -n %NAMESPACE% -o name ^| findstr /b "pod/console-analysis-node-core-"') do (
    REM Extract pod name from "pod/console-analysis-node-core-X"
    set "POD_FULL=%%i"
    set "POD_NAME=!POD_FULL:pod/=!"
    
    echo ============================================
    echo Processing pod: !POD_NAME!
    echo ============================================
    
    REM Only backup shared directory for console-analysis-node-core-0
    if "!POD_NAME!"=="console-analysis-node-core-0" (
        echo Connecting to !POD_NAME! and creating shared directory backup...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -czpf /opt/cast/shared/shared-dir.tar.gz --exclude='/opt/cast/shared/shared-dir.tar.gz' --exclude='/opt/cast/shared/lost+found' /opt/cast/shared/*"
        if errorlevel 1 (
            echo WARNING: Some files may have been skipped due to permissions
        )
        
        echo Downloading shared-dir.tar.gz from !POD_NAME!...
        %CLUSTER_CMD% cp %NAMESPACE%/!POD_NAME!:/opt/cast/shared/shared-dir.tar.gz "%BACKUP_DIR%\shared-dir.tar.gz"
        if errorlevel 1 (
            echo ERROR: Failed to download shared-dir.tar.gz from !POD_NAME!
            exit /b 1
        )
        
        echo Cleaning up shared-dir backup file from !POD_NAME!...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm -f /opt/cast/shared/shared-dir.tar.gz"
        echo.
    )
    
    REM Backup CAST directory for all pods
    echo Connecting to !POD_NAME! and creating CAST directory backup...
    %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -czpf /usr/share/CAST/cast-dir.tar.gz --exclude='/usr/share/CAST/cast-dir.tar.gz' --exclude='/usr/share/CAST/lost+found' /usr/share/CAST/*"
    if errorlevel 1 (
        echo WARNING: Some files may have been skipped due to permissions
    )
    
    echo Downloading cast-dir.tar.gz from !POD_NAME!...
    %CLUSTER_CMD% cp %NAMESPACE%/!POD_NAME!:/usr/share/CAST/cast-dir.tar.gz "%BACKUP_DIR%\!POD_NAME!-cast-dir.tar.gz"
    if errorlevel 1 (
        echo ERROR: Failed to download cast-dir.tar.gz from !POD_NAME!
        exit /b 1
    )
    
    echo Cleaning up cast-dir backup file from !POD_NAME!...
    %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm -f /usr/share/CAST/cast-dir.tar.gz"
    
    echo Backup for !POD_NAME! completed successfully.
    echo.
)

echo All Analysis Node backups completed successfully.
echo.

echo =========================================================================
echo Step 2: Backing up CSS Postgres instance...
echo =========================================================================

echo Finding postgres pod name...
for /f "tokens=1" %%i in ('%CLUSTER_CMD% get pods -n %NAMESPACE% ^| findstr console-postgres') do set POSTGRES_POD=%%i

if not "%POSTGRES_POD%"=="" (
    echo Found postgres pod: %POSTGRES_POD%
    echo.

    echo Creating backup directory in postgres pod...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "mkdir -p %PG_DATA_PATH%/backup"

    echo Running pg_dumpall...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "pg_dumpall -U operator -p 5432 -f %PG_DATA_PATH%/backup/all_databases.backup > %PG_DATA_PATH%/backup/postgres_backup.log 2>&1"
    if errorlevel 1 (
        echo WARNING: pg_dumpall may have encountered issues. Check log file.
    )

    echo Downloading all_databases.backup...
    %CLUSTER_CMD% cp %NAMESPACE%/%POSTGRES_POD%:%PG_DATA_PATH%/backup/all_databases.backup "%BACKUP_DIR%\all_databases.backup"
    if errorlevel 1 (
        echo ERROR: Failed to download all_databases.backup
        exit /b 1
    )

    echo Downloading postgres backup log...
    %CLUSTER_CMD% cp %NAMESPACE%/%POSTGRES_POD%:%PG_DATA_PATH%/backup/postgres_backup.log "%BACKUP_DIR%\postgres_backup.log"

    echo Cleaning up backup files from postgres pod...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "rm -rf %PG_DATA_PATH%/backup"

    echo Postgres backup completed successfully.
    echo.
) else (
    echo WARNING: Could not find postgres pod, skipping postgres backup
)

echo =========================================================================
echo Step 3: Backing up Neo4j databases...
echo =========================================================================

echo Connecting to viewer-neo4j-core-0...
echo Creating/cleaning backup directory...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -f /var/lib/neo4j/config/neo4j5_data/backup/*"

echo Running neo4j-admin database backup...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database backup --verbose --compress=true --include-metadata=all --pagecache=4G --to-path /var/lib/neo4j/config/neo4j5_data/backup --from=localhost:6362 '*' > /var/lib/neo4j/logs/backup_ImagingDatabases.log 2>&1"
if errorlevel 1 (
    echo WARNING: Neo4j backup may have encountered issues. Check log file.
)

echo Inspecting backup files...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database backup --inspect-path=/var/lib/neo4j/config/neo4j5_data/backup"

echo Downloading backup log...
%CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/logs/backup_ImagingDatabases.log "%BACKUP_DIR%\backup_ImagingDatabases.log"

echo Downloading Neo4j backup files...
if not exist "%BACKUP_DIR%\backup" mkdir "%BACKUP_DIR%\backup"
%CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup "%BACKUP_DIR%\backup"
if errorlevel 1 (
    echo ERROR: Failed to download Neo4j backup files
    exit /b 1
)

echo Cleaning up backup files from neo4j pod...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"

echo Neo4j backup completed successfully.
echo.

echo =========================================================================
echo BACKUP COMPLETED SUCCESSFULLY
echo =========================================================================
echo.
echo All backup files have been saved to: %BACKUP_DIR%
echo.
echo Backup contents:
echo   - shared-dir.tar.gz (Analysis Node shared files)
echo   - xxx-cast-dir.tar.gz (Analysis Node CAST files)
echo   - all_databases.backup (Postgres databases)
echo   - postgres_backup.log (Postgres backup log)
echo   - backup\ (Neo4j database backups)
echo   - backup_ImagingDatabases.log (Neo4j backup log)
echo.
echo Please review the postgres_backup.log and backup_ImagingDatabases.log files for any errors.
echo.
echo =========================================================================

endlocal
pause