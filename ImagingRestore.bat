@echo off
REM =========================================================================
REM Imaging Kubernetes Restore Script
REM =========================================================================
REM This script restores an Imaging instance from backup files
REM Ensure kubectl is installed and configured before running this script
REM A freshly installed, empty Imaging instance must be running at target
REM =========================================================================
setlocal enabledelayedexpansion
REM Configuration
set NAMESPACE=castimaging-v3
set BACKUP_DIR=.\mybackupfolder
set USE_OC=false
set CLUSTER_CMD=kubectl
set OPENSHIFT_CHECK="n"

echo =========================================================================
echo Imaging Kubernetes Restore Procedure - SINGLE TENANT
echo =========================================================================
echo Namespace: %NAMESPACE%
echo Backup Directory: %BACKUP_DIR%
echo =========================================================================
echo.
echo CRITICAL WARNINGS:
echo   - A freshly installed, empty Imaging instance must be running
echo   - The namespace must match the original backup source
echo   - All data in the target instance will be replaced
echo.
set /p CONTINUE="Type YES to continue with restore: "
if /i not "%CONTINUE%"=="YES" (
    echo Restore cancelled.
    exit /b 0
)
echo.
REM Check if running on OpenShift
if /i "%OPENSHIFT_CHECK%"=="y" (
    set USE_OC=true
    set %CLUSTER_CMD% exec=oc exec
    echo Using OpenShift commands (oc)
    set PG_DATA_PATH=/var/lib/pgsql/data
) else (
    echo Using standard Kubernetes commands (kubectl)
	set PG_DATA_PATH=/var/lib/postgresql/data
)
echo.

