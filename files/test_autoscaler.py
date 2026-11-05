#!/usr/bin/env python3
"""Tests for analysis-node-autoscaler.py. Standard library only.

    python3 files/test_autoscaler.py

decide() is tested directly against queue-status fixtures. The Controller is
tested with a fake Kubernetes API and a fake clock, for the gates that live
outside decide(): the stabilisation window and the re-read before a removal.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import unittest
from unittest import mock

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "autoscaler", os.path.join(_HERE, "analysis-node-autoscaler.py"))
autoscaler = importlib.util.module_from_spec(_spec)
sys.modules["autoscaler"] = autoscaler  # dataclasses resolve types through it
_spec.loader.exec_module(autoscaler)

PREFIX = "console-analysis-node-core-"
CAP = 2


def host(ordinal: int) -> str:
    return f"{PREFIX}{ordinal}"


def node(ordinal: int, in_progress: int, capacity: int = CAP) -> dict:
    return {"hostname": host(ordinal), "jobsInProgress": in_progress,
            "capacity": capacity}


def queue(queued: int, nodes: list[dict]) -> dict:
    return {"jobsQueued": queued, "nodes": nodes}


def decide(doc: dict, *, replicas: int, reserved: list[int] | None = None,
           min_nodes: int = 1, max_nodes: int = 10,
           untainted: int = 0, stuck: dict[int, str] | None = None,
           ceiling: int = 0,
           known: dict[int, int] | None = None) -> "autoscaler.Decision":
    return autoscaler.decide(
        doc,
        current_replicas=replicas,
        current_reserved=reserved or [],
        live_pods=[n["hostname"] for n in doc["nodes"]],
        new_node_capacity=CAP,
        min_nodes=min_nodes,
        max_nodes=max_nodes,
        untainted_nodes=untainted,
        stuck_pods={host(o): why for o, why in (stuck or {}).items()},
        ceiling=ceiling,
        known_capacity=known,
    )


# ------------------------------------------------------------ below minNodes --

class BelowMinNodes(unittest.TestCase):

    def test_empty_queue_scales_up_to_min(self):
        d = decide(queue(0, [node(0, 0)]), replicas=1, min_nodes=3)
        self.assertEqual(d.action, "scale-up")
        self.assertEqual(d.desired_replicas, 3)
        self.assertIn("below minNodes", d.reason)

    def test_queue_smaller_than_floor_still_reaches_min(self):
        # 3 queued, 2 spare -> the queue alone asks for +1; the floor asks +2.
        d = decide(queue(3, [node(0, 0)]), replicas=1, min_nodes=3)
        self.assertEqual(d.desired_replicas, 3)

    def test_queue_larger_than_floor_wins(self):
        d = decide(queue(9, [node(0, 0)]), replicas=1, min_nodes=2)
        self.assertEqual(d.desired_replicas, 5)  # 7 unservable -> +4

    def test_reuses_reserved_ordinals_before_new_ones(self):
        # Pods 1 and 2 run; 0 and 3 were removed earlier and keep their PVCs.
        # Raising the floor by one must bring back 0, not allocate ordinal 4.
        d = decide(queue(0, [node(1, 0), node(2, 0)]),
                   replicas=2, reserved=[0, 3], min_nodes=3)
        self.assertEqual(d.action, "scale-up")
        self.assertEqual(d.desired_replicas, 3)
        self.assertEqual(d.reused, [0])
        self.assertEqual(d.reserve_ordinals, [3])

    def test_reuses_all_reserved_when_floor_needs_them(self):
        d = decide(queue(0, [node(1, 0)]),
                   replicas=1, reserved=[0, 2], min_nodes=3)
        self.assertEqual(d.reused, [0, 2])
        self.assertEqual(d.reserve_ordinals, [])

    def test_floor_capped_by_schedulable_workers(self):
        # 3 untainted workers -> at most 2 analysis nodes, whatever minNodes says.
        d = decide(queue(0, [node(0, 0)]), replicas=1, min_nodes=5, untainted=3)
        self.assertEqual(d.desired_replicas, 2)

    def test_at_min_with_empty_queue_does_nothing(self):
        d = decide(queue(0, [node(0, 0)]), replicas=1, min_nodes=1)
        self.assertEqual(d.action, "none")


# ------------------------------------------------------------ above maxNodes --

class AboveMaxNodes(unittest.TestCase):

    def test_waiting_jobs_do_not_keep_the_excess(self):
        # 10 queued would normally hold every idle node, but 4 > maxNodes=2.
        nodes = [node(i, 0) for i in range(4)]
        d = decide(queue(10, nodes), replicas=4, max_nodes=2)
        self.assertEqual(d.action, "scale-down")
        self.assertEqual(d.desired_replicas, 2)
        self.assertEqual(d.reserve_ordinals, [2, 3])
        self.assertIn("above maxNodes", d.reason)

    def test_ceiling_outranks_a_higher_min(self):
        nodes = [node(i, 0) for i in range(4)]
        d = decide(queue(0, nodes), replicas=4, min_nodes=4, max_nodes=2)
        self.assertEqual(d.desired_replicas, 2)

    def test_all_busy_removes_nothing(self):
        nodes = [node(i, 1) for i in range(4)]
        d = decide(queue(5, nodes), replicas=4, max_nodes=2)
        self.assertEqual(d.action, "none")
        self.assertEqual(d.desired_replicas, 4)
        self.assertEqual(d.reserve_ordinals, [])
        self.assertIn("no idle node", d.reason)

    def test_only_idle_nodes_go(self):
        nodes = [node(0, 1), node(1, 1), node(2, 0), node(3, 2)]
        d = decide(queue(3, nodes), replicas=4, max_nodes=2)
        self.assertEqual(d.action, "scale-down")
        self.assertEqual(d.removed, [2])
        self.assertEqual(d.desired_replicas, 3)

    def test_above_worker_ceiling_only_is_not_forced(self):
        # 4 nodes, 3 untainted workers (e.g. one cordoned), maxNodes=10: the
        # queue still needs every idle node, so nothing is removed.
        nodes = [node(i, 0) for i in range(4)]
        d = decide(queue(8, nodes), replicas=4, max_nodes=10, untainted=3)
        self.assertEqual(d.action, "none")


# --------------------------------------------------------------- controller --

class FakeKube:
    """Serves one Kruise StatefulSet and its pods; records and applies patches.

    `pending` maps an ordinal to the reason its pod cannot be scheduled.
    """

    def __init__(self, replicas: int, reserved: list[int],
                 pending: dict[int, str] | None = None):
        self.replicas = replicas
        self.reserved = reserved
        self.pending = dict(pending or {})
        self.patches: list[dict] = []
        self.annotations: dict[str, str] = {}

    def _running(self) -> list[int]:
        out, ordinal = [], 0
        while len(out) < self.replicas:
            if ordinal not in self.reserved:
                out.append(ordinal)
            ordinal += 1
        return out

    def get(self, path: str) -> dict:
        if "/statefulsets/" in path:
            if not path.startswith("/" + autoscaler.KRUISE):
                raise autoscaler.ApiError(404, "not found")
            return {
                "metadata": {"annotations": dict(self.annotations)},
                "spec": {
                    "replicas": self.replicas,
                    "reserveOrdinals": list(self.reserved),
                    "template": {"spec": {"containers": [{"env": [
                        {"name": "NB_OF_THREADS_FOR_NODE", "value": str(CAP)},
                    ]}]}},
                },
                "status": {"readyReplicas": len(
                    [o for o in self._running() if o not in self.pending])},
            }
        if "/pods" in path:
            return {"items": [self._pod(o) for o in self._running()]}
        if path.endswith("/nodes"):
            raise autoscaler.ApiError(403, "forbidden")
        raise AssertionError(f"unexpected GET {path}")

    def _pod(self, ordinal: int) -> dict:
        meta = {"name": host(ordinal), "uid": f"uid-{ordinal}"}
        if ordinal in self.pending:
            return {"metadata": meta, "status": {
                "phase": "Pending",
                "conditions": [{"type": "PodScheduled", "status": "False",
                                "reason": self.pending[ordinal]}],
            }}
        return {"metadata": meta, "status": {
            "phase": "Running",
            "conditions": [{"type": "PodScheduled", "status": "True"},
                           {"type": "Ready", "status": "True"}],
        }}

    def merge_patch(self, path: str, patch: dict) -> dict:
        self.patches.append(patch)
        self.replicas = patch["spec"]["replicas"]
        self.reserved = patch["spec"].get("reserveOrdinals", self.reserved)
        self.annotations.update(
            patch.get("metadata", {}).get("annotations", {}))
        self.pending = {o: r for o, r in self.pending.items()
                        if o in self._running()}
        return {}


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class ScaleDownToMaxThroughController(unittest.TestCase):
    """Bringing the fleet back under maxNodes is an ordinary scale-down: it
    must wait the full down window and re-read the queue before patching."""

    DOWN_WINDOW = 120

    def setUp(self) -> None:
        self.kube = FakeKube(replicas=3, reserved=[])
        cfg = autoscaler.Config(
            namespace="ns", sts_name="console-analysis-node-core",
            pod_selector="x", queue_status_url="http://unused",
            min_nodes=1, max_nodes=2, poll_interval=30,
            up_window=60, down_window=self.DOWN_WINDOW,
            dry_run=False, once=False, run_for=0,
        )
        self.ctl = autoscaler.Controller(cfg, self.kube)
        self.docs: list[dict] = []
        self.ctl.fetch_queue_status = lambda: self.docs.pop(0)
        self.clock = Clock()
        patcher = mock.patch.object(autoscaler.time, "monotonic", self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.quiet = mock.patch("builtins.print")
        self.quiet.start()
        self.addCleanup(self.quiet.stop)

    def tick_at(self, seconds: float, *docs: dict) -> None:
        self.docs.extend(docs)
        self.clock.now = 1000.0 + seconds
        self.ctl.tick()

    def test_waits_the_full_down_window(self):
        busy_queue = queue(6, [node(0, 2), node(1, 2), node(2, 0)])
        self.tick_at(0, busy_queue)
        self.tick_at(60, busy_queue)
        self.tick_at(119, busy_queue)
        self.assertEqual(self.kube.patches, [])
        # At the window, decide again and re-read once more before acting.
        self.tick_at(120, busy_queue, busy_queue)
        self.assertEqual(self.kube.patches,
                         [{"spec": {"replicas": 2, "reserveOrdinals": [2]}}])

    def test_aborts_if_the_node_took_a_job_meanwhile(self):
        before = queue(6, [node(0, 2), node(1, 2), node(2, 0)])
        after = queue(5, [node(0, 2), node(1, 2), node(2, 1)])  # core-2 busy now
        self.tick_at(0, before)
        self.tick_at(120, before, after)
        self.assertEqual(self.kube.patches, [])
        # The pending decision is dropped: a new one starts its own window.
        self.assertIsNone(self.ctl.pending)


# ------------------------------------------------- pods that never start --

class StuckPods(unittest.TestCase):
    """A pod that never becomes Ready never registers, so the queue does not
    see it. Seen 2026-10-24: scaled to 2, core-1 Unschedulable for lack of CPU,
    and the fleet froze at 2 - the settle gate waited for core-1 forever, and
    the only removal on offer was core-0, the one node that worked."""

    def test_stuck_pod_goes_not_the_working_idle_one(self):
        d = decide(queue(0, [node(0, 0)]), replicas=2,
                   stuck={1: "Unschedulable"})
        self.assertEqual((d.action, d.desired_replicas), ("scale-down", 1))
        self.assertEqual(d.reserve_ordinals, [1])
        self.assertEqual(d.stuck_removed, [1])
        self.assertIn("never became ready", d.reason)

    def test_stuck_pod_goes_even_while_jobs_wait(self):
        # It contributes no capacity, so the queue cannot be a reason to keep it.
        d = decide(queue(4, [node(0, 2)]), replicas=2,
                   stuck={1: "Unschedulable"})
        self.assertEqual((d.action, d.reserve_ordinals), ("scale-down", [1]))

    def test_stuck_pod_kept_at_min_nodes(self):
        # Removing it would only have the floor re-create it next tick.
        d = decide(queue(0, []), replicas=1, stuck={0: "CrashLoopBackOff"})
        self.assertEqual(d.action, "none")

    def test_registered_node_is_never_treated_as_stuck(self):
        # In the registry means it started; jobsInProgress decides, as usual.
        d = decide(queue(0, [node(0, 0), node(1, 2)]), replicas=2,
                   stuck={1: "Running"})
        self.assertEqual(d.action, "scale-down")
        self.assertEqual(d.reserve_ordinals, [0])

    def test_stuck_ordinal_joins_existing_reservations(self):
        d = decide(queue(0, [node(1, 1)]), replicas=2, reserved=[0],
                   stuck={2: "Unschedulable"})
        self.assertEqual(d.reserve_ordinals, [0, 2])

    def test_ceiling_holds_back_the_scale_up(self):
        d = decide(queue(4, [node(0, 2)]), replicas=1, ceiling=1)
        self.assertEqual(d.action, "none")
        self.assertIn("at the ceiling (1)", d.reason)


class StuckPodThroughController(unittest.TestCase):
    """Replays the 2026-10-24 incident through the controller's gates."""

    TIMEOUT = 600
    DOWN_WINDOW = 120

    def setUp(self) -> None:
        self.kube = FakeKube(replicas=2, reserved=[],
                             pending={1: "Unschedulable"})
        cfg = autoscaler.Config(
            namespace="ns", sts_name="console-analysis-node-core",
            pod_selector="x", queue_status_url="http://unused",
            min_nodes=1, max_nodes=2, poll_interval=30,
            up_window=60, down_window=self.DOWN_WINDOW,
            dry_run=False, once=False, run_for=0,
            stuck_timeout=self.TIMEOUT,
        )
        self.ctl = autoscaler.Controller(cfg, self.kube)
        self.docs: list[dict] = []
        self.ctl.fetch_queue_status = lambda: self.docs.pop(0)
        self.clock = Clock()
        patcher = mock.patch.object(autoscaler.time, "monotonic", self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.quiet = mock.patch("builtins.print")
        self.quiet.start()
        self.addCleanup(self.quiet.stop)

    def tick_at(self, seconds: float, *docs: dict) -> None:
        self.docs.extend(docs)
        self.clock.now = 1000.0 + seconds
        self.ctl.tick()

    def test_waits_for_the_timeout_then_removes_the_stuck_pod(self):
        idle = queue(0, [node(0, 0)])
        self.tick_at(0, idle)
        self.tick_at(self.TIMEOUT - 1, idle)       # still a cold start
        self.assertEqual(self.kube.patches, [])
        self.tick_at(self.TIMEOUT, idle)           # stuck now; window starts
        self.tick_at(self.TIMEOUT + self.DOWN_WINDOW, idle, idle)
        self.assertEqual(self.kube.patches,
                         [{"spec": {"replicas": 1, "reserveOrdinals": [1]}}])

    def test_does_not_ask_for_it_again_until_the_ceiling_lifts(self):
        idle = queue(0, [node(0, 0)])
        busy = queue(4, [node(0, 2)])
        self.tick_at(0, idle)
        self.tick_at(self.TIMEOUT, idle)
        self.tick_at(self.TIMEOUT + self.DOWN_WINDOW, idle, idle)
        removed_at = self.TIMEOUT + self.DOWN_WINDOW
        self.assertEqual(self.ctl.ceiling, 1)

        # Jobs pile up: pinned at 1, no new scale-up.
        self.tick_at(removed_at + 30, busy)
        self.tick_at(removed_at + 120, busy)
        self.assertEqual(len(self.kube.patches), 1)

        # Once lifted, the queue may ask for core-1 back (reusing its ordinal).
        self.tick_at(removed_at + self.TIMEOUT, busy)
        self.tick_at(removed_at + self.TIMEOUT + 60, busy)
        self.assertEqual(self.ctl.ceiling, 0)
        self.assertEqual(self.kube.patches[-1],
                         {"spec": {"replicas": 2, "reserveOrdinals": []}})

    def test_timeout_zero_keeps_the_old_behaviour(self):
        self.ctl.cfg.stuck_timeout = 0
        idle = queue(0, [node(0, 0)])
        for t in (0, 600, 1200, 1800):
            self.tick_at(t, idle)
        self.assertEqual(self.kube.patches, [])


# ------------------------------------------------------- what the queue means --

class ScaleUpOnlyWhatCannotBeAbsorbed(unittest.TestCase):
    """A queue is not a shortage.

    Jobs an existing node is about to pick up need no new node. Provisioning for
    them costs a cold start and the new node arrives with nothing to do.
    """

    def test_queue_absorbed_by_spare_threads(self):
        d = decide(queue(3, [node(0, 1), node(1, 2), node(2, 0)]), replicas=3)
        self.assertEqual(d.action, "none")

    def test_mixed_capacities_still_absorbed(self):
        # node count x capacity would be wrong twice over here.
        d = decide(queue(3, [node(0, 2), node(1, 3, 4), node(2, 0)]), replicas=3)
        self.assertEqual(d.action, "none")

    def test_only_the_unservable_part_is_provisioned(self):
        # 5 queued, 3 spare -> 2 unservable -> +1 node, not the +3 that
        # ceil(5/2) over the whole queue would give.
        d = decide(queue(5, [node(0, 2), node(1, 1), node(2, 0)]), replicas=3)
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 4))

    def test_genuine_saturation(self):
        d = decide(queue(10, [node(0, 2), node(1, 2)]), replicas=2)
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 7))

    def test_clamped_at_max_nodes(self):
        d = decide(queue(100, [node(0, 2), node(1, 2), node(2, 2)]),
                   replicas=3, max_nodes=10)
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 10))

    def test_clamped_at_schedulable_workers_minus_one(self):
        # Each node needs its own worker (anti-affinity) and one is left for
        # Neo4j. Asking for more leaves pods Pending with no obvious cause.
        d = decide(queue(100, [node(0, 2), node(1, 2), node(2, 2)]),
                   replicas=3, max_nodes=10, untainted=5)
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 4))


