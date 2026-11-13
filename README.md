# Documentation

## Install
https://doc.castsoftware.com/imaging/install/global/kubernetes/

## Update
https://doc.castsoftware.com/imaging/install/update/kubernetes/

## Helm Chart Release Notes

### 3.6.9 (vs 3.6.8)

#### New Features
- **MCP Server 3.1 (`imaging-mcp-server` 3.1.0)**: the `mcp-server` pod now runs the MCP Aggregator Gateway with the Structural, Semantic search and Text2Cypher MCP servers behind it (see https://doc.castsoftware.com/imaging/mcp-server/imaging/3.1/docker/). Requires CAST Imaging ≥ 3.6.8. `McpServer.enable` still defaults to `false` (and is ignored when `Viewer.enable: false`).
- **Analysis-node autoscaling (opt-in, disabled by default)**: adds analysis nodes when queued jobs exceed the free capacity of the running nodes, and removes idle ones afterwards. A node running an analysis is never removed. Requires CAST Imaging 3.6.9 and the OpenKruise operator; enabling it restarts the analysis nodes once. See [Analysis-node autoscaling](docs/analysis-node-autoscaling.md) for requirements, settings, namespace-only and cloud (GKE, AKS, EKS) setups, and troubleshooting.
- **AKS: NFS protocol for the shared volume (`AnalysisNodeFS.AKSprotocol`)** (default `smb`, unchanged behavior): set it to `nfs` so that the Azure Files StorageClass created by the chart (`FileClassName`, when `CreateStorageClass: true`) uses NFS 4.1 instead of SMB for `pvc-shared-datadir` (Premium_LRS, mount options `nconnect=4`, `noresvport`, `actimeo=30`). `AnalysisNodeFS.AKSresourceGroup` / `AKSstorageAccount` are still honored.
  This is **required on FIPS-enabled AKS nodes**: the SMB mount with a storage-account key relies on NTLMSSP (`hmac(md5)`), which the FIPS kernel refuses, so `pvc-shared-datadir` fails to mount with `mount error(2): No such file or directory` (node `dmesg`: `CIFS: VFS: Could not allocate shash TFM 'hmac(md5)'`) and the console-service, console-control-panel and console-analysis-node pods stay in `Init`. Validated on AKS 1.36 with FIPS Ubuntu 22.04 nodes.
  **Encryption in transit** (`AnalysisNodeFS.AKSnfsEncryptInTransit`, default `true`): the NFS traffic is encrypted with TLS by the Azure Files CSI driver (`encryptInTransit: "true"`, AZNFS mount helper with stunnel; works with the FIPS-validated OpenSSL of FIPS nodes), so the storage account can keep **"Secure transfer required" enabled** (Azure Policy "Secure transfer to storage accounts should be enabled"). Set it to `false` only for plain-text NFS, which requires "Secure transfer required" to be disabled on the storage account.
  Azure prerequisites for NFS: a Premium **FileStorage** storage account (created automatically by the Azure Files CSI driver unless `AKSstorageAccount` is set), reachable from the AKS VNet on TCP 2049. Do not mix encrypted and plain-text NFS volumes in the same storage account (the CSI driver reuses existing accounts with the same SKU/protocol): plain-text NFS mounts stop working (`stale file handle`) as soon as "Secure transfer required" is enabled, and AZNFS refuses a TLS mount on a node that already has a plain-text mount to the same storage endpoint. The explicit PV option (`AnalysisNodeFS.AKSsharedDatadirPV.create: true`) remains SMB-only.
  ⚠️ **Migration note**: choose the protocol at initial installation. **Never switch an existing deployment from `smb` to `nfs` once the Imaging instance has been used to run analyses**: StorageClass parameters are immutable, so the change requires deleting the `FileClassName` StorageClass (default `castimaging-fs`) and the `pvc-shared-datadir` volume, which results in **permanent data loss** (delivered source code, deployment folders and shared data used by the analysis nodes, `console-service` and `console-control-panel`).
- **`ServiceAccountName` option** (empty by default): name of an existing ServiceAccount to run all Imaging pods and Jobs with. For example, it can carry its own `imagePullSecrets`.
- **cert-manager for the NGINX Ingress (`CertManager`)** (only used when `CreateIngress: true`, `CertManager.enable: false` by default): when enabled, cert-manager annotations (`cert-manager.io/issuer` or `cert-manager.io/cluster-issuer`, `common-name`, `private-key-size`) are added to the Ingress(es), so that cert-manager requests and renews the TLS certificate(s) (`tls-secret-cast`, and `tls-secret-cast-extend` when ExtendProxy is enabled). Settings: `CertManager.issuer` (default `vault-issuer`), `CertManager.issuerKind` (`Issuer` or `ClusterIssuer`) and `CertManager.privateKeySize` (default `"4096"`). cert-manager and the referenced Issuer/ClusterIssuer must already be installed on the cluster.
- **`IstioExtraHttpRoutes` setting** (default `[]`, only used when `UseIstioGateway: true`): additional Istio HTTP routes, added at the top of `castimaging-virtualservice` (`spec.http`) so that they are evaluated before the chart's own routes. Paths are matched as received by the gateway: when `ContextUrl` is enabled, include the context path.
- **`AnalysisNodeApplicationConfig` setting** (default `{}`): overrides of the analysis-node configuration (`/home/carl/data_aip_node_v3/application.yml`). `application.yml` and `application-default.yml` are regenerated at each container start, so changes made in the pod were lost. Properties set here use the same tree as `application.yml` (e.g. `chunked.upload.stale-activity-timeout-seconds`). They are passed to the node through `SPRING_APPLICATION_JSON` and take precedence over both files and over the configuration served by console-control-panel. Changing a value restarts the analysis nodes on the next `helm upgrade`.
  ⚠️ **Restriction**: properties already set by the chart through the analysis-node environment cannot be overridden here, as `SPRING_APPLICATION_JSON` would silently take precedence over them. `helm install` / `helm upgrade` fails if one of them is set, whatever the key spelling (nested, dotted, camelCase, kebab-case or snake_case):
  - `jobs.threadPoolSize`: use `MaxParallelAnalysisPerNode` instead (also used by the analysis-node autoscaler to compute the capacity of a node).
  - `backup.aipcore.upgrade.enabled`: use `ConsoleEnableBackup` instead.
  - `spring.datasource.hikari.maximum-pool-size`, `spring.datasource.hikari.minimum-idle`: set by the chart, cannot be changed.
  - `database.server.maximumPoolSize`, `database.server.minimumIdle`: derived from the Hikari settings above, cannot be changed.

  Other properties of the same sections are allowed.
  Example, to set `application.maintenance.cron` (Spring cron expression: second, minute, hour, day of month, month, day of week; here every Wednesday at 23:00):
  ```yaml
  AnalysisNodeApplicationConfig:
    application:
      maintenance:
        cron: "0 0 23 * * WED"
  ```

#### Configuration Changes
- **New default `GATEWAYSERVICE.SPRING_CLOUD_GATEWAY_SERVER_WEBFLUX_TRUSTEDPROXIES: ".*"`**: console-gateway-service 3.6.9 is built on Spring Cloud Gateway 5, which no longer forwards `X-Forwarded-*` headers to the backend services unless `trusted-proxies` is set. Without it, console-authentication-service never learns that the original request was `https://` and builds an `http://` OAuth2 login callback URL, so the browser is sent back to `http://` after login. The value is a regex matched against the IP of the client calling console-gateway-service, and can be restricted to your ingress / Istio gateway pod network (e.g. `"10\..*"`).
  ⚠️ **Migration note**: if you use your own `values.yaml`, add this setting under `GATEWAYSERVICE`. If a reverse proxy, load balancer or DMZ sits in front of the Application Networking option, it must also forward the original `X-Forwarded-Proto` / `X-Forwarded-Host` headers.
- **Init Jobs renamed on each change**: `custom-postgres-init-job` and `keycloak-init-job` now get a short hash suffix (e.g. `keycloak-init-job-1a2b3c4d`). The hash changes with the chart version, the values or the Job's script. A Job's pod template is immutable, so `helm upgrade` now creates a new Job and removes the old one, instead of failing to patch it. They also retry up to 3 times (`backoffLimit: 3`, previously 0), as their scripts are idempotent.
- `imagePullSecrets` (when `UseImagePullSecrets: true`) is now also set on the console-postgres StatefulSet and on the init Jobs.
- **`RestrictedSecurityMode`: explicit `runAsUser` / `runAsGroup`**: all pods and containers (including init containers and Jobs) now set the UID/GID of their image explicitly, so that admission policies requiring a non-root numeric user accept them. mcp-server now runs as `1000:1000` (previously UID `33`), and its `fsGroup: 1000` is set whatever the security mode.

#### Fixes
- **Keycloak init Job more robust**: `init-keycloak.sh` now retries the admin token request (up to 60 times, every 5s), as Keycloak can answer while its database is still restarting. The realm admin role is now always (re)assigned to the `KCADMIN_USERNAME` user, even when the user already exists. This repairs a previous run that created the user but failed before assigning the role.
- **Istio `X-Forwarded-*` headers fixed**: the Istio VirtualServices (`UseIstioGateway: true`) now set `X-Forwarded-Host` and `X-Forwarded-Proto` (taken from `FrontEndHost`), as the NGINX Ingress and Gateway API templates already did. Previously only `X-Forwarded-For` was set, so the original `https` scheme never reached the application. Both this fix and the `trusted-proxies` setting above are needed for the login callback URL to use the `FrontEndHost` scheme and host behind Istio.
- **Analysis nodes and databases protected from cluster-autoscaler eviction**: the console-analysis-node, console-postgres and viewer-neo4j pods now carry the `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` and `karpenter.sh/do-not-disrupt: "true"` annotations, so that a cluster autoscaler (Cluster Autoscaler on GKE, AKS, EKS, or Karpenter) never evicts them to remove an under-used worker. The worker hosting them is therefore never removed by the cluster autoscaler.

### 3.6.8 (vs 3.6.7)

#### New Features
- **Configurable network timeouts**: two new `values.yaml` settings control how long a request may take on the network path before being aborted with a Gateway Timeout (504). They apply to whichever Application Networking option is active (Ingress / Istio / Gateway API):
  - `NetworkTimeoutSeconds: 300`: network path to `console-gateway-service` (main application). Increase this if you see timeouts on long-running calls.
  - `ExtendProxy.timeoutSeconds: 3600`: network path to `extendproxy` (bundle uploads can be large/slow, hence the much higher default).

  Istio VirtualServices previously had hardcoded `300s` / `3600s` timeouts; NGINX Ingress now gets `proxy-read-timeout` / `proxy-send-timeout` annotations; Gateway API HTTPRoutes now get `timeouts.request`.
- **Persistent log volumes for console services**: logs of console-control-panel, console-gateway-service, console-authentication-service, console-service, console-sso-service and console-dashboards are now written to dedicated PersistentVolumeClaims (`pvc-controlpanel-logs`, `pvc-gatewayservice-logs`, `pvc-authenticationservice-logs`, `pvc-consoleservice-logs`, `pvc-ssoservice-logs`, `pvc-dashboards-logs`, created with `helm.sh/resource-policy: keep`), so they survive pod restarts. Their sizes are configurable via the new `size_controlpanel_logs`, `size_gatewayservice_logs`, `size_authenticationservice_logs`, `size_consoleservice_logs`, `size_ssoservice_logs` and `size_dashboards_logs` values (default `2Gi` each). Keycloak (sso-service) is configured to log both to the console and to a daily-rotated file (`sso.log`, max 10M per file).
  An `fsGroup` (with `fsGroupChangePolicy: OnRootMismatch`) is now always set on the authentication-service, gateway-service, sso-service and dashboards pods so that they can write to these volumes.
- **`Viewer.enable` option** (default `true`): set it to `false` to skip the deployment of the Viewer components and their related resources: viewer-neo4j, viewer-server, viewer-etl, viewer-api, viewer-aimanager and mcp-server (Services, Deployments/StatefulSet, the `servernginxconf` ConfigMap and the `pvc-imagingviewer-v3-*` PersistentVolumeClaims). When `Viewer.enable: false`, `McpServer.enable` is ignored and the mcp-server is not deployed.
  ⚠️ **Note**: on an existing deployment, switching to `Viewer.enable: false` does not delete the Viewer PersistentVolumeClaims (they are created with `helm.sh/resource-policy: keep`).

#### Security
- **`guest` database user removed**: the embedded Postgres init script no longer creates the `guest` user, and the `guest-db-password` key has been removed from the `imaging-pwd-sec` Secret (`GuestDbPassword` value no longer used). Console services now connect explicitly with the `operator` user (`DB_USER` / `DB_USERNAME`, `DB_DATABASE=postgres`); console-authentication-service additionally receives `DB_ENCRYPTED_PASSWORD` from the `operator-db-password-crypted2` Secret key.
  ⚠️ **Migration note**: `GuestDbPassword` can be removed from your custom `values.yaml`, and the `guest-db-password` key is no longer required in an `existingSecret`. On existing deployments, the `guest` user already present in Postgres is not dropped by the upgrade (it can be removed manually with `DROP USER guest;` if not used elsewhere).

#### Configuration Changes
- **Deployment strategy set to `Recreate`** on console-authentication-service, console-service, console-control-panel, console-gateway-service, console-sso-service, mcp-server, viewer-aimanager, viewer-api, viewer-etl and viewer-server (previously the default `RollingUpdate`).
- Image updates: `init-util` 1.2.12, `imaging-mcp-server` 3.0.4.1, `extend-proxy` 2.3.2, and all CAST Imaging application images 3.6.8.

#### Fixes
- **`RestrictedSecurityMode`**: viewer-server now creates `/run/nginx` at startup and mounts an `emptyDir` on `/var/lib/nginx/tmp`, fixing nginx failures with a read-only root filesystem.

### 3.6.7 (vs 3.6.6)

#### New Features
- **Proxy exclusions auto-update job**: a new `proxy-exclusions-update-script` ConfigMap and a suspended `proxy-exclusions-cronjob` CronJob are shipped with the chart. It can be triggered manually (`kubectl create job proxy-exclusions-cronjob-<id> --from=cronjob/proxy-exclusions-cronjob -n <namespace>`) to refresh `control_panel.settings.non_proxy_hosts` from the subnets of currently registered services, when `proxy_settings_mode` is `MANUAL_PROXY`.
- New `AIMANAGER.SUMMARY_LOG_LEVEL: info` default environment variable.

#### Security
- **`UseCustomTrustStore` removed**: self-signed or otherwise unverifiable certificate on an internal service is no longer a blocking issue. The `UseCustomTrustStore` option and the `auth.caCertificate` value have been removed from `values.yaml`, along with the `authcacrt` ConfigMap and the associated volume mounts in `console-authentication-service`.
  ⚠️ **Migration note**: if your existing `values.yaml` sets `UseCustomTrustStore` / `auth.caCertificate`, you can remove them: they are no longer used by the chart.

#### Fixes
- **NGINX Ingress `X-Forwarded-*` headers fixed**: the Ingress template now always injects `X-Forwarded-Host` / `X-Forwarded-Proto` / `X-Forwarded-Port` (previously only when `ContextUrl.enable: true`, and using the non-standard `X-Forwarded-For` header to carry the hostname). This is required whenever a reverse proxy or DMZ sits in front of the Ingress, so the application builds correct redirects and absolute links.
- **`license-extend-update-script.sql` fixed**: `extend_url` is now only auto-populated when currently empty, so a manually-configured Extend URL is no longer overwritten on every `helm upgrade`. Updating `extend_apikey` no longer depends on `ExtendProxy.enable`.
- `mcp-server` deployment's `fsGroupChangePolicy` changed from `OnRootMismatch` to `Always`, for consistency with the security context used by the other services.

### 3.6.6 (vs 3.6.5)

#### New Features
- **Health probes** added on viewer-api, viewer-etl, viewer-server and viewer-aimanager (startup/liveness/readiness) for better detection of pods stuck at startup.
- **Generic per-service environment variable injection**: new sections in `values.yaml` (`NEO4J`, `ETL`, `SERVER`, `API`, `AIMANAGER`, `MCPSERVER`, `CONTROLPANEL`, `ANALYSISNODE`, `AUTHENTICATIONSERVICE`, `CONSOLESERVICE`, `DASHBOARDS`, `GATEWAYSERVICE`, `SSOSERVICE`, `EXTENDPROXY`) allowing custom environment variables to be added to each container without touching the templates.
- **Backup/restore scripts** (`ImagingBackup`/`ImagingRestore`, .sh and .bat): namespace and backup folder are now required parameters (`<namespace> <backup_dir>`) instead of being hardcoded; backing up the CAST directory (`cast-dir.tar.gz`) is now optional (`BACKUP_CASTDIR=true`); failed log downloads no longer abort the script (warning instead of a hard stop).
- **Postgres LoadBalancer option**: the embedded Postgres (`console-postgres` Service) can now be exposed on its own as a cloud LoadBalancer, independently of the Application Networking option used for the rest of the app, via `CreatePostgresLoadBalancer: true` in `values.yaml` (honors `UseInternalLoadBalancer` for a private/internal LB). This is useful to connect directly to the database with an SQL client for troubleshooting or reporting.
  Once enabled, retrieve the external endpoint with:
  ```
  kubectl get svc console-postgres -n castimaging-v3
  ```
  Connect your SQL tool to the returned `<ip>:<port>` (port `2285` by default).

  ⚠️ **Security recommendation**: when enabling remote access to Postgres this way, it is strongly recommended to also enable SSL for the connection, via `CastStorageService.ssl: true` in `values.yaml`. Additionally, restrict inbound access to this LoadBalancer at the network level (e.g. cloud provider firewall/security group rules) to only the specific IP addresses that need to connect.

#### Security
- The operator's encrypted password (`DB_ENCRYPTED_PASSWORD`) is no longer injected in plain text into the console-controlpanel deployment: it is now stored in the Kubernetes Secret and referenced via `secretKeyRef`.
- ⚠️ **Migration note**: if you use an external `existingSecret`, it must now also contain the `operator-db-password-crypted2` key (base64-encoded value of the `CRYPTED2:...` string), in addition to the previously required keys.

#### Configuration Changes
- Neo4j memory parameters (`NEO4J_server_memory_heap_initial__size`, `NEO4J_server_memory_heap_max__size`, `NEO4J_dbms_memory_transaction_total_max`) have moved from the root of `values.yaml` into the `NEO4J:` section — update your custom values files accordingly.
- `IMAGING_DOMAIN_SYNCHRO_ENABLED` removed from the console-controlpanel deployment (multi-tenant).
- ⚠️ **Audit-trail volume no longer used**: the dedicated `pvc-controlpanel-audit-trails` PersistentVolumeClaim is no longer created or mounted by console-controlpanel. Audit trail data is now stored in the existing shared volume (mounted at `/opt/cast/shared`) instead of its own volume (audit-trail full path remains unchanged: /opt/cast/shared/common-data/audit-trail).
  For customers upgrading from a previous version: the old PVC is **not deleted** by the upgrade (it was created with `helm.sh/resource-policy: keep`) — it simply becomes unmounted/orphaned, and its data (including the `audit-trail` folder) remains intact on the underlying disk. If you want to recover the audit trail history it contained, mount it temporarily with an `init-util` pod and copy the data out:
  This pod definition is compatible with the Restricted Pod Security Standard (i.e. it also works on clusters deployed with `RestrictedSecurityMode: true`):
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: audit-trail-recovery
    namespace: <namespace>
  spec:
    restartPolicy: Never
    securityContext:
      runAsNonRoot: true
      runAsUser: 10001
      fsGroup: 10001
      seccompProfile:
        type: RuntimeDefault
    containers:
      - name: init-util
        image: castimaging/init-util:1.2.11
        command: ["sleep", "3600"]
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        volumeMounts:
          - name: audit-trails
            mountPath: /opt/cast/shared/common-data
    volumes:
      - name: audit-trails
        persistentVolumeClaim:
          claimName: pvc-controlpanel-audit-trails
  ```
  ```
  kubectl apply -f audit-trail-recovery.yaml -n <namespace>
  kubectl cp <namespace>/audit-trail-recovery:/opt/cast/shared/common-data/audit-trail ./audit-trail-backup
  kubectl delete pod audit-trail-recovery -n <namespace>
  ```

#### Fixes
- Fixed NodePort/LoadBalancer activation conditions on the gateway service and extendproxy.

#### Known Issues
- Only applies to Kubernetes deployments: the application export/import feature is not yet functional in this version (it will fail). It will be fully functional in the next release.

