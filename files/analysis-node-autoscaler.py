#!/usr/bin/env python3
"""Analysis-node autoscaler for CAST Imaging on Kubernetes (IMAGKSL-5864).

Port of decide.sh + controller.sh. Standard library only, so it runs on
castimaging/init-util (Python 3.13) with no new image, no kubectl and no jq.

Two halves, deliberately separated:

  decide(...)   pure policy. No cluster access, no clock, no I/O. Every rule in
                04-scaling-algorithm.md is testable in milliseconds against a
                fixture - see test_autoscaler.py.

  Controller    the actuator. Reads live state, applies the gates that need
                history or a second look, and patches the StatefulSet.

Why the split survives the rewrite: the bugs that actually bit us were policy
bugs (counting total capacity instead of spare; weighing running jobs against a
queue), and they were caught by fixtures rather than by a cluster doing
something irreversible.
"""

from __future__ import annotations

import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

SA = "/var/run/secrets/kubernetes.io/serviceaccount"


# --------------------------------------------------------------------- log --

def _log(level: str, msg: str) -> None:
    ts = time.strftime("%H:%M:%S", time.gmtime())
    print(f"[{ts}] {level}{msg}", flush=True)


def log(msg: str) -> None:
    _log("", msg)


def warn(msg: str) -> None:
    _log("WARN ", msg)


# ------------------------------------------------------------------ policy --

@dataclass
class Decision:
    """What should happen. `action` is one of none | scale-up | scale-down."""
    action: str
    desired_replicas: int
    reserve_ordinals: list[int]
    reason: str
    spare: int = 0
    unservable: int = 0
    effective_max: int = 0
    ghosts: list[str] = field(default_factory=list)
    removed: list[int] = field(default_factory=list)
    reused: list[int] = field(default_factory=list)
    stuck_removed: list[int] = field(default_factory=list)

    @property
    def signature(self) -> str:
        """Identity of a decision, for the stabilisation window."""
        return f"{self.action}:{self.desired_replicas}:{_join(self.reserve_ordinals)}"


def _join(ordinals: list[int]) -> str:
    return ",".join(str(o) for o in ordinals)


def _ordinal_of(hostname: str) -> int:
    """console-analysis-node-core-7 -> 7. Non-numeric suffixes sort last."""
    tail = hostname.rsplit("-", 1)[-1]
    return int(tail) if tail.isdigit() else -1


def _fmt_nodes(doc: object) -> str:
    """queue-status nodes as 'ordinal:jobsInProgress/capacity', for the log.

    capacity here is the live per-node value (the one set in the UI), not the
    NB_OF_THREADS_FOR_NODE of the pod template. Never raises: it is also called
    on documents decide() rejected.
    """
    nodes = doc.get("nodes") if isinstance(doc, dict) else None
    if not isinstance(nodes, list):
        return "?"
    out = []
    for n in nodes:
        if not isinstance(n, dict):
            out.append("?")
            continue
        host = str(n.get("hostname", "?"))
        ordinal = _ordinal_of(host)
        name = str(ordinal) if ordinal >= 0 else host
        out.append(f"{name}:{n.get('jobsInProgress', '?')}/{n.get('capacity', '?')}")
    return " ".join(out)


