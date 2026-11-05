# Analysis-node autoscaling

Adds analysis nodes when the job queue holds work that no running node can take,
and removes them again once they go idle.

The part that matters: it chooses **which** node to remove. A node running an
analysis is never the one that goes.

Disabled by default. Nothing below applies unless you turn it on.

---

## 1. Requirements

| | |
|---|---|
| **CAST Imaging 3.6.9 or later** | Earlier versions dispatch jobs straight to a node, so the queue is always empty and the autoscaler would never scale up. See §9. |
| **OpenKruise operator installed in the cluster** | An infrastructure prerequisite, like Keycloak or Neo4j. The chart does **not** install it. https://openkruise.io |
| **One schedulable worker per analysis node** | Anti-affinity gives each analysis node its own worker, and one worker is reserved for Neo4j. So the practical ceiling is `schedulable workers - 1`. |

If you only have rights on your own namespace, read §2 before anything else.
If your cluster adds and removes workers on its own (GKE, AKS, EKS node pool
autoscaling), read §3.

### Why OpenKruise is needed

A standard Kubernetes StatefulSet always deletes the **highest-numbered** pod
when you scale down. That pod may be the one running an analysis.

```
core-0  idle
core-1  idle
core-2  running an analysis   <-- a standard StatefulSet deletes THIS one
```

OpenKruise's Advanced StatefulSet adds `reserveOrdinals`, which is the only way
to say "remove *that* specific pod". Without it, safe scale-down is not
possible, so the feature requires it.

---

## 2. Without cluster-admin rights

Many installations run with rights on **one namespace only**. The autoscaler
works there, but with the default settings the upgrade **fails as a whole** —
not just the autoscaler — so a few steps are needed.

### What a cluster administrator must do, once

These cannot be done from inside a namespace.

1. **Install OpenKruise.** It adds cluster-wide resource types (CRDs), a
   controller and admission webhooks. Without it, the upgrade fails with
   `no matches for kind "StatefulSet" in version "apps.kruise.io/v1beta1"`.

2. **Make sure you can manage OpenKruise StatefulSets and Roles in your
   namespace.** With autoscaling enabled, the chart:

   * creates the analysis-node StatefulSet as an OpenKruise resource;
   * creates a Role and RoleBinding that let the autoscaler read and resize
     it. Kubernetes only lets you create a Role granting rights you hold
     yourself, so you need the OpenKruise rights first.

   The official OpenKruise Helm chart adds its rights to the built-in `admin`
   and `edit` roles. So if your namespace access is a RoleBinding to the
   built-in **`admin`** role, nothing more is needed. **`edit` is not enough**:
   it cannot create Roles or RoleBindings. A custom Role listing resources one
   by one does not receive the OpenKruise rights either.

   Check — **all five** must answer `yes`:

   ```bash
   kubectl auth can-i create statefulsets.apps.kruise.io -n <namespace>
   kubectl auth can-i patch  statefulsets.apps.kruise.io -n <namespace>
   kubectl auth can-i delete statefulsets.apps.kruise.io -n <namespace>
   kubectl auth can-i create roles.rbac.authorization.k8s.io -n <namespace>
   kubectl auth can-i create rolebindings.rbac.authorization.k8s.io -n <namespace>
   ```

   If one of the last two answers `no`, ask the administrator to bind you to
   the built-in `admin` role in your namespace:

   ```bash
   kubectl create rolebinding <your-user>-admin -n <namespace> \
     --clusterrole=admin --user=<your-user>
   ```

   If only the OpenKruise checks answer `no` (OpenKruise installed another
   way, or a custom role), the administrator can apply:

   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: castimaging-kruise-statefulsets
     namespace: <namespace>
   rules:
     - apiGroups: ["apps.kruise.io"]
       resources: ["statefulsets"]
       verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: castimaging-kruise-statefulsets
     namespace: <namespace>
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: Role
     name: castimaging-kruise-statefulsets
   subjects:
     - kind: User            # or Group / ServiceAccount, whoever runs helm
       name: <your-user>
   ```

### What you set in `values.yaml`

```yaml
AnalysisNodeAutoscaling:
  enabled: true
  allowNodeRead: false   # required without cluster-admin rights
  minNodes: 1
  maxNodes: 2            # set by hand - see below
