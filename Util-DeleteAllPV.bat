@echo off
REM Retrieve all Persistent Volumes (PVs) with names starting with "pvc-"
for /f "tokens=*" %%p in ('kubectl get pv --no-headers -o "custom-columns=NAME:.metadata.name"') do (
    echo %%p
    kubectl delete pv %%p
    )
)

echo Done.