def decide(
    doc: object,
    *,
    current_replicas: int,
    current_reserved: list[int],
    live_pods: list[str],
    new_node_capacity: int,
    min_nodes: int = 1,
    max_nodes: int = 10,
    untainted_nodes: int = 0,
    stuck_pods: dict[str, str] | None = None,
    ceiling: int = 0,
    known_capacity: dict[int, int] | None = None,
) -> Decision:
    """Pure policy: queue-status document in, decision out.

    stuck_pods maps pod name -> why, for pods that have not been Ready for
    longer than the controller's timeout. ceiling, when > 0, is a temporary
    cap set after such pods were removed, so they are not asked for again.

    known_capacity maps ordinal -> the capacity last seen on it when it differs
    from new_node_capacity. A node whose capacity was changed in the UI keeps
    that value when its ordinal is brought back; only a never-seen ordinal
    starts with MaxParallelAnalysisPerNode.
    """

    def decline(reason: str) -> Decision:
        return Decision("none", current_replicas, list(current_reserved), reason)

    # Rule 4: never act on data we could not read.
    if not isinstance(doc, dict):
        return decline("response is not valid JSON")
    if (
        "jobsQueued" not in doc
        or "nodes" not in doc
        or not isinstance(doc.get("nodes"), list)
    ):
        return decline("response does not match the queue-status schema")

    try:
        queued = int(doc["jobsQueued"])
    except (TypeError, ValueError):
        return decline("jobsQueued is not a number")

    # A node registered in Eureka whose pod is gone contributes no real capacity
    # and must never be chosen for removal, so it is dropped from every
    # calculation. "Unknown" is treated as busy, never as free (rule 5).
    ghosts: list[str] = []
    spare = 0
    idle: list[tuple[int, int, str]] = []  # (capacity, ordinal, hostname)

    for node in doc["nodes"]:
        try:
            host = str(node["hostname"])
            prog = int(node["jobsInProgress"])
            cap = int(node["capacity"])
        except (KeyError, TypeError, ValueError):
            return decline("a node entry does not match the queue-status schema")

        if live_pods and host not in live_pods:
            ghosts.append(host)
            continue

        # Clamped: a node running more than its capacity (the IMAGKSL-5783
        # over-claim) must contribute 0, never a negative that would cancel out
        # real spare on another node.
        spare += max(0, cap - prog)
        if prog == 0:
            idle.append((cap, _ordinal_of(host), host))

    unservable = max(0, queued - spare)

    # Ceiling: the limit the customer configured, and the anti-affinity limit
    # the cluster imposes. Breaching the first degrades the platform; breaching
    # the second leaves pods Pending with no obvious error.
    effective_max = max_nodes
    if untainted_nodes > 0:
        effective_max = min(effective_max, untainted_nodes - 1)
    # The anti-affinity ceiling counts workers, not their free CPU and memory,
    # so a pod can still sit Unschedulable below it. Once such a pod has been
    # removed, the controller pins the ceiling at the fleet that did start.
    if ceiling > 0:
        effective_max = min(effective_max, ceiling)

    reserved = sorted(set(current_reserved))

    # ------------------------------------------------------------ stuck pods --
    # A pod that never became Ready (Unschedulable for lack of CPU or memory,
    # crash-looping, image not pullable) is not in the registry, so it is
    # neither capacity nor an idle node, and the settle gate would wait for it
    # forever. It holds no work and no capacity, so removing it costs the queue
    # nothing: it goes first, before any scale-up or idle-node removal.
    #
    # Only pods absent from the registry: a registered node, Ready or not, is
    # judged by its jobsInProgress like any other, never removed as "stuck".
    listed = {str(n.get("hostname")) for n in doc["nodes"] if isinstance(n, dict)}
    stuck = sorted(
        (_ordinal_of(p), p) for p in (stuck_pods or {})
        if p not in listed and _ordinal_of(p) >= 0
    )

    # minNodes still applies: removing the only node to have it re-created by
    # the floor on the next tick would just loop. Such a pod needs a human.
    remaining = current_replicas
    stuck_removed: list[int] = []
    for ordinal, _pod in reversed(stuck):
        if remaining - 1 < min_nodes and remaining <= max_nodes:
            continue
        stuck_removed.append(ordinal)
        remaining -= 1

    if stuck_removed:
        why = ", ".join(f"{p} ({stuck_pods[p]})"            # type: ignore[index]
                        for o, p in stuck if o in stuck_removed)
        return Decision(
            "scale-down", remaining,
            sorted(set(reserved) | set(stuck_removed)),
            f"{len(stuck_removed)} pod(s) never became ready: {why}",
            spare=spare, unservable=unservable, effective_max=effective_max,
            ghosts=ghosts, removed=sorted(stuck_removed),
            stuck_removed=sorted(stuck_removed),
        )

    # ------------------------------------------------------------ scale up --
    # Only what no existing node can take. A node at jobsInProgress=0 while jobs
    # are queued is not missing capacity - its pickup routine has not fired yet.
    #
    # minNodes is a floor, not only a brake on scale-down: a fleet below it
    # (first install, minNodes raised by an upgrade, a manual scale) is brought
    # back up even with an empty queue. The ceiling still wins over the floor -
    # replicas the cluster cannot place would only sit Pending.
    floor = min(min_nodes, effective_max)
    room = effective_max - current_replicas

    # Reuse reserved ordinals before allocating new ones, so their 100Gi
    # castdir is reused and the PVC count stays bounded by maxNodes. Each comes
    # back with the capacity last set on it in the UI, so count them one by one
    # rather than dividing the queue by a single capacity, and take the largest
    # first. The UI cannot edit a stopped node, so the value recorded when it
    # was reserved is still the one it will start with.
    known = known_capacity or {}

    def cap_of(ordinal: int) -> int:
        return known.get(ordinal, new_node_capacity)

    pool = sorted(reserved, key=lambda o: (-cap_of(o), o))
    reused: list[int] = []
    grow = covered = 0
    # floor <= effective_max, so reaching it never needs more than room.
    while grow < room and (covered < unservable
                           or current_replicas + grow < floor):
        if pool:
            reused.append(pool.pop(0))
            covered += cap_of(reused[-1])
        else:
            covered += new_node_capacity
        grow += 1
    desired = current_replicas + grow

    if grow > 0:
        kept = sorted(pool)

        if unservable > 0:
            reason = (f"{unservable} job(s) beyond {spare} spare thread(s) "
                      f"-> +{grow} node(s)")
        else:
            reason = (f"below minNodes ({current_replicas} < {floor}) "
                      f"-> +{grow} node(s)")

        return Decision(
            "scale-up", desired, kept, reason,
            spare=spare, unservable=unservable, effective_max=effective_max,
            ghosts=ghosts, reused=sorted(reused),
        )

    # Above maxNodes (lowered by an upgrade, or a manual scale) the excess must
    # go even while jobs wait, so fall through to scale-down instead of
    # declining. Only maxNodes counts here, not the anti-affinity ceiling: a
    # cordon taints a node, and draining one for maintenance must not make the
    # fleet shed nodes it will want back minutes later.
    over_max = current_replicas > max_nodes

    if unservable > 0 and not over_max:
        d = decline(
            f"at the ceiling ({effective_max}); {unservable} job(s) must wait"
        )
        d.spare, d.unservable, d.effective_max, d.ghosts = (
            spare, unservable, effective_max, ghosts,
        )
        return d

    # ---------------------------------------------------------- scale down --
    # Decide WHICH nodes to drop and let the count fall out. Dividing assumes
    # every node is worth the same, which mixed capacities break.
    #
    # Two corrections to the obvious version of this test, both found 2026-09-22:
    #   1. Measure SPARE, not total capacity. Capacity already running a job
    #      cannot host a queued one.
    #   2. Weigh it against QUEUED work only. Jobs in progress are pinned to the
    #      node running them - nothing migrates - and only idle nodes are ever
    #      removed, so a removal displaces no running work.
    #
    # What exposed it: core-0 ran THREE jobs on capacity 2, giving inprogress=5
    # against total capacity 6, so an empty core-1 was held for five minutes
    # because 6-2=4 < 5. Neither number was the right one to compare.
    remaining = current_replicas
    spare_left = spare
    removed: list[int] = []

    # Cheapest capacity first, then highest ordinal: give up the least useful
    # node and keep the ordinal range compact.
    #
    # While above maxNodes the ceiling outranks both the queue and minNodes (a
    # minNodes above maxNodes is a misconfiguration; the ceiling wins). Busy
    # nodes are still never removed: the excess drains one idle node at a time.
    for cap, ordinal, _host in sorted(idle, key=lambda n: (n[0], -n[1])):
        excess = remaining > max_nodes
        if remaining - 1 < min_nodes and not excess:
            continue
        # Load-bearing: an idle node's spare IS its capacity, so removing it
        # takes exactly `cap` slots away from the queue.
        if spare_left - cap < queued and not excess:
            continue
        removed.append(ordinal)
        spare_left -= cap
        remaining -= 1

    if not removed:
        if over_max:
            reason = (f"above maxNodes ({current_replicas} > {max_nodes}) but "
                      f"no idle node to remove - waiting for one to finish")
        else:
            reason = (f"nothing removable: {len(idle)} idle node(s), {queued} "
                      f"queued job(s) need the {spare_left} spare thread(s), "
                      f"min={min_nodes}")
        d = decline(reason)
        d.spare, d.unservable, d.effective_max, d.ghosts = (
            spare, unservable, effective_max, ghosts,
        )
        return d

    # reserveOrdinals ACCUMULATES. Dropping an entry silently resurrects that pod.
    merged = sorted(set(reserved) | set(removed))

    reason = (f"{len(removed)} idle node(s) removable, keeping {spare_left} "
              f"spare thread(s) for {queued} queued job(s)")
    if over_max:
        reason = f"above maxNodes ({current_replicas} > {max_nodes}): " + reason

    return Decision(
        "scale-down", remaining, merged, reason,
        spare=spare, unservable=unservable, effective_max=effective_max,
        ghosts=ghosts, removed=removed,
    )