```

* **`allowNodeRead: false` is mandatory.** With `true` (the default), the chart
  creates a ClusterRole and ClusterRoleBinding to read the cluster's nodes.
  Those are cluster-wide objects; creating them is refused, and the whole
  upgrade fails with `forbidden`.
* **`maxNodes` is then the only ceiling, so size it yourself.** The automatic
  `workers - 1` cap needs the node read you just turned off. Set `maxNodes` to
  the number of workers the analysis nodes can use, minus the one Neo4j needs.
  Ask your cluster administrator for that number.

### If `maxNodes` is set too high

The extra analysis nodes have no worker to run on, or not enough free CPU or
memory, and stay `Pending`. The autoscaler first waits for them to start,
logging `holding: X/Y ready, last change has not settled`. After
`stuckPodTimeoutSeconds` (10 minutes by default) it gives up on them: it
removes them (`N pod(s) never became ready: ...`) and keeps the fleet at the
size that did start for another `stuckPodTimeoutSeconds`
(`ceiling pinned at N`), so it does not ask for them again straight away.
A stuck pod needed to reach `minNodes` is kept.

If this keeps happening, lower `maxNodes`. To clear `Pending` pods by hand
without waiting, list them, note their numbers (the suffix after `core-`),
and reserve those numbers while lowering `replicas` by the same count:

```bash
kubectl get pods -n <namespace> -l imaging.service=console-analysis-node
# e.g. core-3 and core-4 are Pending, replicas is 5, reserveOrdinals is [1]:
kubectl patch statefulsets.apps.kruise.io console-analysis-node-core -n <namespace> \
  --type merge -p '{"spec":{"replicas":3,"reserveOrdinals":[1,3,4]}}'
