@echo off

set NAMESPACE=castimaging-v3

REM Update the path to your custom values file
REM Among the provided values: enable Extend Proxy and set its exthostname
set CUSTOM_VALUES=.\values-custom.yaml

setlocal enabledelayedexpansion

echo ----------------------------------------------
echo Installing helm chart...
echo ----------------------------------------------
helm install %NAMESPACE% --create-namespace --namespace %NAMESPACE% -f %CUSTOM_VALUES% .
kubectl rollout status deployment/console-service  --timeout=900s -n %NAMESPACE%

echo Retrieving logs from pod extendproxy-0...
kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace %NAMESPACE% > "%TEMP%\extendproxy_logs.txt"
if errorlevel 1 (
    echo ERROR: Failed to retrieve logs from pod extendproxy-0.
    exit /b 1
)
echo ----------------------------------------------
echo Extracting Apikey for Extend Proxy...
echo ----------------------------------------------
set "APIKEY="
for /f "tokens=*" %%L in ('findstr /c:"Apikey for Extend Proxy:" "%TEMP%\extendproxy_logs.txt"') do (
    for /f "tokens=5" %%K in ("%%L") do (
        set "APIKEY=%%K"
    )
)

if not defined APIKEY (
    echo No extendproxy/Apikey found.
    exit /b 1
)

echo Found extendproxy Apikey: !APIKEY!

echo ----------------------------------------------
echo Running helm upgrade with extracted Apikey...
echo ----------------------------------------------
helm upgrade %NAMESPACE% --namespace %NAMESPACE% -f %CUSTOM_VALUES% --set ExtendApiKey=!APIKEY! .
if errorlevel 1 (
    echo ERROR: helm upgrade failed.
    exit /b 1
)

kubectl scale deployment  console-service               --replicas=0 -n %NAMESPACE%
kubectl scale deployment  console-control-panel         --replicas=0 -n %NAMESPACE%
kubectl scale statefulset  console-analysis-node-core   --replicas=0 -n %NAMESPACE%

kubectl rollout status deployment/console-service               --timeout=120s -n %NAMESPACE%
kubectl rollout status deployment/console-control-panel         --timeout=120s -n %NAMESPACE%
kubectl rollout status statefulset/console-analysis-node-core    --timeout=120s -n %NAMESPACE%

helm upgrade %NAMESPACE% --namespace %NAMESPACE% -f %CUSTOM_VALUES% --set ExtendApiKey=!APIKEY! .
if errorlevel 1 (
    echo ERROR: helm upgrade failed.
    exit /b 1
)

echo .
kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace %NAMESPACE% | findstr /c:"Extend Proxy Admin Center"
echo ----------------------------------------------
echo You can add this ExtendApiKey to the values-custom.yaml file for future use:
echo ExtendApiKey: !APIKEY!
echo ----------------------------------------------
endlocal