# ----------------------------------------------------------------- k8s I/O --

class ApiError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"HTTP {status}: {body[:200]}")
        self.status = status


class Kube:
    """Minimal Kubernetes client over the pod's ServiceAccount."""

    def __init__(self) -> None:
        host = os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc")
        port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
        self.base = f"https://{host}:{port}"
        self.ctx = ssl.create_default_context(cafile=f"{SA}/ca.crt")

    def _token(self) -> str:
        # Re-read every call: projected tokens are rotated while we run.
        with open(f"{SA}/token", encoding="utf-8") as fh:
            return fh.read().strip()

    def request(self, method: str, path: str, body: dict | None = None,
                content_type: str | None = None, timeout: int = 15) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self._token())
        req.add_header("Accept", "application/json")
        if content_type:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=timeout) as r:
                return json.loads(r.read() or "{}")
        except urllib.error.HTTPError as e:
            raise ApiError(e.code, e.read().decode("utf-8", "replace")) from None

    def get(self, path: str) -> dict:
        return self.request("GET", path)

    def merge_patch(self, path: str, patch: dict) -> dict:
        return self.request("PATCH", path, patch, "application/merge-patch+json")


def namespace() -> str:
    env = os.environ.get("NAMESPACE")
    if env:
        return env
    try:
        with open(f"{SA}/namespace", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return "default"


# -------------------------------------------------------------- controller --

KRUISE = "apis/apps.kruise.io/v1beta1"
NATIVE = "apis/apps/v1"

# On the StatefulSet: {"ordinal": capacity} for every ordinal whose capacity, as
# last seen in queue-status, differs from MaxParallelAnalysisPerNode. A node
# changed in the UI keeps that value across a restart of its ordinal, but once
# reserved it is no longer listed anywhere: this is the only record of it, and
# it must outlive a restart of the autoscaler.
CAPACITY_ANNOTATION = "imaging.castsoftware.com/ordinal-capacity"


def _parse_capacity_annotation(value: object) -> dict[int, int]:
    """The annotation as {ordinal: capacity}. Unreadable -> empty, never raises.

    A capacity below 1 cannot be set in the UI, so it is dropped as corrupt.
    """
    try:
        raw = json.loads(value) if isinstance(value, str) else {}
        parsed = {int(o): int(c) for o, c in raw.items()}
        return {o: c for o, c in parsed.items() if c >= 1}
    except (ValueError, TypeError, AttributeError):
        return {}


def observe_capacity(known: dict[int, int], doc: object, live_pods: list[str],
                     helm_capacity: int) -> dict[int, int]:
    """known, updated with the capacity of every live node in queue-status.

    Only values that differ from Helm's are kept: an ordinal never changed in
    the UI comes back with MaxParallelAnalysisPerNode, whatever it was before.
    Ordinals not listed (reserved, stuck, ghosts) keep what was last seen.
    """
    out = dict(known)
    nodes = doc.get("nodes") if isinstance(doc, dict) else None
    for n in nodes if isinstance(nodes, list) else []:
        try:
            host, cap = str(n["hostname"]), int(n["capacity"])
        except (KeyError, TypeError, ValueError):
            continue
        ordinal = _ordinal_of(host)
        if ordinal < 0 or (live_pods and host not in live_pods) or cap < 1:
            continue
        if cap == helm_capacity:
            out.pop(ordinal, None)
        else:
            out[ordinal] = cap
    return out


@dataclass
class Config:
    namespace: str
    sts_name: str
    pod_selector: str
    queue_status_url: str
    min_nodes: int
    max_nodes: int
    poll_interval: int
    up_window: int
    down_window: int
    dry_run: bool
    once: bool
    run_for: int
    stuck_timeout: int = 600

    @staticmethod
    def from_env() -> "Config":
        def i(name: str, default: int) -> int:
            try:
                return int(os.environ.get(name, default))
            except ValueError:
                return default

        return Config(
            namespace=namespace(),
            sts_name=os.environ.get("STS_NAME", "console-analysis-node-core"),
            pod_selector=os.environ.get(
                "POD_SELECTOR", "imaging.service=console-analysis-node"),
            queue_status_url=os.environ.get(
                "QUEUE_STATUS_URL",
                "http://console-service:8091/api/jobs/queue-status"),
            min_nodes=i("MIN_NODES", 1),
            max_nodes=i("MAX_NODES", 10),
            poll_interval=i("POLL_INTERVAL_SECONDS", 30),
            up_window=i("SCALE_UP_STABILIZATION_SECONDS", 60),
            down_window=i("SCALE_DOWN_STABILIZATION_SECONDS", 120),
            dry_run=os.environ.get("DRY_RUN", "true").lower() == "true",
            once=os.environ.get("ONCE", "false").lower() == "true",
            run_for=i("RUN_FOR_SECONDS", 0),
            stuck_timeout=i("STUCK_POD_TIMEOUT_SECONDS", 600),
        )


@dataclass
class State:
    kind: str                 # KRUISE or NATIVE
    replicas: int
    ready: int
    reserved: list[int]
    capacity_per_node: int
    live_pods: list[str]
    untainted: int
    # pod name -> (uid, why) for every pod not Ready, whatever its age.
    not_ready: dict[str, tuple[str, str]] = field(default_factory=dict)
    # CAPACITY_ANNOTATION as stored on the StatefulSet.
    stored_capacity: dict[int, int] = field(default_factory=dict)


def _not_ready_reason(pod: dict) -> str | None:
    """None if the pod is Ready, else a short why for the log."""
    status = pod.get("status", {}) or {}
    conditions = {c.get("type"): c for c in status.get("conditions", []) or []}
    if (conditions.get("Ready") or {}).get("status") == "True":
        return None
    scheduled = conditions.get("PodScheduled") or {}
    if scheduled.get("status") == "False":
        return scheduled.get("reason") or "not scheduled"
    for cs in status.get("containerStatuses", []) or []:
        waiting = (cs.get("state") or {}).get("waiting")
        if waiting and waiting.get("reason"):
            return waiting["reason"]
    return status.get("phase") or "not ready"


class Controller:
    def __init__(self, cfg: Config, kube: Kube) -> None:
        self.cfg = cfg
        self.kube = kube
        self.pending: str | None = None
        self.pending_since = 0.0
        self._warned_nodes = False
        # pod uid -> monotonic time it was first seen not Ready. Keyed on uid so
        # a re-created pod with the same name starts a fresh clock. Lost on
        # restart, which only delays a removal - never hastens one.
        self.not_ready_since: dict[str, float] = {}
        # Temporary cap after stuck pods were removed (0 = none).
        self.ceiling = 0
        self.ceiling_until = 0.0
        # ordinal -> capacity when it differs from Helm's (see observe_capacity).
        # None until loaded from CAPACITY_ANNOTATION on the first tick.
        self.known_capacity: dict[int, int] | None = None

    # -- reading -----------------------------------------------------------
    def _sts_path(self, kind: str) -> str:
        return (f"/{kind}/namespaces/{self.cfg.namespace}"
                f"/statefulsets/{self.cfg.sts_name}")

    def read_state(self) -> State:
        sts, kind = None, ""
        for candidate in (KRUISE, NATIVE):
            try:
                sts = self.kube.get(self._sts_path(candidate))
                kind = candidate
                break
            except ApiError as e:
                if e.status != 404:
                    raise
        if sts is None:
            raise RuntimeError(
                f"statefulset {self.cfg.sts_name} not found as either "
                f"apps.kruise.io/v1beta1 or apps/v1")

        spec = sts.get("spec", {})
        status = sts.get("status", {})

        capacity = 0
        for c in spec.get("template", {}).get("spec", {}).get("containers", []):
            for env in c.get("env", []) or []:
                if env.get("name") == "NB_OF_THREADS_FOR_NODE":
                    try:
                        capacity = int(env.get("value"))
                    except (TypeError, ValueError):
                        capacity = 0

        pods = self.kube.get(
            f"/api/v1/namespaces/{self.cfg.namespace}/pods"
            f"?labelSelector={urllib.parse.quote(self.cfg.pod_selector)}")
        live: list[str] = []
        not_ready: dict[str, tuple[str, str]] = {}
        for p in pods.get("items", []):
            meta = p.get("metadata", {})
            if meta.get("deletionTimestamp") is not None:
                continue
            if p.get("status", {}).get("phase") == "Running":
                live.append(meta["name"])
            why = _not_ready_reason(p)
            if why is not None:
                not_ready[meta["name"]] = (meta.get("uid") or meta["name"], why)

        return State(
            kind=kind,
            replicas=int(spec.get("replicas", 0)),
            ready=int(status.get("readyReplicas", 0) or 0),
            reserved=[int(o) for o in spec.get("reserveOrdinals", []) or []],
            capacity_per_node=capacity,
            live_pods=sorted(live),
            untainted=self._untainted_nodes(),
            not_ready=not_ready,
            stored_capacity=_parse_capacity_annotation(
                (sts.get("metadata", {}).get("annotations") or {})
                .get(CAPACITY_ANNOTATION)),
        )

    def stuck_pods(self, state: State) -> dict[str, str]:
        """Pods not Ready for longer than the timeout: pod name -> why.

        Also refreshes the not-Ready clocks, forgetting pods that became Ready
        or disappeared.
        """
        now = time.monotonic()
        self.not_ready_since = {
            uid: self.not_ready_since.get(uid, now)
            for uid, _why in state.not_ready.values()
        }
        if self.cfg.stuck_timeout <= 0:
            return {}
        return {
            name: f"{why}, not ready for "
                  f"{int(now - self.not_ready_since[uid])}s"
            for name, (uid, why) in state.not_ready.items()
            if now - self.not_ready_since[uid] >= self.cfg.stuck_timeout
        }

    def current_ceiling(self) -> int:
        if self.ceiling and time.monotonic() >= self.ceiling_until:
            log(f"  ceiling of {self.ceiling} lifted")
            self.ceiling = 0
        return self.ceiling

    def _untainted_nodes(self) -> int:
        """Schedulable nodes, for the anti-affinity ceiling.

        Needs a cluster-scoped read. If RBAC does not allow it we degrade to 0,
        which disables only this ceiling - maxNodes still applies - rather than
        forcing every install to grant cluster-wide permissions.
        """
        try:
            nodes = self.kube.get("/api/v1/nodes")
        except ApiError as e:
            if e.status in (401, 403) and not self._warned_nodes:
                warn("cannot list nodes (RBAC) - the anti-affinity ceiling is "
                     "disabled; MAX_NODES still applies")
                self._warned_nodes = True
            return 0
        return sum(
            1 for n in nodes.get("items", [])
            if not any(t.get("effect") == "NoSchedule"
                       for t in (n.get("spec", {}).get("taints") or []))
        )

    def fetch_queue_status(self) -> object | None:
        try:
            with urllib.request.urlopen(
                    self.cfg.queue_status_url, timeout=10) as r:
                return json.loads(r.read())
        except Exception as e:                      # noqa: BLE001 - any failure
            warn(f"queue-status unreachable ({type(e).__name__}) - "
                 f"doing nothing this tick")
            return None

    # -- writing -----------------------------------------------------------
    def apply(self, state: State, decision: Decision) -> bool:
        """Patch the StatefulSet. True if it was actually changed."""
        reserved = decision.reserve_ordinals

        # A native StatefulSet removes the HIGHEST ordinal, which is exactly the
        # pod that may be busy. reserveOrdinals is the only reason this design
        # is safe, so without the Kruise object we must never scale DOWN.
        if state.kind != KRUISE:
            if decision.desired_replicas < state.replicas:
                warn("refusing to scale down a native StatefulSet: it removes "
                     "the highest ordinal regardless of which pod is idle.")
                warn("Convert to apps.kruise.io/v1beta1 first.")
                return False
            if reserved:
                warn("reserveOrdinals is not supported on a native "
                     "StatefulSet - ignoring it")
                reserved = []

        patch: dict = {"spec": {"replicas": decision.desired_replicas}}
        if state.kind == KRUISE:
            patch["spec"]["reserveOrdinals"] = reserved
        known = self.known_capacity or {}
        if known != state.stored_capacity:
            patch["metadata"] = {"annotations": {CAPACITY_ANNOTATION: json.dumps(
                {str(o): c for o, c in sorted(known.items())})}}

        if self.cfg.dry_run:
            log(f"  DRY RUN - would patch {state.kind}: {json.dumps(patch)}")
            return False

        log(f"  applying: {json.dumps(patch)}")
        self.kube.merge_patch(self._sts_path(state.kind), patch)
        return True

    # -- one tick ----------------------------------------------------------
    def tick(self) -> None:
        state = self.read_state()

        if state.capacity_per_node <= 0:
            warn("NB_OF_THREADS_FOR_NODE is not set on the pod template - "
                 "refusing to guess a new node's capacity")
            return

        doc = self.fetch_queue_status()
        if doc is None:
            return

        if self.known_capacity is None:
            self.known_capacity = dict(state.stored_capacity)
        self.known_capacity = observe_capacity(
            self.known_capacity, doc, state.live_pods, state.capacity_per_node)

        stuck = self.stuck_pods(state)
        ceiling = self.current_ceiling()
        decision = decide(
            doc,
            current_replicas=state.replicas,
            current_reserved=state.reserved,
            live_pods=state.live_pods,
            new_node_capacity=state.capacity_per_node,
            min_nodes=self.cfg.min_nodes,
            max_nodes=self.cfg.max_nodes,
            untainted_nodes=state.untainted,
            stuck_pods=stuck,
            ceiling=ceiling,
            known_capacity=self.known_capacity,
        )

        log(f"state: kind={state.kind.split('/')[1]} replicas={state.replicas} "
            f"ready={state.ready} reserved=[{_join(state.reserved)}] "
            f"newNodeCapacity={state.capacity_per_node} (helm) "
            f"untainted={state.untainted}"
            + (f" stuck=[{' '.join(sorted(stuck))}]" if stuck else "")
            + (f" ceiling={ceiling} ({int(self.ceiling_until - time.monotonic())}s"
               f" left)" if ceiling else ""))
        queued = doc.get("jobsQueued", "?") if isinstance(doc, dict) else "?"
        reserved_caps = {o: c for o, c in self.known_capacity.items()
                if o in state.reserved}
        log(f"queue: queued={queued} nodes=[{_fmt_nodes(doc)}]"
            + (" reservedCapacity=[" + " ".join(
                f"{o}:{c}" for o, c in sorted(reserved_caps.items())) + "]"
               if reserved_caps else ""))
        # Not Ready but not yet stuck: show the countdown, so a pod sitting
        # Pending is visibly being watched rather than ignored.
        if self.cfg.stuck_timeout > 0:
            now = time.monotonic()
            for name, (uid, why) in sorted(state.not_ready.items()):
                if name not in stuck:
                    log(f"  not ready: {name} ({why}) for "
                        f"{int(now - self.not_ready_since[uid])}s of "
                        f"{self.cfg.stuck_timeout}s before it counts as stuck")
        log(f"decision: {decision.action} -> replicas="
            f"{decision.desired_replicas} "
            f"reserve=[{_join(decision.reserve_ordinals)}]")
        log(f"  reason: {decision.reason}")

        if decision.action == "none":
            self.pending, self.pending_since = None, 0.0
            return

        # Rule 3: never change the fleet while the last change has not settled.
        # Adding capacity during a cold start is how R7 compounds.
        #
        # A pod stuck past the timeout is not settling - it has failed, and
        # waiting for it would hold every decision forever, including the one
        # that removes it. It counts as settled.
        if state.ready + len(stuck) < state.replicas:
            log(f"  holding: {state.ready}/{state.replicas} ready, "
                f"last change has not settled")
            return

        # Readiness and Eureka registration are DIFFERENT CLOCKS. A pod can pass
        # its readiness probe before the endpoint lists it, and in that window
        # the fleet looks smaller than it is. Ghosts (listed, no pod) are NOT a
        # reason to hold - decide() already excludes them. Neither are stuck
        # pods: a crash-looping pod is Running but will never register.
        listed = {n.get("hostname") for n in doc["nodes"]}      # type: ignore[index]
        missing = [p for p in state.live_pods
                   if p not in listed and p not in stuck]
        if missing:
            log(f"  holding: Ready but not yet in the endpoint: "
                f"{' '.join(missing)} - registry is mid-update")
            return

        # Stabilisation, keyed on the decision signature so a changing decision
        # resets the clock.
        need = (self.cfg.down_window if decision.action == "scale-down"
                else self.cfg.up_window)
        if decision.signature != self.pending:
            self.pending = decision.signature
            self.pending_since = time.monotonic()
            log(f"  holding: decision is new, need {need}s of agreement")
            return

        held = int(time.monotonic() - self.pending_since)
        if held < need:
            log(f"  holding: {held}s of {need}s agreement")
            return

        # Re-read immediately before acting. There is no quiesce mode (D8), so a
        # node idle when we decided may have been handed work since. This
        # shrinks the window; it does not close it.
        if decision.action == "scale-down":
            fresh_doc = self.fetch_queue_status()
            if fresh_doc is None:
                return
            fresh_state = self.read_state()
            recheck = decide(
                fresh_doc,
                current_replicas=fresh_state.replicas,
                current_reserved=fresh_state.reserved,
                live_pods=fresh_state.live_pods,
                new_node_capacity=fresh_state.capacity_per_node,
                min_nodes=self.cfg.min_nodes,
                max_nodes=self.cfg.max_nodes,
                untainted_nodes=fresh_state.untainted,
                stuck_pods=self.stuck_pods(fresh_state),
                ceiling=ceiling,
                known_capacity=observe_capacity(
                    self.known_capacity, fresh_doc, fresh_state.live_pods,
                    fresh_state.capacity_per_node),
            )
            if recheck.reserve_ordinals != decision.reserve_ordinals:
                warn("  aborting scale-down: the fleet changed between "
                     "deciding and acting")
                warn(f"  (was [{_join(decision.reserve_ordinals)}], "
                     f"now [{_join(recheck.reserve_ordinals)}])")
                self.pending, self.pending_since = None, 0.0
                return

        applied = self.apply(state, decision)
        self.pending, self.pending_since = None, 0.0

        # Asking again for the pod just removed would only recreate it stuck.
        # Hold the fleet at what did start for one more timeout; whatever
        # blocked it (a full cluster, a missing worker) may be gone by then.
        if applied and decision.stuck_removed:
            self.ceiling = decision.desired_replicas
            self.ceiling_until = time.monotonic() + self.cfg.stuck_timeout
            log(f"  ceiling pinned at {self.ceiling} for "
                f"{self.cfg.stuck_timeout}s")


def main() -> int:
    cfg = Config.from_env()
    log(f"analysis-node autoscaler starting (DRY_RUN={cfg.dry_run})")
    log(f"  namespace={cfg.namespace} statefulset={cfg.sts_name}")
    log(f"  bounds: min={cfg.min_nodes} max={cfg.max_nodes}")
    log(f"  stabilisation: up={cfg.up_window}s down={cfg.down_window}s")

    controller = Controller(cfg, Kube())
    started = time.monotonic()

    while True:
        try:
            controller.tick()
        except Exception as e:                      # noqa: BLE001
            warn(f"tick failed ({type(e).__name__}: {e}) - continuing")
        if cfg.once:
            return 0
        if cfg.run_for and time.monotonic() - started >= cfg.run_for:
            log("run budget reached - exiting")
            return 0
        time.sleep(cfg.poll_interval)


if __name__ == "__main__":
    sys.exit(main())
