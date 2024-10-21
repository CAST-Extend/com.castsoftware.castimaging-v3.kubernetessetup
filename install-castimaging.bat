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
    exit /b 1
) else (
    echo helm install succeeded.
)
echo Viewer PVC...
kubectl apply -f ex_pvc-imagingviewer.yaml
if errorlevel 1 (
    echo helm install failed.
    exit /b 1
) else (
    echo helm install succeeded.
)

timeout 10

echo Running helm install...
helm install castimaging-v3 --namespace castimaging-v3 --set version=3.0.0 .
if errorlevel 1 (
    echo helm install failed.
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
    exit /b 1
)
echo Pod found: %VIEWER-SERVER-POD-NAME%


for /f "tokens=*" %%i in ('kubectl get pods -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name" ^| findstr "^%VIEWER-ETL-SEARCH-ARG%"') do set VIEWER-ETL-POD-NAME=%%i
:: Check if the pod name was found
if "%VIEWER-ETL-POD-NAME%"=="" (
    echo No pod found starting with %VIEWER-ETL-SEARCH-ARG% in namespace %NAMESPACE%.
    exit /b 1
)
echo Pod found: %VIEWER-ETL-POD-NAME%


for /f "tokens=*" %%i in ('kubectl get pods -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name" ^| findstr "^%VIEWER-NEO4J-SEARCH-ARG%"') do set VIEWER-NEO4J-POD-NAME=%%i
:: Check if the pod name was found
if "%VIEWER-NEO4J-POD-NAME%"=="" (
    echo No pod found starting with %VIEWER-NEO4J-SEARCH-ARG% in namespace %NAMESPACE%.
    exit /b 1
)
echo Pod found: %VIEWER-NEO4J-POD-NAME%


:: Execute the kubectl cp commands
echo Copying files inside pods...

kubectl cp config\imaging\server\.     %NAMESPACE%/%VIEWER-SERVER-POD-NAME%:/opt/imaging/config
if errorlevel 1 (
    echo Failed to copy files.
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp config\imaging\neo4j\csv\.  %NAMESPACE%/%VIEWER-SERVER-POD-NAME%:/opt/imaging/imaging-service/upload
if errorlevel 1 (
    echo Failed to copy files.
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp config\imaging\etl\.        %NAMESPACE%/%VIEWER-ETL-POD-NAME%:/opt/imaging/imaging-etl/config
if errorlevel 1 (
    echo Failed to copy files.
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp config\imaging\neo4j\csv\.  %NAMESPACE%/%VIEWER-ETL-POD-NAME%:/opt/imaging/imaging-etl/upload
if errorlevel 1 (
    echo Failed to copy files.
    exit /b 1
) else (
    echo Files successfully copied to the pod.
)
kubectl cp config\imaging\neo4j\.      %NAMESPACE%/%VIEWER-NEO4J-POD-NAME%:/var/lib/neo4j/config
:: Check if the copy command succeeded
if errorlevel 1 (
    echo Failed to copy files.
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
    echo Failed to run helm upgrade.
    exit /b 1
) else (
    echo ******
    echo Done.
    echo ******
)

echo **********************************************************************************************
echo Extendproxy setup (optional):
echo **********************************************************************************************
echo     - run this command to create the extendproxy PVC:
echo        kubectl apply -f ex_pvc-extend-proxy.yaml
echo     - rename ex_extendproxy-service.yaml into extendproxy-service.yaml
echo     - run "helm-upgrade.bat"
echo     - Get the extendproxy service "External Endpoint" DNS name from K8S Dashboard
echo         For instance: a33300000000004523be8231c11431899-1907755555.us-east-2.elb.amazonaws.com
echo     - Update the exthostname variable in values.yaml with this name, for instance:
echo        ExtendProxy:
echo          exthostname: a33300000000004523be8231c11431899-1907755555.us-east-2.elb.amazonaws.com
echo     - rename ex_extendproxy-deployment.yaml into extendproxy-deployment.yaml
echo     - run "helm-upgrade.bat"
echo     - Review the log of extendproxy pod to get the administration URL and extend token
echo **********************************************************************************************
