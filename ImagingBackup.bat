@echo off
REM =========================================================================
REM Imaging Kubernetes Backup Script
REM =========================================================================
REM This script performs a full backup of an Imaging instance on K8s
REM Ensure kubectl/oc is installed and configured before running this script
REM =========================================================================

setlocal enabledelayedexpansion

REM Configuration
if "%~2"=="" (
    echo Usage: %~nx0 ^<namespace^> ^<backup_dir^>
    exit /b 1
)
set NAMESPACE=%~1
set BACKUP_DIR=%~2
set CLUSTER_CMD=kubectl
REM kubectl 1.30+ streams exec over WebSockets, which breaks large file transfers; force SPDY
set KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false
set OPENSHIFT_CHECK="n"
set BACKUP_CASTDIR=false
REM Set to false to skip the postgres backup (e.g. when an external postgres instance is used)
set BACKUP_POSTGRES=true
REM Large files are downloaded in chunks of this size, each one size-checked and retried
set CHUNK_MB=256
set /a CHUNK_BYTES=CHUNK_MB*1048576

echo =========================================================================
echo Imaging Kubernetes Backup Procedure
echo =========================================================================
echo Namespace: %NAMESPACE%
echo Backup Directory: %BACKUP_DIR%
echo =========================================================================
echo.

