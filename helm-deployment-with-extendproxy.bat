@echo off

REM ##############################################################
REM Batch Parameters
REM ##############################################################
set NAMESPACE=castimaging-v3
REM Helm action: install or upgrade
set ACTION=install
REM Bundle file to be uploaded. Leave empty to skip:
set BUNDLE_FILE_PATH=C:\temp\linux-bundle\CastArchive_134230312386136230_linux_x64.extarchive
REM Provide the path to your custom values file (will override values set in values.yaml):
set CUSTOM_VALUES=.\values-custom.yaml
REM ##############################################################

setlocal enabledelayedexpansion

kubectl create ns %NAMESPACE%
echo ----------------------------------------------
echo Running helm chart %ACTION%...
echo ----------------------------------------------
helm %ACTION% %NAMESPACE% --namespace %NAMESPACE% -f %CUSTOM_VALUES% .
kubectl rollout status deployment/extendproxy  --timeout=900s -n %NAMESPACE%

echo Retrieving logs from pod extendproxy...
kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace %NAMESPACE% > "%TEMP%\extendproxy_logs.txt"
if errorlevel 1 (
    echo ERROR: Failed to retrieve logs from pod extendproxy.
    exit /b 1
)
echo ----------------------------------------------
echo Extracting Apikey for Extend Proxy...
echo ----------------------------------------------
set "APIKEY="
for /f "tokens=*" %%L in ('findstr /c:"Apikey for Extend Proxy:" "%TEMP%\extendproxy_logs.txt"') do (
    for /f "tokens=6" %%K in ("%%L") do (
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
echo ----------------------------------------------
kubectl logs -l imaging.service=extendproxy --tail=-1 --namespace %NAMESPACE% | findstr /c:"Admin Access url:"
echo ExtendApiKey: !APIKEY!
echo ----------------------------------------------

if defined BUNDLE_FILE_PATH (
	echo Getting EXTEND-PROXY-URL...
	for /f "usebackq tokens=*" %%i in (`kubectl get deployment extendproxy -n %NAMESPACE% -o jsonpath^="{.spec.template.spec.containers[*].env[?(@.name==\"public_url\")].value}"`) do set EXTEND-PROXY-URL=%%i
    echo ----------------------------------------------
    echo Uploading extend bundle:
    echo - File            : %BUNDLE_FILE_PATH%
	echo - EXTEND-PROXY-URL: !EXTEND-PROXY-URL!
    echo ----------------------------------------------
    curl -H "x-cxproxy-apikey:!APIKEY!" -F "data=@%BUNDLE_FILE_PATH%" !EXTEND-PROXY-URL!/api/synchronization/bundle/upload
)
echo Done.
endlocal