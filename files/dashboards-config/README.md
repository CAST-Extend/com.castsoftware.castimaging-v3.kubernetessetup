# Custom Dashboards configuration files

This folder mirrors the `/app/resources/config/` folder of the Dashboards image (`castimaging/dashboards-v3`,
service `console-dashboards`). It contains the default tile configuration files shipped with the Dashboards
image of this chart version:

| File            | Customizes                                                        |
|-----------------|-------------------------------------------------------------------|
| `hd/cmp.json`     | Management Dashboard, portfolio level (several applications)      |
| `hd/app.json`     | Management Dashboard, application level                           |
| `hd/cmp-ISO.json` | Management Dashboard, portfolio level, ISO-5055 view              |
| `hd/app-ISO.json` | Management Dashboard, application level, ISO-5055 view            |
| `ed/ed.json`      | Engineering Dashboard                                             |
| `sd/ed.json`      | Security Dashboard                                                |

The content of these files is described in the CAST documentation:
https://doc.castsoftware.com/imaging/administer/system-settings/dashboards/tile-customization/
and https://doc.castsoftware.com/imaging/administer/system-settings/dashboards/configuration-options/

## How to customize

1. Edit the file(s) in this folder.
2. In your values file, set:
   ```yaml
   DashboardsCustomConfig:
     enable: true
   ```
3. Run `helm upgrade` (or `helm install`) from the chart folder as usual.

When `enable` is `true`, every file of this folder (except this README) is stored in the `console-dashboards-config`
ConfigMap and mounted over the image file at the same path under `/app/resources/config/`
(e.g. `hd/app.json` -> `/app/resources/config/hd/app.json`). Files of the image that are not in this folder keep
their default content. When a file changes, the next `helm upgrade` restarts the `console-dashboards` pod
automatically. When `enable` is `false` (default), this folder is ignored and the image defaults are used.

Other files of `/app/resources/config/` (e.g. `reports/*.json`) can be customized the same way: add the file
here at the same relative path (e.g. `reports/ISO-5055-Detailed-Report.json`).

## Notes

- Each `.json` file must be valid JSON: `helm install`/`helm upgrade` stops with an error otherwise.
- All files together must stay under 1 MB (ConfigMap size limit).
- To keep the image default for a file, delete it from this folder.
- After the pod restart, clear the browser cache to see the changes.
- When upgrading to a new chart version, merge your changes into the new version of these files: the new
  defaults may contain new settings.
