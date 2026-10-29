#!/usr/bin/env python3
"""Compose ordinary common-band targets with sharp-cluster band escalation.

Input is the drawing's real segment inventory, native mapping, grip-0 inventory,
text boxes, and the already computed ordinary common-band audit.  Output is one
final grip-0 plan.  Ordinary items retain exactly the common path band.  Only a
contiguous short-arc endpoint cluster may move to the next shared band, and only
when its forecast text boxes have a hard collision on the nearer band.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
from pathlib import Path

from annotation_quantized_layout_v3 import (
    choose_cluster_band_h,
    load_runtime_quantized_layout,
)
from plan_typed_dimension_quantified_common_band import (
    circle_through,
    read_tsv,
    signed_sweep_through,
    source_polygon,
    write_tsv,
)


ROOT = Path(__file__).resolve().parents[1]


def text_box(row: dict[str, str]) -> tuple[float, float, float, float]:
    return tuple(float(row[key]) for key in ("MIN_X", "MIN_Y", "MAX_X", "MAX_Y"))


def measured_height(row: dict[str, str]) -> float:
    value = row.get("TEXT_HEIGHT", "") or row.get("HEIGHT", "")
    if not value:
        raise ValueError(f"{row.get('SOURCE_HANDLE','')}: native text height missing")
    height = float(value)
    if height <= 0.0:
        raise ValueError("native text height must be positive")
    return height


def move_box(box, dx: float, dy: float):
    return box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy


def expand_box(box, value: float):
    return box[0] - value, box[1] - value, box[2] + value, box[3] + value


def overlaps(first, second) -> bool:
    return not (
        first[2] < second[0]
        or second[2] < first[0]
        or first[3] < second[1]
        or second[3] < first[1]
    )


def arc_geometry(row: dict[str, str]):
    start = float(row["START_X"]), float(row["START_Y"])
    mid = float(row["MID_X"]), float(row["MID_Y"])
    end = float(row["END_X"]), float(row["END_Y"])
    center, radius = circle_through(start, mid, end)
    angles = tuple(
        math.atan2(point[1] - center[1], point[0] - center[0])
        for point in (start, mid, end)
    )
    sweep = signed_sweep_through(*angles)
    return center, radius, abs(radius * sweep)


def short_arc(row: dict[str, str], height: float) -> bool:
    if row["SEGMENT_TYPE"].upper() != "ARC":
        return False
    _center, radius, length = arc_geometry(row)
    return length < 2.5 * height or radius < 2.5 * height


def contiguous_short_clusters(rows: list[dict[str, str]], height: float):
    ordered = sorted(rows, key=lambda row: int(row["SEGMENT_INDEX"]))
    flags = [short_arc(row, height) for row in ordered]
    clusters: list[list[dict[str, str]]] = []
    current: list[dict[str, str]] = []
    for row, is_short in zip(ordered, flags):
        if is_short:
            current.append(row)
        elif current:
            if len(current) >= 2:
                clusters.append(current)
            current = []
    if current and len(current) >= 2:
        clusters.append(current)

    _points, closed = source_polygon(rows)
    if closed and len(clusters) >= 2:
        first_index = int(clusters[0][0]["SEGMENT_INDEX"])
        last_index = int(clusters[-1][-1]["SEGMENT_INDEX"])
        if first_index == int(ordered[0]["SEGMENT_INDEX"]) and last_index == int(ordered[-1]["SEGMENT_INDEX"]):
            merged = clusters[-1] + clusters[0]
            clusters = [merged] + clusters[1:-1]
    return clusters


def forecast_move(row, grip0, box, target_signed):
    """Forecast the text box with the same reachable axis used by grip 0."""

    del box  # The native dimension follows grip 0; bbox direction is not an actuator.
    return grip_axis_move(row, grip0, target_signed)

def grip_axis_move(row, grip0, target_signed):
    """Return the reachable grip-0 move on the native radial/normal axis."""

    start = float(row["START_X"]), float(row["START_Y"])
    mid = float(row["MID_X"]), float(row["MID_Y"])
    end = float(row["END_X"]), float(row["END_Y"])
    if row["SEGMENT_TYPE"].upper() == "ARC":
        center, radius, _length = arc_geometry(row)
        gx, gy = grip0
        vector = gx - center[0], gy - center[1]
        current_radius = math.hypot(*vector)
        if current_radius <= 1.0e-9:
            raise ValueError("arc grip0 lies on centre")
        current_signed = current_radius - radius
        delta = target_signed - current_signed
        ux, uy = vector[0] / current_radius, vector[1] / current_radius
        return current_signed, delta, ux * delta, uy * delta
    tangent = end[0] - start[0], end[1] - start[1]
    length = math.hypot(*tangent)
    if length <= 1.0e-9:
        raise ValueError("degenerate line segment")
    normal = -tangent[1] / length, tangent[0] / length
    current_signed = (grip0[0] - mid[0]) * normal[0] + (grip0[1] - mid[1]) * normal[1]
    delta = target_signed - current_signed
    return current_signed, delta, normal[0] * delta, normal[1] * delta


def signed_cluster_target(
    base_signed: float, side_multiplier: int, absolute_band: float
) -> float:
    """Keep every segment's topology side; flip only the whole cluster."""

    if side_multiplier not in (-1, 1):
        raise ValueError("side multiplier must be -1 or 1")
    if absolute_band <= 0.0:
        raise ValueError("absolute band must be positive")
    base_side = 1.0 if base_signed >= 0.0 else -1.0
    return base_side * side_multiplier * absolute_band


