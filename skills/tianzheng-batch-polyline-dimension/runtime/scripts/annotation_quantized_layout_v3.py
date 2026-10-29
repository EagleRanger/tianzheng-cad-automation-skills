"""Small, drawing-independent rules for quantified native dimension layout.

The module deliberately contains no drawing handles or coordinates.  It turns
the user's visual rules into H-normalised decisions that can be reused by the
CAD-side batch:

* all ordinary dimensions on one source path share the smallest hard-pass band;
* a side change applies to the whole local cluster, never one isolated label;
* a sharp endpoint cluster stays on one side and one band, escalating only
  when the closer band has a measured hard collision.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SideSelectionRule:
    closed_path_default: str
    closed_path_inside_switch_forbidden: bool
    open_path_default: str
    switch_scope: str
    isolated_switch_allowed: bool
    opposite_side_minimum_advantage_h: float
    opposite_side_requires_hard_pass: bool


@dataclass(frozen=True)
class SharpClusterRule:
    activation: str
    common_side_required: bool
    common_band_required: bool
    common_band_tolerance_h: float
    text_text_hard_gap_h: float
    next_band_increment_h: float
    maximum_band_rank: int
    bounded_stagger_allowed_after_shared_band_exhausted: bool
    max_stagger_span_h: float
    fallback_order: tuple[str, ...]


@dataclass(frozen=True)
class RuntimeQuantizedLayout:
    status: str
    ordinary_common_band_tolerance_h: float
    reference_policy: str
    side: SideSelectionRule
    sharp_cluster: SharpClusterRule


def load_runtime_quantized_layout(path: Path) -> RuntimeQuantizedLayout:
    payload = json.loads(path.read_text(encoding="utf-8"))
    runtime = payload["runtime_quantized_layout"]
    side = runtime["side_selection"]
    sharp = runtime["sharp_endpoint_cluster"]
    result = RuntimeQuantizedLayout(
        status=str(runtime["status"]),
        ordinary_common_band_tolerance_h=float(
            runtime["ordinary_common_band_tolerance_h"]
        ),
        reference_policy=str(runtime["reference_policy"]),
        side=SideSelectionRule(
            closed_path_default=str(side["closed_path_default"]),
            closed_path_inside_switch_forbidden=bool(
                side["closed_path_inside_switch_forbidden"]
            ),
            open_path_default=str(side["open_path_default"]),
            switch_scope=str(side["switch_scope"]),
            isolated_switch_allowed=bool(side["isolated_switch_allowed"]),
            opposite_side_minimum_advantage_h=float(
                side["opposite_side_minimum_advantage_h"]
            ),
            opposite_side_requires_hard_pass=bool(
                side["opposite_side_requires_hard_pass"]
            ),
        ),
        sharp_cluster=SharpClusterRule(
            activation=str(sharp["activation"]),
            common_side_required=bool(sharp["common_side_required"]),
            common_band_required=bool(sharp["common_band_required"]),
            common_band_tolerance_h=float(sharp["common_band_tolerance_h"]),
            text_text_hard_gap_h=float(sharp["text_text_hard_gap_h"]),
            next_band_increment_h=float(sharp["next_band_increment_h"]),
            maximum_band_rank=int(sharp["maximum_band_rank"]),
            bounded_stagger_allowed_after_shared_band_exhausted=bool(
                sharp["bounded_stagger_allowed_after_shared_band_exhausted"]
            ),
            max_stagger_span_h=float(sharp["max_stagger_span_h"]),
            fallback_order=tuple(str(item) for item in sharp["fallback_order"]),
        ),
    )
    if result.status not in {"validation_only", "active_validation"}:
        raise ValueError("runtime quantified layout has unsupported status")
    if not 0.0 <= result.ordinary_common_band_tolerance_h <= 0.05:
        raise ValueError("ordinary common-band tolerance must be at most 0.05H")
    if result.reference_policy != "smallest_zero_hard_collision_band":
        raise ValueError("unsupported common-band reference policy")
    if result.side.closed_path_default != "topology_exterior":
        raise ValueError("closed paths must default to topology exterior")
    if not result.side.closed_path_inside_switch_forbidden:
        raise ValueError("closed paths must never switch to topology interior")
    if result.side.switch_scope != "whole_contiguous_cluster":
        raise ValueError("side switching must be cluster-wide")
    if result.side.isolated_switch_allowed:
        raise ValueError("isolated side switching is forbidden")
    if result.side.opposite_side_minimum_advantage_h < 0.0:
        raise ValueError("side advantage cannot be negative")
    if not result.sharp_cluster.common_side_required:
        raise ValueError("sharp clusters require one common side")
    if not result.sharp_cluster.common_band_required:
        raise ValueError("sharp clusters require one common band")
    if result.sharp_cluster.common_band_tolerance_h > 0.05:
        raise ValueError("sharp common-band tolerance must be at most 0.05H")
    if result.sharp_cluster.next_band_increment_h <= 0.0:
        raise ValueError("sharp band increment must be positive")
    if result.sharp_cluster.maximum_band_rank < 1:
        raise ValueError("sharp cluster needs at least one fallback band")
    if result.sharp_cluster.max_stagger_span_h < result.sharp_cluster.next_band_increment_h:
        raise ValueError("sharp stagger span must allow at least one adjacent band")
    return result


def choose_cluster_side(
    *,
    default_side: int,
    default_clearance_h: float,
    opposite_clearance_h: float,
    required_clearance_h: float,
    closed_path: bool,
    rule: SideSelectionRule,
) -> tuple[int, str]:
    """Choose one side for a whole cluster with a deterministic wide-side rule."""

    if default_side not in (-1, 1):
        raise ValueError("default_side must be -1 or 1")
    if min(default_clearance_h, opposite_clearance_h, required_clearance_h) < 0.0:
        raise ValueError("clearances cannot be negative")
    if closed_path:
        return default_side, "CLOSED_TOPOLOGY_EXTERIOR"
    opposite_passes = opposite_clearance_h >= required_clearance_h
    advantage = opposite_clearance_h - default_clearance_h
    if (
        opposite_passes
        and advantage >= rule.opposite_side_minimum_advantage_h
        and (not rule.opposite_side_requires_hard_pass or opposite_passes)
    ):
        return -default_side, "WHOLE_CLUSTER_WIDER_OPPOSITE_SIDE"
    return default_side, "KEEP_DEFAULT_COMMON_SIDE"


def choose_cluster_band_h(
    *,
    base_band_h: float,
    candidate_bands_h: tuple[float, ...],
    hard_collision_count_by_band: dict[float, int],
    rule: SharpClusterRule,
) -> tuple[float | None, str]:
    """Return the nearest collision-free common band for one endpoint cluster."""

    if base_band_h <= 0.0:
        raise ValueError("base band must be positive")
    ordered = tuple(
        band
        for band in sorted(set(candidate_bands_h))
        if band + 1.0e-9 >= base_band_h
    )
    permitted = ordered[: rule.maximum_band_rank + 1]
    for rank, band in enumerate(permitted):
        if hard_collision_count_by_band.get(band, 0) == 0:
            reason = "SHARED_BASE_BAND" if rank == 0 else "SHARED_NEXT_BAND_AFTER_HARD_COLLISION"
            return band, reason
    return None, "SHARP_CLUSTER_NEEDS_MANUAL_REVIEW"