# --------------------------------------------------- choosing WHICH node goes --

class ChoosingWhichNodeToRemove(unittest.TestCase):
    """The reason OpenKruise is a dependency at all."""

    def test_all_idle_goes_down_to_min(self):
        d = decide(queue(0, [node(0, 0), node(1, 0), node(2, 0)]), replicas=3)
        self.assertEqual((d.action, d.desired_replicas), ("scale-down", 1))
        self.assertEqual(d.reserve_ordinals, [1, 2])

    def test_busy_node_is_the_highest_ordinal_and_survives(self):
        # THE case the whole design exists for. A native StatefulSet deletes the
        # highest ordinal - here core-2, the only node running an analysis.
        # reserveOrdinals must take core-0 and core-1 instead.
        d = decide(queue(0, [node(0, 0), node(1, 0), node(2, 2)]), replicas=3)
        self.assertEqual(d.action, "scale-down")
        self.assertEqual(d.reserve_ordinals, [0, 1])
        self.assertNotIn(2, d.reserve_ordinals)

    def test_heterogeneous_capacity_keeps_the_busy_small_node(self):
        # Division cannot express this: dropping the capacity-4 node is fine,
        # dropping the busy capacity-2 one is not.
        d = decide(queue(0, [node(0, 0, 4), node(1, 0), node(2, 2)]), replicas=3)
        self.assertEqual(d.reserve_ordinals, [0, 1])