```

Keep every number already in `reserveOrdinals` — removing one brings that pod
back.

---

## 3. Clusters with node autoscaling (GKE, AKS, EKS)

Two autoscalers then work side by side, each on its own layer:

* the **CAST autoscaler** changes the number of analysis-node **pods**, from
  the job queue;
* the **cluster autoscaler** of your cloud changes the number of **workers**:
  it adds one when a pod is `Pending` for lack of room, and removes one that
  has been under-used for a while (about 10 minutes by default).

They cooperate only through `Pending` pods. That has one important consequence.

### Set `allowNodeRead: false`

With `allowNodeRead: true`, the CAST autoscaler caps the fleet at
`schedulable workers - 1`, counting only the workers that **exist now**. It
therefore never asks for a pod the current workers cannot hold, so no pod is
ever `Pending`, so the cluster autoscaler never adds a worker. The fleet stays
at its current size and the log shows `at the ceiling (N); M job(s) must wait`.

With `allowNodeRead: false`:

1. jobs queue up, the CAST autoscaler raises the replica count;
2. the new analysis-node pods are `Pending` — anti-affinity gives each its own
   worker;
3. the cluster autoscaler adds workers and the pods start.

The same setting is also needed with a **dedicated, tainted node pool**
(`EnforceNodeAffinity: true`): workers carrying a `NoSchedule` taint are not
counted, so the automatic cap would be computed from the other pools only and
come out too low.

### Size `maxNodes` from the node pool

Set `maxNodes` to **the node pool's maximum size, minus the worker Neo4j uses**
if it runs in the same pool. If `maxNodes` is above what the pool can grow to,
the extra pods stay `Pending` until `stuckPodTimeoutSeconds`, then are removed
— see "If `maxNodes` is set too high" in §2. Keep `stuckPodTimeoutSeconds`
above the time your cloud needs to add a worker and pull the image.

### Expect a slower scale-up

Adding an analysis node now also means adding a worker:

| Step | Typical time |
|---|---|
| `scaleUpStabilizationSeconds` | 60 s |
| Cloud provider creates and joins a worker | 2–5 min |
| New worker pulls the analysis-node image | 1–several min |

During that time the CAST autoscaler waits for the new pods
(`holding: X/Y ready`) and does not stack further changes. This is expected.

### Scale-down

The CAST autoscaler removes an idle analysis-node pod. The worker it ran on is
then removed by the cluster autoscaler after its own delay, **if** every other
pod on that worker can move elsewhere. Workers also hosting Neo4j or PostgreSQL
stay: these pods carry the same annotations as the analysis nodes (see below).
Workers hosting other pods with local storage normally stay too.

### Running analyses and the cluster autoscaler

To free an under-used worker, a cluster autoscaler may move the pods running on
it, which would stop a running analysis. To prevent this, the analysis-node
pods always carry the annotations
`cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` (Cluster Autoscaler,
including GKE, AKS and EKS) and `karpenter.sh/do-not-disrupt: "true"`
(Karpenter). A worker running an analysis-node pod is therefore not removed by
the cluster autoscaler; it becomes removable once the CAST autoscaler has
removed that pod. This works whatever the cluster autoscaler's
`skip-nodes-with-local-storage` setting.

Consequence: the workers hosting the `minNodes` analysis nodes that are always
kept are never removed by the cluster autoscaler.

### Zones and volumes

Each analysis node keeps a 100 GB `castdir` volume. On most clouds this is a
**zonal** disk (GCE Persistent Disk, Azure Disk LRS, EBS): it can only be
attached in the zone where it was created.

When the CAST autoscaler brings back a node number that was removed earlier,
that pod must run in its volume's zone. If the node pool spans several zones,
the cluster autoscaler may add the worker in another zone, and the pod stays
`Pending`. Use one of:

* a node pool in a **single zone**;
* a **zone-redundant** storage class for `castdir` (Azure ZRS, GKE regional
  Persistent Disk);
* one node pool per zone, with the cluster autoscaler balancing similar node
  groups.

### Recommended settings

| Setting | Value |
|---|---|
| `allowNodeRead` | `false` |
| `maxNodes` | node pool maximum − 1 (Neo4j), or lower |
| `castdir` storage | single zone, or zone-redundant storage class |

---

## 4. Before you enable it

**Enabling replaces the analysis-node StatefulSet and restarts the analysis
nodes once.** The resource changes kind (`apps/v1` →
`apps.kruise.io/v1beta1`), which Helm cannot do in place.

* Do it when **no analysis is running**. A running analysis will be lost.
* The 100 GB `castdir` volumes are **kept** — only the pods restart.
* Plan it as a maintenance-window change, like any other StatefulSet migration.

The same applies when you disable it again.

---

## 5. Enabling

Install OpenKruise first, then in your `values.yaml`:

```yaml
AnalysisNodeAutoscaling:
  enabled: true
  minNodes: 1
  maxNodes: 3
