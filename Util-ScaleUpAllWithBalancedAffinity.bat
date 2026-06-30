@echo off
setlocal enabledelayedexpansion

set NAMESPACE=castimaging-v3
set NUMBER_OF_ANALYSIS_NODES=1
set TIMEOUT=900s

echo Scaling up namespace %NAMESPACE%...
echo.

REM ----- Analysis nodes (scale now, wait later so other things start in parallel) -----

call :scale statefulset console-analysis-node-core %NUMBER_OF_ANALYSIS_NODES%

REM ----- Core data stores -----

call :scale statefulset console-postgres 1
call :wait_ready statefulset console-postgres

call :scale statefulset viewer-neo4j-core 1
call :wait_ready statefulset viewer-neo4j-core

REM ----- Console services -----

call :scale deployment console-sso-service 1
call :wait_ready deployment console-sso-service

call :scale deployment console-control-panel 1
call :scale deployment console-gateway-service 1
call :scale deployment console-authentication-service 1
call :scale deployment console-service 1
call :scale deployment console-dashboards 1
call :scale deployment extendproxy 1

REM ----- Now block until the analysis nodes are actually Ready -----

call :wait_ready statefulset console-analysis-node-core

REM ----- Viewer services -----

call :scale deployment viewer-server 1
call :scale deployment viewer-etl 1
call :scale deployment viewer-aimanager 1
call :scale deployment viewer-api 1
call :scale deployment mcp-server 1

echo.
echo Scale-up complete.
exit /b 0

REM ============================================================
REM  Subroutines
REM ============================================================

:scale
REM  %1 = kind (statefulset/deployment)  %2 = name  %3 = replicas
echo Scaling %1/%2 to %3 replica(s)...
kubectl scale %1 %2 --replicas=%3 -n %NAMESPACE%
if errorlevel 1 (
    echo ERROR: failed to scale %1/%2
    exit /b 1
)
exit /b 0

:wait_ready
REM  %1 = kind  %2 = name
echo Waiting for %1/%2 to roll out...
kubectl rollout status %1/%2 --timeout=%TIMEOUT% -n %NAMESPACE%
if errorlevel 1 (
    echo ERROR: %1/%2 did not become ready within %TIMEOUT%
    exit /b 1
)
echo %1/%2 is ready.
echo.
exit /b 0