# -------------------------------------- capacity does not bound concurrency --

class Overcommit(unittest.TestCase):
    """A node can run more jobs than its capacity (IMAGKSL-5783).

    These two encode the arithmetic bug this policy once had: comparing TOTAL
    capacity against jobs ALREADY RUNNING. An idle node was then held for five
    minutes because 6-2=4 < 5, with neither number being the right one.
    """

    def test_idle_node_still_removable_when_another_is_over_capacity(self):
        # core-0 runs 3 jobs on capacity 2. Nothing is queued, so the empty
        # core-1 is free to go: running jobs are pinned where they are.
        d = decide(queue(0, [node(0, 3), node(1, 0), node(2, 2)]), replicas=3)
        self.assertEqual((d.action, d.desired_replicas), ("scale-down", 2))
        self.assertEqual(d.reserve_ordinals, [1])

    def test_idle_node_kept_when_queued_work_has_nowhere_else_to_land(self):
        # Same fleet, but 2 jobs are waiting and core-1 is the only free slot.
        d = decide(queue(2, [node(0, 3), node(1, 0), node(2, 2)]), replicas=3)
        self.assertEqual(d.action, "none")


# -------------------------------------------------------------------- safety --

class NeverActOnBadData(unittest.TestCase):

    def test_malformed_document_changes_nothing(self):
        d = autoscaler.decide(
            None, current_replicas=3, current_reserved=[], live_pods=[],
            new_node_capacity=CAP)
        self.assertEqual((d.action, d.desired_replicas), ("none", 3))

    def test_document_missing_the_schema_changes_nothing(self):
        d = autoscaler.decide(
            {"nodes": []}, current_replicas=3, current_reserved=[],
            live_pods=[], new_node_capacity=CAP)
        self.assertEqual(d.action, "none")

    def test_registered_node_with_no_pod_is_never_removed(self):
        # core-9 is in the registry but has no pod. It contributes no real
        # capacity and must never be chosen for removal - only core-0 is live.
        doc = queue(0, [node(0, 0), node(9, 0)])
        d = autoscaler.decide(
            doc, current_replicas=2, current_reserved=[], live_pods=[host(0)],
            new_node_capacity=CAP, min_nodes=1, max_nodes=10)
        self.assertEqual((d.action, d.desired_replicas), ("scale-down", 1))
        self.assertEqual(d.reserve_ordinals, [0])
        self.assertNotIn(9, d.reserve_ordinals)


