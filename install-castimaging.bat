@echo off

:: Variables to be set
set NAMESPACE=castimaging-v3
set VIEWER-SERVER-SEARCH-ARG=viewer-server
set VIEWER-ETL-SEARCH-ARG=viewer-etl
set VIEWER-NEO4J-SEARCH-ARG=viewer-neo4j

kubectl create ns %NAMESPACE%

echo Creating Persistent Volume Claims...
echo Console PVC...
kubectl apply -f ex_pvc-console.yaml
if errorlevel 1 (
    echo helm install failed.
    pause
    exit /b 1
) else (
    echo helm install succeeded.
)
echo Viewer PVC...
kubectl apply -f ex_pvc-imagingviewer.yaml
if errorlevel 1 (
    echo helm install failed.
    pause
    exit /b 1
) else (
    echo helm install succeeded.
)

timeout 30

echo Running helm install...
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
if errorlevel 1 (
    echo helm install failed.
    pause
    exit /b 1
) else (
    echo helm install succeeded.
)

:CheckPods
echo Checking pod statuses in the %NAMESPACE% namespace...

:: Get the status of all pods in the namespace
kubectl get pods -n %NAMESPACE% --no-headers > pod_status.txt

:: Initialize variables
set all_running=true

:: Loop through each pod status line
for /f "tokens=3" %%i in (pod_status.txt) do (
    echo Pod status: %%i
    if not "%%i"=="Running" (
        set all_running=false
    )
)

:: Check if all pods are running
if "%all_running%"=="true" (
    echo All pods are running!
    del pod_status.txt
    goto RetrievePodNames
) else (
    echo Not all pods are running, waiting and re-checking...
    timeout /t 10 /nobreak >nul
    goto CheckPods
)


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
kubectl cp -n viewer-neo4j config\imaging\neo4j\.      %NAMESPACE%/%VIEWER-NEO4J-POD-NAME%:viewer-neo4j/var/lib/neo4j/config --container=viewer-neo4j
:: Check if the copy command succeeded
if errorlevel 1 (
    echo Failed to copy files.
    pause
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
echo Copy complete. 

echo Scaling down some deployments... 
kubectl scale statefulset viewer-neo4j-core --replicas=0 -n %NAMESPACE%
kubectl scale statefulset console-analysis-node-core --replicas=0 -n %NAMESPACE%
kubectl scale deployment viewer-etl --replicas=0 -n %NAMESPACE%
kubectl scale deployment viewer-server --replicas=0 -n %NAMESPACE%

timeout 30

echo Running helm upgrade...
helm upgrade castimaging-v3 --namespace %NAMESPACE% --set version=3.0.0 .
if errorlevel 1 (
    echo helm upgrade failed.
    pause
    exit /b 1
) else (
    echo helm upgrade succeeded.
)

