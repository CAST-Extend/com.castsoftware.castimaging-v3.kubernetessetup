@echo off

:: Variables to be set
set NAMESPACE=castimaging-v3
set VIEWER-SERVER-SEARCH-ARG=viewer-server
set VIEWER-ETL-SEARCH-ARG=viewer-etl
set VIEWER-NEO4J-SEARCH-ARG=viewer-neo4j


:RetrievePodNames
echo Retrieving pod names...

:: Retrieve the name of the pod that starts with the search string
for /f "tokens=*" %%i in ('kubectl get pods -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name" ^| findstr "^%VIEWER-SERVER-SEARCH-ARG%"') do set VIEWER-SERVER-POD-NAME=%%i
:: Check if the pod name was found
if "%VIEWER-SERVER-POD-NAME%"=="" (
    echo No pod found starting with %VIEWER-SERVER-SEARCH-ARG% in namespace %NAMESPACE%.
    pause
    exit /b 1
)
echo Pod found: %VIEWER-SERVER-POD-NAME%


for /f "tokens=*" %%i in ('kubectl get pods -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name" ^| findstr "^%VIEWER-ETL-SEARCH-ARG%"') do set VIEWER-ETL-POD-NAME=%%i
:: Check if the pod name was found
if "%VIEWER-ETL-POD-NAME%"=="" (
    echo No pod found starting with %VIEWER-ETL-SEARCH-ARG% in namespace %NAMESPACE%.
    pause
    exit /b 1
)
echo Pod found: %VIEWER-ETL-POD-NAME%


for /f "tokens=*" %%i in ('kubectl get pods -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name" ^| findstr "^%VIEWER-NEO4J-SEARCH-ARG%"') do set VIEWER-NEO4J-POD-NAME=%%i
:: Check if the pod name was found
if "%VIEWER-NEO4J-POD-NAME%"=="" (
    echo No pod found starting with %VIEWER-NEO4J-SEARCH-ARG% in namespace %NAMESPACE%.
    pause
    exit /b 1
)
echo Pod found: %VIEWER-NEO4J-POD-NAME%


:: Execute the kubectl cp commands
echo Copying files inside pods...

kubectl cp config\imaging\server\.     %NAMESPACE%/%VIEWER-SERVER-POD-NAME%:/opt/imaging/config --container=viewer-server
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp -n viewer-server config\imaging\neo4j\csv\.  %NAMESPACE%/%VIEWER-SERVER-POD-NAME%:/opt/imaging/imaging-service/upload --container=viewer-server
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp -n viewer-etl config\imaging\etl\.        %NAMESPACE%/%VIEWER-ETL-POD-NAME%:/opt/imaging/imaging-etl/config --container=viewer-etl
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp -n viewer-etl config\imaging\neo4j\csv\.  %NAMESPACE%/%VIEWER-ETL-POD-NAME%:/opt/imaging/imaging-etl/upload --container=viewer-etl
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp -n viewer-neo4j config\imaging\neo4j\.      %NAMESPACE%/%VIEWER-NEO4J-POD-NAME%:/var/lib/neo4j/config --container=viewer-neo4j
:: Check if the copy command succeeded
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
echo Copy complete. 
