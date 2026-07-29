# Documentation

## Install
https://doc.castsoftware.com/imaging/install/global/kubernetes/

## Update
https://doc.castsoftware.com/imaging/install/update/kubernetes/

## Helm Chart Release Notes

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