```

and upgrade as usual.

> **`AnalysisNodeReplicaCount` is ignored while autoscaling is enabled.** The
> controller owns the replica count, so the chart stops setting it — otherwise
> every upgrade would reset your fleet. The StatefulSet therefore starts at
> **one** node, and the controller brings it up to `minNodes`, then adds more
> as the queue requires.

> **Keep `minNodes` at 1 or more. Never set it to 0.** The autoscaler only scales
> up when jobs are queued, and jobs can only be queued from the console while
> at least one analysis node is available. With `minNodes: 0`, an idle fleet
> shrinks to zero nodes. The console then greys out the analysis actions,
> because no node is available, so no job can be launched, the queue stays
> empty, and the autoscaler never scales back up to 1. To recover, set
> `minNodes` back to 1 and upgrade. The controller then brings the fleet back
> up to one node even with an empty queue.

---

## 6. Settings

| Setting | Default | What it does |
|---|---|---|
| `enabled` | `false` | Turns the feature on. Also switches the StatefulSet kind — see §4. |
| `minNodes` | `1` | Never scales below this, even when the whole fleet is idle. A fleet below it is brought back up, even with an empty queue. **Must be at least 1**: at 0 the console cannot launch analyses, so the fleet never scales back up (see §5). |
| `maxNodes` | `3` | Never scales above this. Also capped at `schedulable workers - 1` when `allowNodeRead` is `true`. A fleet above it is brought back down, one idle node at a time. |
| `pollIntervalSeconds` | `30` | How often the queue is read. |
| `scaleUpStabilizationSeconds` | `60` | How long "we need more nodes" must hold before acting. |
| `scaleDownStabilizationSeconds` | `120` | How long "this node is spare" must hold before removing it. |
| `stuckPodTimeoutSeconds` | `600` | An analysis-node pod not Ready for this long is removed, and the fleet is held at the size that started for as long again. `0` disables it. |
| `dryRun` | `false` | Decide and log, but never change anything. Useful for a first look. |
| `allowNodeRead` | `true` | Grants a cluster-scoped **read** of nodes, used only to cap `maxNodes` at `workers - 1`. Set `false` without cluster-admin rights (§2), with node autoscaling (§3), or with a tainted dedicated node pool; the controller then logs one warning and uses `maxNodes` alone. |

### Choosing the stabilisation windows

They are deliberately asymmetric. Being slow to **add** capacity leaves work
waiting; being slow to **remove** a node only wastes a little idle compute. So
removal is the cautious one.

Bringing a removed node back costs about **40 seconds** when that host already
has the analysis-node image, and several minutes when it does not. Setting
`scaleDownStabilizationSeconds` far above a minute or two buys little.

Do not go below about 90 seconds: a single reading can catch a node in the gap
between two jobs of the same application and make it look idle when it is not.

---

## 7. Checking that it works

```bash
kubectl logs -n <namespace> -l imaging.service=console-analysis-node-autoscaler -f
```

Every poll logs what it saw, what it decided, and **why**:

```
state: kind=apps.kruise.io replicas=1 ready=1 reserved=[] newNodeCapacity=2 (helm) untainted=4
queue: queued=2 nodes=[0:2/2]
decision: scale-up -> replicas=2 reserve=[]
  reason: 2 job(s) beyond 0 spare thread(s) -> +1 node(s)
  holding: decision is new, need 60s of agreement
```

then, once the decision has held long enough:

```
  applying: {"spec": {"replicas": 2, "reserveOrdinals": []}}
