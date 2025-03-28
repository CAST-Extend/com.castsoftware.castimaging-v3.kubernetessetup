# CAST Imaging Version Upgrade from 3.1.1 to 3.2.2

## Steps

- Scale down all Imaging pods (Util-ScaleDownAll.bat)
- Update variables defined in values.yaml to match your current Imaging deployment
- Run Helm Upgrade:
 	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 .
   	```
- Use Console to upgrade applications from Core version 8.4.0 to 8.4.2
    - Connect to Imaging Console and go to Settings / "Applications" tab
    - Select the applications to be upgraded and start the upgrade
- To reanalyze an upgraded application, it is required to use the "Run a new scan" option
