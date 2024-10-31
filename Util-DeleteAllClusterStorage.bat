@echo off
set NAMESPACE=castimaging-v3

echo ABOUT TO DELETE ALL PVCs IN %NAMESPACE%, ARE YOU SURE?
pause
@REM echo PLEASE CONFIRM DELETION.
@REM pause     
REM Retrieve and delete all Persistent Volumes (PVCs)
for /f "tokens=*" %%p in ('kubectl get pvc -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name"') do (
    echo %%p
    kubectl delete pvc -n %NAMESPACE% %%p
    )
)

@REM echo ABOUT TO DELETE ALL PVs IN THE CLUSTER, ARE YOU SURE?
@REM pause
@REM echo PLEASE CONFIRM DELETION.
@REM pause
REM Retrieve and delete all Persistent Volumes (PVs)
for /f "tokens=*" %%p in ('kubectl get pv --no-headers -o "custom-columns=NAME:.metadata.name" ^|findstr "^pvc-"') do (
    echo %%p
    kubectl delete pv %%p
    )
)
echo Done.