REM Check if running on OpenShift
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
set SHARED_DONE=false

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
    
    REM The shared directory is one volume mounted by every analysis node: back it up from the first pod
    REM (not necessarily -0: with AnalysisNodeAutoscaling any ordinal can be the one running)
    if "!SHARED_DONE!"=="false" (
        set SHARED_DONE=true
        echo Connecting to !POD_NAME! and creating shared directory backup...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -czpf /opt/cast/shared/shared-dir.tar.gz --exclude='/opt/cast/shared/shared-dir.tar.gz' --exclude='/opt/cast/shared/lost+found' /opt/cast/shared/*"
        if errorlevel 1 (
            echo ERROR: Failed to create archive file
            exit /b 1
        )
        
        echo Downloading shared-dir.tar.gz from !POD_NAME!...
        call :download_file !POD_NAME! /opt/cast/shared/shared-dir.tar.gz "%BACKUP_DIR%\shared-dir.tar.gz"
        if errorlevel 1 (
            echo ERROR: Failed to download shared-dir.tar.gz from !POD_NAME!
            exit /b 1
        )
        
        echo Cleaning up shared-dir backup file from !POD_NAME!...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm -f /opt/cast/shared/shared-dir.tar.gz"
        echo.
    )
    
    REM Backup CAST directory for all pods (optional)
    if /i "%BACKUP_CASTDIR%"=="true" (
        echo Connecting to !POD_NAME! and creating CAST directory backup...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "tar -czpf /usr/share/CAST/cast-dir.tar.gz --exclude='/usr/share/CAST/cast-dir.tar.gz' --exclude='/usr/share/CAST/lost+found' /usr/share/CAST/*"
        if errorlevel 1 (
            echo ERROR: Failed to create archive file
            exit /b 1
        )

        echo Downloading cast-dir.tar.gz from !POD_NAME!...
        call :download_file !POD_NAME! /usr/share/CAST/cast-dir.tar.gz "%BACKUP_DIR%\!POD_NAME!-cast-dir.tar.gz"
        if errorlevel 1 (
            echo ERROR: Failed to download cast-dir.tar.gz from !POD_NAME!
            exit /b 1
        )

        echo Cleaning up cast-dir backup file from !POD_NAME!...
        %CLUSTER_CMD% exec -it !POD_NAME! -n %NAMESPACE% -- /bin/bash -c "rm -f /usr/share/CAST/cast-dir.tar.gz"
    ) else (
        echo Skipping CAST directory backup for !POD_NAME! ^(BACKUP_CASTDIR is not set to true^)
    )

    echo Backup for !POD_NAME! completed successfully.
    echo.
)

echo All Analysis Node backups completed successfully.
echo.

echo =========================================================================
echo Step 2: Backing up CSS Postgres instance...
echo =========================================================================

set POSTGRES_POD=
if /i "%BACKUP_POSTGRES%"=="true" (
    echo Finding postgres pod name...
    for /f "tokens=1" %%i in ('%CLUSTER_CMD% get pods -n %NAMESPACE% ^| findstr console-postgres') do set POSTGRES_POD=%%i
)

if /i not "%BACKUP_POSTGRES%"=="true" (
    echo Skipping postgres backup ^(BACKUP_POSTGRES is not set to true^)
) else if not "%POSTGRES_POD%"=="" (
    echo Found postgres pod: %POSTGRES_POD%
    echo.

    echo Creating backup directory in postgres pod...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "mkdir -p %PG_DATA_PATH%/backup"

    echo Running pg_dumpall...
    %CLUSTER_CMD% exec -it %POSTGRES_POD% -n %NAMESPACE% -- /bin/bash -c "pg_dumpall -v -U operator -p 5432 -f %PG_DATA_PATH%/backup/all_databases.backup > %PG_DATA_PATH%/backup/postgres_backup.log 2>&1"
    if errorlevel 1 (
        %CLUSTER_CMD% exec %POSTGRES_POD% -n %NAMESPACE% -- cat %PG_DATA_PATH%/backup/postgres_backup.log > "%BACKUP_DIR%\postgres_backup.log"
        if errorlevel 1 echo WARNING: Failed to download postgres_backup.log
        echo ERROR: pg_dumpall has encountered issues. Check log file.
        exit /b 1
    )

    echo Downloading all_databases.backup...
    call :download_file %POSTGRES_POD% %PG_DATA_PATH%/backup/all_databases.backup "%BACKUP_DIR%\all_databases.backup"
    if errorlevel 1 (
        echo ERROR: Failed to download all_databases.backup
        exit /b 1
    )

    echo Downloading postgres backup log...
    %CLUSTER_CMD% exec %POSTGRES_POD% -n %NAMESPACE% -- cat %PG_DATA_PATH%/backup/postgres_backup.log > "%BACKUP_DIR%\postgres_backup.log"
    if errorlevel 1 echo WARNING: Failed to download postgres_backup.log, continuing...

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
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "mkdir -p /var/lib/neo4j/config/neo4j5_data/backup && rm -rf /var/lib/neo4j/config/neo4j5_data/backup/*"

echo Running neo4j-admin database backup...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database backup --verbose --compress=true --include-metadata=all --pagecache=4G --to-path /var/lib/neo4j/config/neo4j5_data/backup --from=localhost:6362 '*' > /var/lib/neo4j/logs/backup_ImagingDatabases.log 2>&1"
if errorlevel 1 (
    %CLUSTER_CMD% exec viewer-neo4j-core-0 -n %NAMESPACE% -- cat /var/lib/neo4j/logs/backup_ImagingDatabases.log > "%BACKUP_DIR%\backup_ImagingDatabases.log"
    if errorlevel 1 echo WARNING: Failed to download backup_ImagingDatabases.log
    echo ERROR: Neo4j backup has encountered issues. Check log file.
    exit /b 1
)

echo Inspecting backup files...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "neo4j-admin database backup --inspect-path=/var/lib/neo4j/config/neo4j5_data/backup"

echo Downloading backup log...
%CLUSTER_CMD% exec viewer-neo4j-core-0 -n %NAMESPACE% -- cat /var/lib/neo4j/logs/backup_ImagingDatabases.log > "%BACKUP_DIR%\backup_ImagingDatabases.log"
if errorlevel 1 echo WARNING: Failed to download backup_ImagingDatabases.log, continuing...

echo Downloading Neo4j backup files...
if not exist "%BACKUP_DIR%\backup" mkdir "%BACKUP_DIR%\backup"
%CLUSTER_CMD% exec viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "tar cf /var/lib/neo4j/config/neo4j5_data/neo4j.tar /var/lib/neo4j/config/neo4j5_data/backup"
if errorlevel 1 (
    echo ERROR: Failed to create Neo4j backup archive
    exit /b 1
)
call :download_file viewer-neo4j-core-0 /var/lib/neo4j/config/neo4j5_data/neo4j.tar "%BACKUP_DIR%\backup\neo4j.tar"
if errorlevel 1 (
    echo ERROR: Failed to download Neo4j backup files
    exit /b 1
)

echo Cleaning up backup files from neo4j pod...
%CLUSTER_CMD% exec -it viewer-neo4j-core-0 -n %NAMESPACE% -- /bin/bash -c "rm -rf /var/lib/neo4j/config/neo4j5_data/backup/* /var/lib/neo4j/config/neo4j5_data/neo4j.tar"

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
echo   - xxx-cast-dir.tar.gz (Analysis Node CAST files, if BACKUP_CASTDIR=true)
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
exit /b 0

REM =========================================================================
REM  Subroutines
REM =========================================================================

:download_file
REM  %1 = pod  %2 = remote file  %3 = local file
REM  Transfers in CHUNK_MB chunks, checking each chunk's size and retrying it on mismatch
REM  (a single large kubectl exec stream can be cut short without kubectl reporting an error)
set "DL_POD=%~1"
set "DL_REMOTE=%~2"
set "DL_LOCAL=%~3"
set DL_SIZE=
for /f "tokens=1-3" %%a in ('%CLUSTER_CMD% exec %DL_POD% -n %NAMESPACE% -- sh -c "s=$(stat -c %%s %DL_REMOTE%) && n=$(( (s + %CHUNK_BYTES% - 1) / %CHUNK_BYTES% )) && echo $s $n $(( s - (n - 1) * %CHUNK_BYTES% ))" 2^>nul') do (
    set DL_SIZE=%%a
    set DL_CHUNKS=%%b
    set DL_LAST=%%c
)
if "%DL_SIZE%"=="" (
    echo ERROR: Cannot read size of %DL_REMOTE% in %DL_POD%
    exit /b 1
)
echo   %DL_SIZE% bytes in %DL_CHUNKS% chunk^(s^)
type nul > "%DL_LOCAL%"
set /a DL_LASTIDX=DL_CHUNKS-1
for /L %%i in (0,1,%DL_LASTIDX%) do (
    call :download_chunk %%i
    if errorlevel 1 exit /b 1
)
for %%f in ("%DL_LOCAL%") do set DL_GOT=%%~zf
if not "%DL_GOT%"=="%DL_SIZE%" (
    echo ERROR: %DL_LOCAL% is %DL_GOT% bytes, expected %DL_SIZE%
    exit /b 1
)
exit /b 0

:download_chunk
REM  %1 = chunk index
set /a DL_SKIP=%1*CHUNK_MB
set /a DL_NUM=%1+1
set DL_EXPECTED=%CHUNK_BYTES%
if %1==%DL_LASTIDX% set DL_EXPECTED=%DL_LAST%
set DL_TRY=0
:download_chunk_retry
set /a DL_TRY+=1
echo   chunk %DL_NUM%/%DL_CHUNKS%...
REM The trailing sleep keeps the stream open so data still in flight is not dropped when dd exits
%CLUSTER_CMD% exec %DL_POD% -n %NAMESPACE% -- sh -c "dd if=%DL_REMOTE% bs=1M skip=%DL_SKIP% count=%CHUNK_MB% 2>/dev/null; sleep 5" > "%DL_LOCAL%.part"
set DL_GOT=0
for %%f in ("%DL_LOCAL%.part") do set DL_GOT=%%~zf
if "%DL_GOT%"=="%DL_EXPECTED%" goto download_chunk_ok
if %DL_TRY% GEQ 5 (
    echo ERROR: chunk %DL_NUM%/%DL_CHUNKS% of %DL_REMOTE% still incomplete after %DL_TRY% attempts
    del "%DL_LOCAL%.part"
    exit /b 1
)
echo   chunk %DL_NUM%/%DL_CHUNKS% incomplete ^(%DL_GOT% of %DL_EXPECTED% bytes^), retrying...
goto download_chunk_retry
:download_chunk_ok
copy /b "%DL_LOCAL%"+"%DL_LOCAL%.part" "%DL_LOCAL%" >nul
del "%DL_LOCAL%.part"
exit /b 0