```

`newNodeCapacity` is `MaxParallelAnalysisPerNode` as set in Helm: it is only
used to size a scale-up (how many nodes to add). The `queue:` line shows, per
node, `ordinal:jobsInProgress/capacity` as reported by the console - that
capacity is the one set in the Imaging UI, and it is what spare threads and
scale-down are computed from. The two differ when the UI value was changed.

A node whose capacity was changed in the UI keeps that value when its ordinal
is brought back; only a never-used ordinal starts with
`MaxParallelAnalysisPerNode`. The autoscaler therefore records, in the
`imaging.castsoftware.com/ordinal-capacity` annotation of the analysis-node
StatefulSet, the capacity of every ordinal that differs from Helm's, and uses
it to size a scale-up: reserved ordinals are reused largest capacity first. The
UI cannot edit a node that is not running, so the value recorded when a node
was reserved is the one it restarts with. The capacities held for reserved
ordinals appear at the end of the `queue:` line as
`reservedCapacity=[ordinal:capacity ...]`.

`reserveOrdinals` is the list of node numbers that are **not** running. On
scale-down it is how a specific node is removed, and it accumulates — an entry
is only released when that node is brought back.

---

## 8. Why is it not scaling?

Every line below is a normal, deliberate behaviour, not a fault.

| Log line | Meaning |
|---|---|
| `nothing removable: N idle node(s), M queued job(s) need the K spare thread(s)` | Removing a node would leave too little room for work already waiting. |
| `holding: X/Y ready, last change has not settled` | A previous change is still in progress. It never stacks changes. If it lasts, some pods are `Pending` — see §2 and §3. |
| `not ready: core-K (Unschedulable) for 120s of 600s before it counts as stuck` | The pod is being watched. The clock restarts if the autoscaler pod restarts. |
| `N pod(s) never became ready: core-K (Unschedulable, not ready for 600s)` | A pod did not start within `stuckPodTimeoutSeconds`. It is removed, whatever the queue. |
| `ceiling pinned at N for 600s` / `ceiling of N lifted` | After removing a stuck pod, the fleet is not grown above what did start, for one more timeout. |
| `holding: Ready but not yet in the endpoint ... registry is mid-update` | A new node has started but has not registered yet. Acting now would misread the fleet as smaller than it is. |
| `holding: 30s of 120s agreement` | The decision is right but has not held long enough yet. |
| `at the ceiling (N); M job(s) must wait` | `maxNodes`, or `workers - 1`, has been reached. With node autoscaling, see §3. |
| `below minNodes (X < N) -> +K node(s)` | The fleet is under `minNodes` and is being brought back up. |
| `above maxNodes (X > N) but no idle node to remove` | The fleet is over `maxNodes`; it shrinks as soon as a node finishes its work. |
| `queue-status unreachable ... doing nothing this tick` | The console could not be reached. It never acts on missing data. |
| `aborting scale-down: the fleet changed between deciding and acting` | A node picked up work in the final seconds. The removal is cancelled. |
| `cannot list nodes (RBAC) - the anti-affinity ceiling is disabled` | `allowNodeRead: false`. Expected; `maxNodes` still applies. |
| `NB_OF_THREADS_FOR_NODE is not set ... refusing to guess` | The pod template has no thread count. It will not assume one, because a wrong value would halve or double the fleet. |
| `refusing to scale down a native StatefulSet` | The StatefulSet is not the OpenKruise kind. Check that OpenKruise is installed and the upgrade applied. |

**If nothing is queued, nothing will happen.** The autoscaler reacts to queue
depth, not to CPU or memory. An idle fleet simply shrinks to `minNodes`.

---

## 9. Limits worth knowing

* **It reacts to the queue, not to prediction.** A new node takes time to start,
  so a short burst may finish before extra capacity arrives. This is deliberate:
  adding nodes for work that an existing node was about to pick up costs a lot
  and gains nothing.
* **It never removes a node that is running anything.** The trade is that one
  long analysis can keep a node alive on its own.
* **Each node's volume is tied to one worker.** With node-local storage classes,
  a given node number can only ever run on the worker holding its volume. If
  that worker is unavailable, that node cannot be rescheduled elsewhere. With
  zonal cloud disks, it is tied to one zone — see §3.
* **Before 3.6.9 the queue is always empty.** Jobs were dispatched directly to a
  node rather than queued, so there was nothing for the autoscaler to react to.

---

## 10. Disabling it

```yaml
AnalysisNodeAutoscaling:
  enabled: false
```

and upgrade. This removes the controller and everything it owns — Deployment,
ConfigMap, ServiceAccount and all RBAC, including the cluster-scoped role — and
restores the standard StatefulSet, which restarts the analysis nodes once (§4).

`AnalysisNodeReplicaCount` is used again, so set it to the fleet size you want.
The standard StatefulSet numbers its nodes from 0 again and reuses the matching
volumes.

* **Volumes above that count are kept but unused.** If the autoscaler had run
  nodes numbered higher than `AnalysisNodeReplicaCount - 1`, their `castdir`
  volumes stay in the namespace. Delete them if you do not plan to re-enable
  autoscaling:

  ```bash
  kubectl get pvc -n <namespace> | grep castdir-console-analysis-node-core
  ```

* **Disable it before uninstalling OpenKruise.** Uninstalling OpenKruise first
  deletes the analysis-node StatefulSet with it, and the next upgrade fails
  because Helm can no longer find the resource type it recorded.