# ------------------------------------------ ordinal reuse keeps PVCs bounded --

class OrdinalReuse(unittest.TestCase):
    """Every new ordinal provisions a 100Gi volume that is never reclaimed."""

    def test_reserved_ordinals_are_reused_before_new_ones(self):
        d = decide(queue(10, [node(0, 2), node(1, 2)]), replicas=2,
                   reserved=[0, 1])
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 7))
        self.assertEqual(d.reserve_ordinals, [])

    def test_a_reserved_ordinal_is_released_rather_than_allocating_a_new_one(self):
        d = decide(queue(5, [node(0, 2), node(1, 1), node(2, 0)]), replicas=3,
                   reserved=[5])
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 4))
        self.assertEqual(d.reserve_ordinals, [])

    def test_reserve_ordinals_accumulate_and_are_never_replaced(self):
        # Dropping an existing entry silently resurrects that pod.
        d = decide(queue(0, [node(0, 0), node(1, 0), node(2, 0)]), replicas=3,
                   reserved=[7])
        self.assertEqual(d.reserve_ordinals, [1, 2, 7])


# ------------------------------------------- capacity changed in the UI --

class ReusedOrdinalKeepsItsUiCapacity(unittest.TestCase):
    """A reserved ordinal comes back with the capacity set on it in the UI;
    only a never-seen ordinal starts with MaxParallelAnalysisPerNode (CAP)."""

    BUSY = [node(0, 2), node(1, 2)]

    def test_higher_ui_capacity_needs_fewer_nodes(self):
        # 6 unservable: core-2 brings 6 back, not the 3 nodes 6/CAP would give.
        d = decide(queue(6, self.BUSY), replicas=2, reserved=[2],
                   known={2: 6})
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 3))
        self.assertEqual((d.reserve_ordinals, d.reused), ([], [2]))

    def test_lower_ui_capacity_needs_more_nodes(self):
        # 4 unservable: core-2 brings 1, then two new nodes at CAP.
        d = decide(queue(4, self.BUSY), replicas=2, reserved=[2],
                   known={2: 1})
        self.assertEqual((d.action, d.desired_replicas), ("scale-up", 5))

    def test_largest_reserved_capacity_is_reused_first(self):
        d = decide(queue(4, self.BUSY), replicas=2, reserved=[2, 3],
                   known={3: 4})
        self.assertEqual(d.desired_replicas, 3)
        self.assertEqual((d.reserve_ordinals, d.reused), ([2], [3]))

    def test_min_nodes_reuses_the_largest_reserved_first(self):
        d = decide(queue(0, [node(0, 0)]), replicas=1, reserved=[1, 2],
                   min_nodes=2, known={2: 4})
        self.assertEqual((d.desired_replicas, d.reserve_ordinals), (2, [1]))

    def test_capacity_below_one_is_never_recorded(self):
        # The UI does not allow it: such a value is noise, not a setting.
        doc = queue(0, [node(0, 0, capacity=0)])
        self.assertEqual(
            autoscaler.observe_capacity({0: 3}, doc, [host(0)], CAP), {0: 3})
        self.assertEqual(
            autoscaler._parse_capacity_annotation('{"1": 0, "2": 5}'), {2: 5})

    def test_observe_keeps_only_values_that_differ_from_helm(self):
        doc = queue(0, [node(0, 0, capacity=CAP), node(1, 0, capacity=5)])
        live = [host(0), host(1)]
        # core-0 was 4 in the UI and has been set back to the Helm value.
        self.assertEqual(
            autoscaler.observe_capacity({0: 4, 3: 1}, doc, live, CAP),
            {1: 5, 3: 1})  # core-3, reserved, keeps what was last seen

    def test_observe_ignores_ghosts(self):
        doc = queue(0, [node(0, 0, capacity=5)])
        self.assertEqual(
            autoscaler.observe_capacity({}, doc, [host(1)], CAP), {})

    def test_bad_annotation_is_ignored(self):
        self.assertEqual(autoscaler._parse_capacity_annotation("not json"), {})
        self.assertEqual(autoscaler._parse_capacity_annotation(None), {})
        self.assertEqual(
            autoscaler._parse_capacity_annotation('{"2": 6}'), {2: 6})