echo =========================================================================
echo Step 1: Restoring Analysis Node files...
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
    
    REM Only restore shared directory for console-analysis-node-core-0
    if "!POD_NAME!"=="console-analysis-node-core-0" (
        echo Checking if shared-dir.tar.gz exists...
        if exist "%BACKUP_DIR%\shared-dir.tar.gz" (
            echo Uploading shared-dir.tar.gz to !POD_NAME!...
			type "%BACKUP_DIR%\shared-dir.tar.gz" | %CLUSTER_CMD% exec -n %NAMESPACE% !POD_NAME! -i -- sh -c "cat > /opt/cast/shared/shared-dir.tar.gz"
            if errorlevel 1 (
                echo ERROR: Failed to upload shared-dir.tar.gz to !POD_NAME!
                exit /b 1
            )
            
            echo Extracting shared-dir.tar.gz on !POD_NAME!...
            %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -xzpf /opt/cast/shared/shared-dir.tar.gz --strip-components=3 --ignore-failed-read -C /opt/cast/shared/"
            if errorlevel 1 (
                echo WARNING: issue encountered while extracting shared-dir.tar.gz on !POD_NAME!
            )
            
            echo Cleaning up shared-dir archive from !POD_NAME!...
            %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm /opt/cast/shared/shared-dir.tar.gz"
            echo.
        ) else (
            echo WARNING: shared-dir.tar.gz not found in backup directory
            echo.
        )
    )
    
    REM Restore CAST directory for all pods using pod-specific backup
    set "CAST_BACKUP=%BACKUP_DIR%\!POD_NAME!-cast-dir.tar.gz"
    echo Checking if !POD_NAME!-cast-dir.tar.gz exists...
    if exist "!CAST_BACKUP!" (
        echo Uploading !POD_NAME!-cast-dir.tar.gz to !POD_NAME!...
        type "!CAST_BACKUP!" | %CLUSTER_CMD% exec -n %NAMESPACE% !POD_NAME! -i -- sh -c "cat > /usr/share/CAST/cast-dir.tar.gz"
        if errorlevel 1 (
            echo ERROR: Failed to upload cast-dir.tar.gz to !POD_NAME!
            exit /b 1
        )
        
        echo Extracting cast-dir.tar.gz on !POD_NAME!...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -xzpf /usr/share/CAST/cast-dir.tar.gz --strip-components=3 --ignore-failed-read -C /usr/share/CAST/"
        if errorlevel 1 (
            echo WARNING: issue encountered while extracting cast-dir.tar.gz on !POD_NAME!
        )
        
        echo Cleaning up cast-dir archive from !POD_NAME!...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm /usr/share/CAST/cast-dir.tar.gz"
        
        echo Restore for !POD_NAME! completed successfully.
        echo.
    ) else (
        echo ERROR: Backup file !POD_NAME!-cast-dir.tar.gz not found
        exit /b 1
    )
)
echo All Analysis Node files restored successfully.
echo.
:pgrestore
echo =========================================================================
echo Step 2: Restoring CSS Postgres instance...
echo =========================================================================
echo Stopping all services except postgres and neo4j...
%CLUSTER_CMD% scale deployment  console-dashboards             --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale statefulset console-analysis-node-core     --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  console-service                --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  console-authentication-service --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  console-gateway-service        --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  console-control-panel          --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  console-sso-service            --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  viewer-aimanager               --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  viewer-api                     --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  viewer-etl                     --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  viewer-server                  --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  extendproxy                    --replicas=0 -n %NAMESPACE%
%CLUSTER_CMD% scale deployment  mcp-server                     --replicas=0 -n %NAMESPACE%
echo Waiting for services to scale down...
timeout /t 10 /nobreak >nul
echo.
echo Finding postgres pod name...
for /f "tokens=1" %%i in ('%CLUSTER_CMD% get pods -n %NAMESPACE% ^| findstr console-postgres') do set POSTGRES_POD=%%i
if not "%POSTGRES_POD%"=="" (
    echo Found postgres pod: %POSTGRES_POD%
    echo.
    if "%OPENSHIFT%"=="true" (
        set PG_DATA_PATH=/var/lib/pgsql/data
    ) else (
        set PG_DATA_PATH=/var/lib/postgresql/data
    )
    echo Uploading all_databases.backup to postgres pod...
	type "%BACKUP_DIR%\all_databases.backup" | %CLUSTER_CMD% exec -n %NAMESPACE% %POSTGRES_POD% -i -- sh -c "cat > %PG_DATA_PATH%/all_databases.backup"
    if errorlevel 1 (
        echo ERROR: Failed to upload all_databases.backup
        exit /b 1
    )
    echo Dropping existing databases in postgres...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "psql -U postgres -c 'drop database keycloak;'"
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "psql -U postgres -c 'drop schema control_panel cascade;'"
    echo Restoring postgres databases from backup...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "psql -U postgres -f %PG_DATA_PATH%/all_databases.backup > %PG_DATA_PATH%/postgres_restore.log 2>&1"
    if errorlevel 1 (
        echo ERROR: Postgres restore encountered issues. Check log file.
        exit /b 1
    )
    echo.
    echo Running ANALYZE commands...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "psql -U operator -p 5432 -c 'ANALYZE;' -d keycloak"
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "psql -U operator -p 5432 -c 'ANALYZE;' -d postgres"
    echo Downloading postgres restore log...
    %CLUSTER_CMD% cp %NAMESPACE%/%POSTGRES_POD%:%PG_DATA_PATH%/postgres_restore.log "%BACKUP_DIR%\postgres_restore.log"
    echo Cleaning up backup files from postgres pod...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "rm -f %PG_DATA_PATH%/all_databases.backup %PG_DATA_PATH%/postgres_restore.log"
    echo Postgres restore done.
    echo.
) else (
    echo WARNING: Could not find postgres pod, skipping postgres restore
)
:neo4j
echo =========================================================================
echo Step 3: Restoring Neo4j databases...
echo =========================================================================
echo Creating/cleaning backup directory...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"
echo Creating temporary cypher scripts...
(
echo drop database neo4j if exists;
echo drop database imaging if exists;
echo drop database packagereference if exists;
echo create database neo4j;
echo create database imaging;
echo create database packagereference;
echo stop database neo4j;
echo stop database imaging;
echo stop database packagereference;
) > "%BACKUP_DIR%\backup\neo4j_drop_create.cypher"
echo Starting restored databases...
(
echo start database neo4j;
echo start database imaging;
echo start database packagereference;
echo show databases;
) > "%BACKUP_DIR%\backup\neo4j_start.cypher"
echo Uploading cypher scripts...
%CLUSTER_CMD% cp -n %NAMESPACE% "%BACKUP_DIR%\backup\neo4j_drop_create.cypher"	viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup/neo4j_drop_create.cypher
if errorlevel 1 (
    echo ERROR: Failed to upload neo4j_drop_create.cypher
    exit /b 1
)
%CLUSTER_CMD% cp -n %NAMESPACE% "%BACKUP_DIR%\backup\neo4j_start.cypher" 		viewer-neo4j-core-0:/var/lib/neo4j/config/neo4j5_data/backup/neo4j_start.cypher
if errorlevel 1 (
    echo ERROR: Failed to upload neo4j_start.cypher
    exit /b 1
)
echo Uploading Neo4j backup file...
%CLUSTER_CMD% exec -n %NAMESPACE% viewer-neo4j-core-0 -i -- sh -c "cat > /var/lib/neo4j/config/neo4j5_data/neo4j.tar" < "%BACKUP_DIR%\backup\neo4j.tar"
if errorlevel 1 (
    echo ERROR: Failed to upload Neo4j backup files
    exit /b 1
)
echo Expanding Neo4j backup files...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "tar -xf /var/lib/neo4j/config/neo4j5_data/neo4j.tar --strip-components=5 -C /var/lib/neo4j/config/neo4j5_data/"
if errorlevel 1 (
    echo ERROR: Failed to expand Neo4j backup files
    exit /b 1
)
echo Dropping and recreating Neo4j databases...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_drop_create.cypher"
if errorlevel 1 (
    echo ERROR: Failed to execute neo4j_drop_create.cypher
    exit /b 1
)
del %BACKUP_DIR%\backup\neo4j_drop_create.cypher
echo Restoring neo4j database...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=neo4j neo4j > /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if errorlevel 1 (
	echo ERROR: neo4j database restore encountered issues. Check neo4j_restore.log file.
    %CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "%BACKUP_DIR%\neo4j_restore.log"
    exit /b 1
)
echo Restoring imaging database...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=imaging imaging >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if errorlevel 1 (
	echo ERROR: imaging database restore encountered issues. Check neo4j_restore.log file.
    %CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "%BACKUP_DIR%\neo4j_restore.log"
    exit /b 1
)
echo Restoring packagereference database...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database restore --verbose --overwrite-destination=true --from-path=/var/lib/neo4j/config/neo4j5_data/backup --source-database=packagereference packagereference >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
if errorlevel 1 (
	echo ERROR: packagereference database restore encountered issues. Check neo4j_restore.log file.
    %CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "%BACKUP_DIR%\neo4j_restore.log"
    exit /b 1
)
echo Starting databases...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system -f /var/lib/neo4j/config/neo4j5_data/backup/neo4j_start.cypher"
if errorlevel 1 (
    echo ERROR: Failed to execute neo4j_start.cypher
    exit /b 1
)
del %BACKUP_DIR%\backup\neo4j_start.cypher
echo Executing permission scripts...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"neo4j\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/neo4j/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"imaging\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/imaging/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "cypher-shell -a localhost:7687 -u neo4j -p imaging -d system --param 'database => \"packagereference\"' -f /var/lib/neo4j/config/neo4j5_data/scripts/packagereference/restore_metadata.cypher >> /var/lib/neo4j/logs/neo4j_restore.log 2>&1"
echo Downloading Neo4j restore log...
%CLUSTER_CMD% cp %NAMESPACE%/viewer-neo4j-core-0:/var/lib/neo4j/logs/neo4j_restore.log "%BACKUP_DIR%\neo4j_restore.log"
echo Cleaning up archive files...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "rm -f /var/lib/neo4j/config/neo4j5_data/neo4j.tar"
echo Cleaning up Neo4j restore log from pod...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "rm -f /var/lib/neo4j/logs/neo4j_restore.log"
echo Restarting Neo4j pod...
%CLUSTER_CMD% scale statefulset viewer-neo4j-core --replicas=0 -n %NAMESPACE%
echo Waiting for Neo4j to stop...
:wait_neo4j_stop
%CLUSTER_CMD% get statefulset viewer-neo4j-core -n %NAMESPACE% | findstr "0/0" >nul
if errorlevel 1 (
    timeout /t 5 /nobreak >nul
    goto wait_neo4j_stop
)
echo Neo4j has been stopped successfully.
echo.
echo =========================================================================
echo Final Step: Starting all Imaging services...
echo =========================================================================
echo.
echo IMPORTANT: You must now start all Imaging services by either:
echo   1. Running Util-ScaleUpAll.bat script from the Imaging helm chart folder
echo   2. Running: helm upgrade %NAMESPACE% --namespace %NAMESPACE% .
echo =========================================================================
echo RESTORE COMPLETED
echo =========================================================================
echo.
echo Log files have been saved to: %BACKUP_DIR%
echo   - postgres_restore.log (Postgres restore log)
echo   - neo4j_restore.log (Neo4j restore and permissions log)
echo.
echo Please review these log files for any errors or warnings.
echo.
echo Next steps:
echo   1. Start all remaining services using helm upgrade or Util-ScaleUpAll script
echo   2. Verify the Imaging instance is functioning correctly
echo   3. Check the Console for any issues
echo.
echo =========================================================================
endlocal
pause