def collision_components(keys, boxes):
    """Return connected groups of native text boxes with hard overlap."""

    adjacency = {key: set() for key in keys}
    for index, first in enumerate(keys):
        for second in keys[index + 1 :]:
            if overlaps(boxes[first], boxes[second]):
                adjacency[first].add(second)
                adjacency[second].add(first)
    result = []
    visited = set()
    for key in keys:
        if key in visited or not adjacency[key]:
            continue
        stack = [key]
        component = set()
        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            component.add(current)
            stack.extend(adjacency[current] - visited)
        if len(component) >= 2:
            result.append(component)
    return result


def merge_cluster_sets(groups):
    merged = []
    for group in (set(item) for item in groups if len(item) >= 2):
        touching = [existing for existing in merged if existing & group]
        if not touching:
            merged.append(group)
            continue
        combined = set(group)
        for existing in touching:
            combined.update(existing)
            merged.remove(existing)
        merged.append(combined)
    return merged


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--common-band-audit", required=True, type=Path)
    parser.add_argument(
        "--formula",
        type=Path,
        default=ROOT / "config" / "annotation_quantized_layout_formula_v3.json",
    )
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()

    formula = load_runtime_quantized_layout(args.formula)
    formula_json = json.loads(args.formula.read_text(encoding="utf-8"))
    bands = tuple(
        float(value)
        for value in formula_json["runtime_quantized_layout"]["base_band"]["candidate_bands_h"]
    )
    geometry_rows = [
        row for row in read_tsv(args.geometry)
        if row["SEGMENT_TYPE"].upper() in {"ARC", "LINE"}
    ]
    geometry = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in geometry_rows
    }
    mapping = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row["NATIVE_HANDLE"].upper()
        for row in read_tsv(args.mapping)
        if row.get("STATUS", "").upper() == "PASS"
    }
    if set(geometry) != set(mapping):
        raise SystemExit(f"geometry/mapping mismatch: {sorted(set(geometry) ^ set(mapping))}")
    handles = set(mapping.values())
    grips = {
        row["HANDLE"].upper(): (float(row["GRIP_X"]), float(row["GRIP_Y"]))
        for row in read_tsv(args.grips)
        if row["HANDLE"].upper() in handles and int(row["GRIP_INDEX"]) == 0
    }
    bbox_rows = {
        row["SOURCE_HANDLE"].upper(): row
        for row in read_tsv(args.text_bboxes)
        if row["SOURCE_HANDLE"].upper() in handles
    }
    common = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in read_tsv(args.common_band_audit)
    }
    missing = handles - set(grips) | handles - set(bbox_rows)
    if missing:
        raise SystemExit(f"missing native grip or text box: {sorted(missing)}")
    if set(common) != set(geometry):
        raise SystemExit("common-band audit does not cover exact geometry")

    rows_by_source: dict[str, list[dict[str, str]]] = {}
    for row in geometry_rows:
        rows_by_source.setdefault(row["SOURCE_HANDLE"].upper(), []).append(row)

    final_signed = {
        key: float(common[key]["TARGET_SIGNED_BAND"])
        for key in geometry
    }
    reasons = {key: "ORDINARY_SHARED_COMMON_BAND" for key in geometry}
    cluster_ids = {key: "" for key in geometry}
    unresolved: list[str] = []

    collision_before_by_key = {key: 0 for key in geometry}
    collision_after_by_key = {key: 0 for key in geometry}
    side_multiplier_by_key = {key: 1 for key in geometry}

    for source, source_rows in rows_by_source.items():
        source_keys = sorted(
            ((source, int(row["SEGMENT_INDEX"])) for row in source_rows),
            key=lambda key: key[1],
        )
        source_handles = [mapping[key] for key in source_keys]
        reference_height = max(measured_height(bbox_rows[handle]) for handle in source_handles)
        base_band_h = max(abs(final_signed[key]) for key in source_keys) / reference_height
        padding = 0.5 * formula.sharp_cluster.text_text_hard_gap_h * reference_height

        def forecast_box(key, target_signed):
            row = geometry[key]
            handle = mapping[key]
            box = text_box(bbox_rows[handle])
            _current, _delta, dx, dy = forecast_move(
                row, grips[handle], box, target_signed
            )
            return expand_box(move_box(box, dx, dy), padding)

        base_boxes = {
            key: forecast_box(key, final_signed[key])
            for key in source_keys
        }
        short_groups = [
            {(source, int(row["SEGMENT_INDEX"])) for row in cluster}
            for cluster in contiguous_short_clusters(source_rows, reference_height)
        ]
        collision_groups = collision_components(source_keys, base_boxes)
        clusters = merge_cluster_sets(short_groups + collision_groups)
        _polygon, closed_source = source_polygon(source_rows)

        for cluster_index, key_set in enumerate(
            sorted(clusters, key=lambda group: min(key[1] for key in group)),
            start=1,
        ):
            keys = sorted(key_set, key=lambda key: key[1])
            cluster_id = f"{source}:SHARP:{cluster_index}"
            context_keys = [key for key in source_keys if key not in key_set]

            def collision_count_targets(target_signed_by_key):
                candidate_boxes = {
                    key: forecast_box(key, target_signed_by_key[key])
                    for key in keys
                }
                count = sum(
                    1
                    for index, first_key in enumerate(keys)
                    for second_key in keys[index + 1 :]
                    if overlaps(candidate_boxes[first_key], candidate_boxes[second_key])
                )
                count += sum(
                    1
                    for key in keys
                    for context_key in context_keys
                    if overlaps(candidate_boxes[key], base_boxes[context_key])
                )
                return count

            def collision_count(side_multiplier, band_h):
                return collision_count_targets({
                    key: signed_cluster_target(
                        final_signed[key],
                        side_multiplier,
                        band_h * reference_height,
                    )
                    for key in keys
                })
            default_counts = {
                band_h: collision_count(1, band_h)
                for band_h in bands
                if band_h + 1.0e-9 >= base_band_h
            }
            selected, reason = choose_cluster_band_h(
                base_band_h=base_band_h,
                candidate_bands_h=bands,
                hard_collision_count_by_band=default_counts,
                rule=formula.sharp_cluster,
            )
            side_multiplier = 1
            opposite_counts = {
                band_h: collision_count(-1, band_h)
                for band_h in bands
                if band_h + 1.0e-9 >= base_band_h
            }
            opposite_selected, _opposite_reason = choose_cluster_band_h(
                base_band_h=base_band_h,
                candidate_bands_h=bands,
                hard_collision_count_by_band=opposite_counts,
                rule=formula.sharp_cluster,
            )

            # A closed path keeps its topology exterior whenever that side has
            # a hard-pass band. Open paths may switch as one group when the
            # opposite side reaches a hard pass at least 0.5H sooner. If the
            # default side has no hard pass, the whole cluster may use the
            # opposite hard-pass side as the final bounded fallback.
            if not closed_source and opposite_selected is not None and (
                selected is None
                or selected - opposite_selected
                >= formula.side.opposite_side_minimum_advantage_h
            ):
                selected = opposite_selected
                side_multiplier = -1
                reason = "WHOLE_CLUSTER_WIDER_OPPOSITE_SIDE"

            staggered_targets = None
            if (
                selected is None
                and closed_source
                and formula.sharp_cluster.bounded_stagger_allowed_after_shared_band_exhausted
            ):
                outward_bands = tuple(
                    band_h
                    for band_h in bands
                    if band_h + 1.0e-9 >= base_band_h
                )
                candidates = []
                for band_tuple in itertools.product(outward_bands, repeat=len(keys)):
                    if len(set(band_tuple)) == 1:
                        continue
                    if max(band_tuple) - min(band_tuple) > formula.sharp_cluster.max_stagger_span_h + 1.0e-9:
                        continue
                    targets = {
                        key: signed_cluster_target(
                            final_signed[key], 1, band_h * reference_height
                        )
                        for key, band_h in zip(keys, band_tuple)
                    }
                    collision_total = collision_count_targets(targets)
                    score = (
                        collision_total,
                        max(band_tuple),
                        sum(band_tuple),
                        tuple(band_tuple),
                    )
                    candidates.append((score, targets, band_tuple))
                if candidates:
                    score, targets, band_tuple = min(candidates, key=lambda item: item[0])
                    if score[0] == 0:
                        staggered_targets = targets
                        selected = max(band_tuple)
                        side_multiplier = 1
                        reason = "SAME_SIDE_BOUNDED_ADJACENT_BAND_STAGGER"
            before_count = default_counts.get(base_band_h)
            if before_count is None:
                before_count = collision_count(1, base_band_h)
            if selected is None:
                unresolved.append(cluster_id)
                reason = "SHARP_CLUSTER_NEEDS_MANUAL_REVIEW"
                selected = base_band_h
                side_multiplier = 1
            after_count = (
                0
                if staggered_targets is not None
                else collision_count(side_multiplier, selected)
            )

            for key in keys:
                final_signed[key] = (
                    staggered_targets[key]
                    if staggered_targets is not None
                    else signed_cluster_target(
                        final_signed[key],
                        side_multiplier,
                        selected * reference_height,
                    )
                )
                reasons[key] = reason
                cluster_ids[key] = cluster_id
                collision_before_by_key[key] = before_count
                collision_after_by_key[key] = after_count
                side_multiplier_by_key[key] = side_multiplier

    plan = []
    audit = []
    for key in sorted(geometry):
        row = geometry[key]
        handle = mapping[key]
        current, delta, dx, dy = grip_axis_move(
            row, grips[handle], final_signed[key]
        )
        if abs(delta) > 1.0e-8:
            plan.append({
                "HANDLE": handle,
                "GRIP_INDEX": 0,
                "DX": dx,
                "DY": dy,
                "DZ": 0.0,
                "TARGET_SIGNED_BAND": final_signed[key],
            })
        height = measured_height(bbox_rows[handle])
        audit.append({
            "SOURCE_HANDLE": key[0],
            "SEGMENT_INDEX": key[1],
            "NATIVE_HANDLE": handle,
            "TEXT_HEIGHT": height,
            "CURRENT_SIGNED_BAND": current,
            "FINAL_SIGNED_BAND": final_signed[key],
            "FINAL_ABS_BAND_H": abs(final_signed[key]) / height,
            "CLUSTER_ID": cluster_ids[key],
            "REASON": reasons[key],
            "SIDE_MULTIPLIER": side_multiplier_by_key[key],
            "HARD_COLLISION_COUNT_BEFORE": collision_before_by_key[key],
            "HARD_COLLISION_COUNT_AFTER": collision_after_by_key[key],
            "DX": dx,
            "DY": dy,
        })

    write_tsv(args.output_plan, plan, ("HANDLE", "GRIP_INDEX", "DX", "DY", "DZ", "TARGET_SIGNED_BAND"))
    write_tsv(
        args.output_audit,
        audit,
        (
            "SOURCE_HANDLE", "SEGMENT_INDEX", "NATIVE_HANDLE", "TEXT_HEIGHT",
            "CURRENT_SIGNED_BAND", "FINAL_SIGNED_BAND", "FINAL_ABS_BAND_H",
            "CLUSTER_ID", "REASON", "SIDE_MULTIPLIER",
            "HARD_COLLISION_COUNT_BEFORE", "HARD_COLLISION_COUNT_AFTER",
            "DX", "DY",
        ),
    )
    summary = {
        "status": "PASS" if not unresolved else "PARTIAL_UNRESOLVED_SHARP_CLUSTERS",
        "formula_id": formula_json["formula_id"],
        "target_count": len(audit),
        "move_count": len(plan),
        "ordinary_common_band_tolerance_h": formula.ordinary_common_band_tolerance_h,
        "sharp_cluster_count": len({value for value in cluster_ids.values() if value}),
        "unresolved_sharp_clusters": unresolved,
        "mutable_grip_indexes": [0],
        "text_orientation_mutation_count": 0,
        "isolated_side_switch_count": 0,
        "whole_cluster_side_switch_count": len({
            cluster_ids[key]
            for key in geometry
            if cluster_ids[key] and side_multiplier_by_key[key] == -1
        }),
        "hard_collision_count_before": sum(
            collision_before_by_key[key]
            for key in geometry
            if cluster_ids[key]
        ),
        "hard_collision_count_after": sum(
            collision_after_by_key[key]
            for key in geometry
            if cluster_ids[key]
        ),
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