class UiCapacitySurvivesAutoscalerRestart(unittest.TestCase):
    """Once reserved, a node is listed nowhere: its UI capacity is recorded on
    the StatefulSet when it is removed, and read back by a new controller."""

    def make_controller(self):
        cfg = autoscaler.Config(
            namespace="ns", sts_name="console-analysis-node-core",
            pod_selector="x", queue_status_url="http://unused",
            min_nodes=1, max_nodes=5, poll_interval=30,
            up_window=60, down_window=120,
            dry_run=False, once=False, run_for=0,
        )
        ctl = autoscaler.Controller(cfg, self.kube)
        ctl.fetch_queue_status = lambda: self.docs.pop(0)
        return ctl

    def setUp(self) -> None:
        self.kube = FakeKube(replicas=2, reserved=[])
        self.docs: list[dict] = []
        self.clock = Clock()
        for p in (mock.patch.object(autoscaler.time, "monotonic", self.clock),
                  mock.patch("builtins.print")):
            p.start()
            self.addCleanup(p.stop)

    def tick_at(self, ctl, seconds: float, *docs: dict) -> None:
        self.docs.extend(docs)
        self.clock.now = 1000.0 + seconds
        ctl.tick()

    def test_removed_node_comes_back_with_its_ui_capacity(self):
        ctl = self.make_controller()
        # Both set in the UI. The smaller one (core-1 at 3) is removed, and
        # its 3 is recorded alongside core-0's 6.
        idle = queue(0, [node(0, 0, capacity=6), node(1, 0, capacity=3)])
        self.tick_at(ctl, 0, idle)
        self.tick_at(ctl, 120, idle, idle)
        self.assertEqual(self.kube.reserved, [1])
        self.assertEqual(
            self.kube.annotations[autoscaler.CAPACITY_ANNOTATION],
            '{"0": 6, "1": 3}')

    def test_new_controller_reads_the_annotation(self):
        self.kube = FakeKube(replicas=1, reserved=[1])
        self.kube.annotations[autoscaler.CAPACITY_ANNOTATION] = '{"1": 6}'
        ctl = self.make_controller()
        busy = queue(6, [node(0, 2)])
        self.tick_at(ctl, 0, busy)
        self.tick_at(ctl, 60, busy)
        # core-1 brings 6 back: one node, not the three 6/CAP would give.
        self.assertEqual((self.kube.replicas, self.kube.reserved), (2, []))


# ----------------------------------------------------------------------- log --

class NodesLogLine(unittest.TestCase):

    def test_shows_live_capacity_per_node(self):
        # Capacity changed in the UI: 4 on core-0, 1 on core-1.
        doc = queue(0, [node(0, 3, capacity=4), node(1, 0, capacity=1)])
        self.assertEqual(autoscaler._fmt_nodes(doc), "0:3/4 1:0/1")

    def test_non_numeric_hostname_is_shown_whole(self):
        doc = queue(0, [{"hostname": "other", "jobsInProgress": 0,
                         "capacity": 2}])
        self.assertEqual(autoscaler._fmt_nodes(doc), "other:0/2")

    def test_never_raises_on_bad_data(self):
        self.assertEqual(autoscaler._fmt_nodes("not json"), "?")
        self.assertEqual(autoscaler._fmt_nodes({"nodes": None}), "?")
        self.assertEqual(autoscaler._fmt_nodes({"nodes": [42, {}]}), "? ?:?/?")


if __name__ == "__main__":
    unittest.main(verbosity=2)
