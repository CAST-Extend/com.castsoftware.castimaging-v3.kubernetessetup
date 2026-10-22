# Imaging Backup & Restore Scripts

This document describes what `ImagingBackup.sh/.bat` and `ImagingRestore.sh/.bat` actually do: what is saved, what is restored, how the data is moved, and what the scripts do **not** cover.

The `.sh` (bash) and `.bat` (Windows) versions perform the same steps; differences are listed in [Known limitations](#known-limitations).

---

## 1. Summary

| Data | Where it lives in the cluster | Backed up as | Default |
|---|---|---|---|
| Analysis node **shared directory** | `/opt/cast/shared` (PVC `pvc-shared-datadir`, RWX, mounted by every analysis node, console-service and control-panel) | `shared-dir.tar.gz` | Always |
| Analysis node **CAST directory** (one per pod) | `/usr/share/CAST` (per-pod volume of `console-analysis-node-core-N`) | `<pod-name>-cast-dir.tar.gz` | Off (`BACKUP_CASTDIR=false`) |
| **PostgreSQL** (embedded `console-postgres`) | PVC `db-data`: databases `postgres` (Console / Control Panel schemas) and `keycloak`, plus roles `operator` / `keycloak` | `all_databases.backup` (plain SQL from `pg_dumpall`) | On (`BACKUP_POSTGRES=true`) |
| **Neo4j** (`viewer-neo4j-core-0`) | `/var/lib/neo4j/config/neo4j5_data` | `backup/neo4j.tar` (one `neo4j-admin` backup file per database) | Always |

**Not backed up** (see [section 5](#5-what-is-not-backed-up)): Helm values, Kubernetes secrets and other objects, external PostgreSQL instances, the Extend Proxy data volume, and log volumes.

---

## 2. Usage

```
ImagingBackup.bat  <namespace> <backup_dir>
ImagingRestore.bat <namespace> <backup_dir>

./ImagingBackup.sh  <namespace> <backup_dir>
./ImagingRestore.sh <namespace> <backup_dir>
```

Both arguments are mandatory. The scripts must be run from a machine where `kubectl` (or `oc`) is installed and connected to the target cluster.

### Configuration variables (edit at the top of each script)

| Variable | Default | Effect |
|---|---|---|
| `BACKUP_CASTDIR` | `false` | `true` also backs up / restores `/usr/share/CAST` of **each** analysis node pod. |
| `BACKUP_POSTGRES` | `true` | `false` skips the PostgreSQL step entirely (e.g. when an external PostgreSQL instance is used). The same variable name is used in the restore scripts. |
| `OPENSHIFT_CHECK` | `n` | `y` switches to `oc` and the OpenShift PostgreSQL data path `/var/lib/pgsql/data` (instead of `/var/lib/postgresql/data`). See known limitations for the `.bat` versions. |
| `CHUNK_MB` (backup only) | `256` | Size of the chunks used to download large files. |
| `KUBECTL_REMOTE_COMMAND_WEBSOCKETS` | `false` | Forces kubectl to use SPDY instead of WebSockets for `exec` (kubectl 1.30+ WebSocket streams break large transfers). |

---

## 3. Backup — what happens, step by step

The backup is **online**: it does not stop any service. The script asks for confirmation that the instance is quiet (no analysis running, no activity in Console) and relies on the operator to keep it that way for the whole run.

### Step 1 — Analysis node files

1. Lists the pods named `console-analysis-node-core-*`. **If none is running, the script stops with an error** (e.g. when analysis node autoscaling has scaled the node down to 0).
2. On the **first** pod found (not necessarily `-0`), creates `shared-dir.tar.gz` **inside the shared volume** itself:
   `tar -czpf /opt/cast/shared/shared-dir.tar.gz /opt/cast/shared/*` (excluding the archive itself and `lost+found`).
3. Downloads the archive to `<backup_dir>/shared-dir.tar.gz`, then deletes it from the pod.
4. If `BACKUP_CASTDIR=true`, repeats the same for `/usr/share/CAST` on **every** analysis node pod, producing `<pod-name>-cast-dir.tar.gz`.

### Step 2 — PostgreSQL (skipped if `BACKUP_POSTGRES=false`)

1. Finds the `console-postgres` pod. If none is found, prints a warning and **continues without a PostgreSQL backup**.
2. Runs, inside the pod:
   `pg_dumpall -v -U operator -f <PG_DATA_PATH>/backup/all_databases.backup`
   This produces a plain SQL script containing **all roles (with their password hashes), all databases, schemas and data**. Each database is dumped consistently, but the databases are not dumped at the same instant.
3. Downloads `all_databases.backup` and `postgres_backup.log`, then deletes the temporary directory from the pod.

A `pg_dumpall` failure stops the script (non-zero exit code).

### Step 3 — Neo4j

1. In `viewer-neo4j-core-0`, empties `/var/lib/neo4j/config/neo4j5_data/backup`.
2. Runs an online backup of **all databases** (including `system`):
   `neo4j-admin database backup --compress=true --include-metadata=all --pagecache=4G --from=localhost:6362 '*'`
   Output goes to `/var/lib/neo4j/logs/backup_ImagingDatabases.log`. A failure stops the script.
3. Runs `--inspect-path` on the result (informational only, not checked).
4. Packs the backup directory into `neo4j.tar` (uncompressed tar; each database file is already compressed), downloads it to `<backup_dir>/backup/neo4j.tar`, together with the backup log, then deletes the temporary files from the pod.

### Resulting backup folder

```
<backup_dir>/
├── shared-dir.tar.gz              Analysis node shared directory
├── <pod>-cast-dir.tar.gz          Only if BACKUP_CASTDIR=true (one per pod)
├── all_databases.backup           Only if BACKUP_POSTGRES=true
├── postgres_backup.log            Only if BACKUP_POSTGRES=true
├── backup_ImagingDatabases.log    Neo4j backup log
└── backup/
    └── neo4j.tar                  <db>-YYYY-MM-DDTHH-MM-SS.backup files, one per Neo4j database
```

---

## 4. Restore — what happens, step by step

**Prerequisite:** a freshly installed, empty Imaging instance, deployed with the Helm chart version that matches the backup, running in a namespace with the **same name** as the source. The script asks the operator to type `YES` before doing anything.

### Step 1 — Analysis node files

1. Detects whether the analysis node is a standard StatefulSet or an OpenKruise StatefulSet (analysis node autoscaling enabled).
2. If the analysis node is at 0 replicas, scales it to 1 and waits up to 10 minutes for it to be ready.
3. Through the first analysis node pod, uploads `shared-dir.tar.gz` and extracts it into `/opt/cast/shared`. Existing files are **overwritten, not removed first** (the target is expected to be empty). An extraction error is only a **warning**. A missing `shared-dir.tar.gz` is also only a warning.
4. If `BACKUP_CASTDIR=true`, restores `<pod-name>-cast-dir.tar.gz` into `/usr/share/CAST` of each pod. The archive is matched by **pod name**, so the target must have the same pods as the source; a missing archive stops the script.

The application services are still running during this step.

### Step 2 — Stop services, then PostgreSQL

1. Scales to 0 replicas: the analysis node autoscaler (if present), `console-dashboards`, the analysis node, `console-service`, `console-authentication-service`, `console-gateway-service`, `console-control-panel`, `console-sso-service`, `viewer-aimanager`, `viewer-api`, `viewer-etl`, `viewer-server`, `extendproxy`, `mcp-server`. Only `console-postgres` and `viewer-neo4j-core` keep running. Waits 10 seconds.
2. If `BACKUP_POSTGRES=true` and the `console-postgres` pod is found:
   1. Uploads `all_databases.backup` to the pod.
   2. Drops the objects created by the fresh install: `DROP SCHEMA control_panel CASCADE` (and, in the `.bat` version only, `DROP DATABASE keycloak`).
   3. Replays the dump with `psql -U postgres -f all_databases.backup`, output to `postgres_restore.log`.
   4. Runs `ANALYZE` on the `keycloak` and `postgres` databases.
   5. Downloads `postgres_restore.log` and deletes the temporary files from the pod.

> **Important:** `psql` is run without `ON_ERROR_STOP`, so individual SQL errors do **not** stop the script and the step reports "Postgres restore done." even if statements failed. Always check `postgres_restore.log` for `ERROR:` lines. Errors like `role "operator" already exists` are expected (the roles exist on the fresh instance); others are not.
>
> The dump also contains `ALTER ROLE ... PASSWORD` statements: after the restore, the `operator` and `keycloak` database passwords are those of the **source** instance. The target instance must therefore be installed with the same database credentials as the source.

### Step 3 — Neo4j

1. Uploads `neo4j.tar` to `viewer-neo4j-core-0` and extracts it to `/var/lib/neo4j/config/neo4j5_data/backup`.
2. Builds the list of databases from the backup file names, **excluding `system`** (the target's own `system` database is kept).
3. Generates and runs two Cypher scripts against the `system` database (user `neo4j`, password `imaging`):
   - for each database: `DROP DATABASE IF EXISTS`, `CREATE DATABASE`, `STOP DATABASE`;
   - after the restore: `START DATABASE` for each, then `SHOW DATABASES`.
4. For each database: `neo4j-admin database restore --overwrite-destination=true --from-path=... --source-database=<db> <db>`. A failure stops the script and downloads `neo4j_restore.log`.
5. Starts the databases, then runs the `restore_metadata.cypher` script written by the restore for each database (`neo4j5_data/scripts/<db>/`), which re-applies users, roles and privileges stored in the backup (`--include-metadata=all`). Failures of this step are only logged, not checked.
6. Downloads `neo4j_restore.log`, cleans up the temporary files, and **scales `viewer-neo4j-core` to 0**, waiting until it is stopped.

### Final step — restart (manual)

At the end, **all Imaging services are stopped**, including Neo4j and the analysis node autoscaler. They must be restarted manually, either with:

- `Util-ScaleUpAll.sh` / `Util-ScaleUpAll.bat` (also restarts the analysis node autoscaler if present), or
- `helm upgrade <release> --namespace <namespace> .` from the chart folder.

Then check `postgres_restore.log` and `neo4j_restore.log`, and verify the instance in Console.

---

## 5. What is not backed up

| Not covered | Notes |
|---|---|
| Helm chart, values file(s), Kubernetes secrets, ConfigMaps, Ingress/Gateway objects | Keep the chart version and the values file(s) used for the install; they are needed to re-create an empty instance for the restore. |
| External PostgreSQL instance | When `console-postgres` is not used, back the external instance up with the customer's own tools and set `BACKUP_POSTGRES=false`. |
| Extend Proxy data (`pvc-extendproxy-data`) | Not part of the scripts. |
| Log volumes (`pvc-*-logs`, Neo4j logs), ETL CSV archive (`pvc-imagingviewer-v3-etl-csvarchive`) | Not part of the scripts. |
| `/usr/share/CAST` on analysis nodes | Only when `BACKUP_CASTDIR=true`. |
| Neo4j `system` database | Backed up, but deliberately **not restored**; database users and privileges are re-applied from the per-database metadata instead. |

---

## 6. How large files are transferred

A single long `kubectl exec` / `kubectl cp` stream can be cut short without kubectl reporting an error, which would silently produce a truncated backup. The scripts therefore check every transfer:

- **Download (backup):** the file size is read in the pod with `stat`. The file is then downloaded in `CHUNK_MB` (256 MB) chunks with `dd ... skip=N count=CHUNK_MB`. Each chunk's size is compared with the expected size and retried up to 5 times; the reassembled file must match the original size exactly. A trailing `sleep 5` in each `exec` keeps the stream open so in-flight data is not dropped.
- **Upload (restore):** the file is streamed with `kubectl exec -i ... cat > <file>`, then its size in the pod is compared with the local size; retried up to 3 times.

Size checks detect truncation, not corruption; there is no checksum.

### Disk space needed

| Location | Temporary space needed |
|---|---|
| Shared volume (`pvc-shared-datadir`) | Size of `shared-dir.tar.gz` (created inside the volume being backed up) |
| PostgreSQL volume (`db-data`) | Size of the SQL dump |
| Neo4j volume | Size of the Neo4j backup files **twice** (backup files + `neo4j.tar`) |
| Local machine | Total size of the backup folder |

---

## 7. Logs and error handling

| Log file (in `<backup_dir>`) | Produced by | Content |
|---|---|---|
| `postgres_backup.log` | Backup | `pg_dumpall -v` output |
| `backup_ImagingDatabases.log` | Backup | `neo4j-admin database backup` output |
| `postgres_restore.log` | Restore | `psql` output; **must be checked for `ERROR:`** |
| `neo4j_restore.log` | Restore | `neo4j-admin database restore` output and metadata script output |

| Situation | Behaviour |
|---|---|
| Missing arguments, no analysis node pod, archive creation/transfer failure, `pg_dumpall` failure, Neo4j backup/restore failure | Script stops with `ERROR` |
| PostgreSQL pod not found | Warning, PostgreSQL step skipped, script continues |
| `shared-dir.tar.gz` missing or its extraction fails at restore | Warning only |
| SQL errors during the PostgreSQL restore | **Not detected**; check `postgres_restore.log` |
| Neo4j metadata (permission) scripts fail | **Not detected**; check `neo4j_restore.log` |
| Log download fails | Warning only |

---

## Known limitations

- **No consistency across components.** The shared directory, PostgreSQL and Neo4j are backed up one after the other, while services keep running. The instance must be kept quiet (no analysis, no Console activity) for the whole backup.
- **Analysis node must be running for the backup.** With analysis node autoscaling, scale it up before running the backup script.
- **PostgreSQL restore errors are not detected** (see section 4).
- **`.sh` and `.bat` restore differ:** only the `.bat` drops the `keycloak` database before replaying the dump. With the `.sh` version, the Keycloak objects created by the fresh install remain and the corresponding statements of the dump fail (visible in `postgres_restore.log`).
- **OpenShift in the `.bat` scripts:** `OPENSHIFT_CHECK` is set with quotes (`set OPENSHIFT_CHECK="n"`), so it must be changed to `set OPENSHIFT_CHECK=y` (without quotes) to take effect. In `ImagingRestore.bat`, the OpenShift branch does not actually switch `CLUSTER_CMD` to `oc`, and the PostgreSQL step always resets the data path to `/var/lib/postgresql/data`. Use the `.sh` scripts on OpenShift.
- **Neo4j credentials are hard-coded** in the restore scripts (`neo4j` / `imaging`).
- **Same namespace required.** The restore must target a namespace with the same name as the source instance.
