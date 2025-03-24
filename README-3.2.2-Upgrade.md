# CAST Imaging Version Upgrade from 3.1.1 to 3.2.2

## Steps

- Scale down all Imaging pods (Util-ScaleDownAll.bat)
- Update variables in values.yaml to match your current Imaging deployment
- Run Helm Upgrade with the new Helm Chart:
 	```
   	helm upgrade castimaging-v3 --namespace castimaging-v3 .
   	```
- Run Core version upgrade of existing applications (8.4.0 to 8.4.2)
    - Connect to Imaging Console and go to Settings / "Applications" tab
    - Select the applications to be upgraded and start the upgrade
- To analyze an upgraded application, you will have to select "Run a new scan"

