@echo off
set NAMESPACE=castimaging-v3

echo ABOUT TO DELETE ALL PVCs IN %NAMESPACE%, ARE YOU SURE?
pause
echo PLEASE CONFIRM DELETION.
pause     
REM Retrieve and delete all Persistent Volumes (PVCs)
for /f "tokens=*" %%p in ('kubectl get pvc -n %NAMESPACE% --no-headers -o "custom-columns=NAME:.metadata.name"') do (
    echo %%p
    kubectl delete pvc -n %NAMESPACE% %%p
    )
)

echo ABOUT TO DELETE ALL PVs IN THE CLUSTER, ARE YOU SURE?
pause
echo PLEASE CONFIRM DELETION.
pause
REM Retrieve and delete all Persistent Volumes (PVs)
for /f "tokens=*" %%p in ('kubectl get pv --no-headers -o "custom-columns=NAME:.metadata.name" ^|findstr "^pvc-"') do (
    echo %%p
    kubectl delete pv -n %NAMESPACE% %%p
    )
)
echo Done.
