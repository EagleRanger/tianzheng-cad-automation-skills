#!/usr/bin/env python3
"""Resolve one collision box and measured text height per mapped native dimension.

The primary evidence remains the reversible native text-explode audit.  Some
valid Tianzheng dimensions do not expose a separate text entity when exploded.
For those objects only, this resolver learns the text-grip index from the
successfully measured objects, derives text height from consistent peers, and
uses the live native object extents as a conservative collision proxy.

No drawing-specific handle, source id, coordinate, count, or bounding box is
embedded here.  Ambiguous grip semantics, inconsistent peer heights, or invalid
live extents stop planning instead of guessing.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path


BBOX_FIELDS = (
    "SOURCE_HANDLE",
    "TEXT_INDEX",
    "TEXT",
    "MIN_X",
    "MIN_Y",
    "MAX_X",
    "MAX_Y",
    "OBJECT_NAME",
    "HEIGHT",
    "TEXT_HEIGHT",
    "ROTATION",
    "RESOLUTION_METHOD",
    "HEIGHT_SOURCE",
    "PEER_COUNT",
    "TEXT_GRIP_INDEX",
)

AUDIT_FIELDS = (
    "SOURCE_HANDLE",
    "SOURCE_GEOMETRY_HANDLE",
    "STATUS",
    "RESOLUTION_METHOD",
    "HEIGHT",
    "HEIGHT_SOURCE",
    "PEER_COUNT",
    "PEER_RELATIVE_SPREAD",
    "TEXT_GRIP_INDEX",
    "DETAIL",
)


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, object]], fields: tuple[str, ...]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def positive_float(value: str | None) -> float | None:
    try:
        number = float(value or "")
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number > 0.0 else None


def finite_float(value: str | None) -> float | None:
    try:
        number = float(value or "")
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def measured_height(row: dict[str, str]) -> float | None:
    return positive_float(row.get("HEIGHT")) or positive_float(row.get("TEXT_HEIGHT"))


def direct_boxes(rows: list[dict[str, str]], wanted: set[str]) -> dict[str, dict[str, object]]:
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        handle = row.get("SOURCE_HANDLE", "").strip().upper()
        if handle in wanted:
            grouped[handle].append(row)
    result: dict[str, dict[str, object]] = {}
    for handle, items in grouped.items():
        valid = []
        for row in items:
            bounds = tuple(finite_float(row.get(key)) for key in ("MIN_X", "MIN_Y", "MAX_X", "MAX_Y"))
            height = measured_height(row)
            if height is None or any(value is None for value in bounds):
                continue
            min_x, min_y, max_x, max_y = bounds
            if max_x <= min_x or max_y <= min_y:
                continue
            valid.append((row, height, min_x, min_y, max_x, max_y))
        if not valid:
            continue
        heights = [item[1] for item in valid]
        result[handle] = {
            "SOURCE_HANDLE": handle,
            "TEXT_INDEX": "1",
            "TEXT": " | ".join(item[0].get("TEXT", "") for item in valid),
            "MIN_X": min(item[2] for item in valid),
            "MIN_Y": min(item[3] for item in valid),
            "MAX_X": max(item[4] for item in valid),
            "MAX_Y": max(item[5] for item in valid),
            "OBJECT_NAME": "+".join(sorted({item[0].get("OBJECT_NAME", "") for item in valid})),
            "HEIGHT": max(heights),
            "TEXT_HEIGHT": "",
            "ROTATION": valid[0][0].get("ROTATION", ""),
            "RESOLUTION_METHOD": "DIRECT_TEXT_EXPLODE",
            "HEIGHT_SOURCE": "DIRECT_NATIVE_TEXT",
            "PEER_COUNT": len(valid),
            "TEXT_GRIP_INDEX": "",
        }
    return result


def grips_by_handle(rows: list[dict[str, str]], wanted: set[str]) -> dict[str, list[dict[str, str]]]:
    result: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        handle = row.get("HANDLE", "").strip().upper()
        if handle in wanted:
            result[handle].append(row)
    return result


def learn_text_grip_index(
    direct: dict[str, dict[str, object]],
    grips: dict[str, list[dict[str, str]]],
    minimum_dominance: float,
    maximum_normalized_distance: float,
) -> tuple[int, int, float]:
    observations: list[tuple[int, float]] = []
    for handle, box in direct.items():
        center_x = (float(box["MIN_X"]) + float(box["MAX_X"])) * 0.5
        center_y = (float(box["MIN_Y"]) + float(box["MAX_Y"])) * 0.5
        height = float(box["HEIGHT"])
        candidates = []
        for row in grips.get(handle, []):
            x, y = finite_float(row.get("GRIP_X")), finite_float(row.get("GRIP_Y"))
            try:
                index = int(row.get("GRIP_INDEX", ""))
            except ValueError:
                continue
            if x is not None and y is not None:
                candidates.append((math.hypot(x - center_x, y - center_y), index))
        if candidates:
            distance, index = min(candidates)
            normalized = distance / height
            if normalized <= maximum_normalized_distance:
                observations.append((index, normalized))
    if not observations:
        raise ValueError("TEXT_GRIP_SEMANTICS_NOT_OBSERVED")
    counts = Counter(index for index, _distance in observations)
    index, count = counts.most_common(1)[0]
    dominance = count / len(observations)
    if dominance < minimum_dominance or list(counts.values()).count(count) != 1:
        raise ValueError("TEXT_GRIP_SEMANTICS_AMBIGUOUS")
    distances = [distance for observed_index, distance in observations if observed_index == index]
    return index, len(observations), max(distances)


def consensus_height(values: list[float], maximum_relative_spread: float) -> tuple[float, float] | None:
    if not values:
        return None
    center = statistics.median(values)
    spread = max(abs(value - center) for value in values) / center
    if spread > maximum_relative_spread:
        return None
    return center, spread


def proxy_from_live_extents(
    handle: str,
    rows: list[dict[str, str]],
    text_grip_index: int,
    height: float,
    height_source: str,
    peer_count: int,
) -> dict[str, object]:
    if not rows:
        raise ValueError("NATIVE_GRIPS_MISSING")
    first = rows[0]
    bounds = tuple(finite_float(first.get(key)) for key in ("EXTMIN_X", "EXTMIN_Y", "EXTMAX_X", "EXTMAX_Y"))
    if any(value is None for value in bounds):
        raise ValueError("NATIVE_EXTENTS_MISSING")
    min_x, min_y, max_x, max_y = bounds
    if max_x <= min_x or max_y <= min_y:
        raise ValueError("NATIVE_EXTENTS_INVALID")
    matches = [row for row in rows if int(row.get("GRIP_INDEX", "-1")) == text_grip_index]
    if len(matches) != 1:
        raise ValueError("LEARNED_TEXT_GRIP_NOT_UNIQUE")
    x, y = finite_float(matches[0].get("GRIP_X")), finite_float(matches[0].get("GRIP_Y"))
    if x is None or y is None:
        raise ValueError("LEARNED_TEXT_GRIP_COORDINATE_MISSING")
    tolerance = max(height * 1.0e-6, 1.0e-8)
    if not (min_x - tolerance <= x <= max_x + tolerance and min_y - tolerance <= y <= max_y + tolerance):
        raise ValueError("TEXT_GRIP_OUTSIDE_NATIVE_EXTENTS")
    return {
        "SOURCE_HANDLE": handle,
        "TEXT_INDEX": "1",
        "TEXT": "",
        "MIN_X": min_x,
        "MIN_Y": min_y,
        "MAX_X": max_x,
        "MAX_Y": max_y,
        "OBJECT_NAME": "NATIVE_OBJECT_EXTENTS_PROXY",
        "HEIGHT": height,
        "TEXT_HEIGHT": "",
        "ROTATION": "",
        "RESOLUTION_METHOD": "PEER_HEIGHT_NATIVE_EXTENTS_PROXY",
        "HEIGHT_SOURCE": height_source,
        "PEER_COUNT": peer_count,
        "TEXT_GRIP_INDEX": text_grip_index,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--output-bboxes", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    parser.add_argument("--maximum-peer-relative-spread", type=float, default=1.0e-6)
    parser.add_argument("--minimum-text-grip-dominance", type=float, default=0.90)
    parser.add_argument("--maximum-text-grip-normalized-distance", type=float, default=0.25)
    args = parser.parse_args()

    mapping_rows = [row for row in read_tsv(args.mapping) if row.get("STATUS", "").upper() == "PASS"]
    if not mapping_rows:
        raise SystemExit("PASS_MAPPING_EMPTY")
    handle_rows: dict[str, dict[str, str]] = {}
    for row in mapping_rows:
        handle = row.get("NATIVE_HANDLE", "").strip().upper()
        if not handle or handle in handle_rows:
            raise SystemExit("MAPPING_NATIVE_HANDLE_EMPTY_OR_DUPLICATE")
        handle_rows[handle] = row
    wanted = set(handle_rows)
    source_handles: dict[str, list[str]] = defaultdict(list)
    for handle, row in handle_rows.items():
        source_handles[row.get("SOURCE_HANDLE", "").strip().upper()].append(handle)

    direct = direct_boxes(read_tsv(args.text_bboxes), wanted)
    grip_rows = grips_by_handle(read_tsv(args.grips), wanted)
    try:
        text_grip_index, text_grip_observation_count, max_text_grip_distance = learn_text_grip_index(
            direct,
            grip_rows,
            args.minimum_text_grip_dominance,
            args.maximum_text_grip_normalized_distance,
        )
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    resolved = dict(direct)
    audit: list[dict[str, object]] = []
    unresolved: list[str] = []
    for handle in sorted(wanted):
        mapping = handle_rows[handle]
        source = mapping.get("SOURCE_HANDLE", "").strip().upper()
        if handle in direct:
            row = direct[handle]
            row["TEXT_GRIP_INDEX"] = text_grip_index
            audit.append({
                "SOURCE_HANDLE": handle,
                "SOURCE_GEOMETRY_HANDLE": source,
                "STATUS": "PASS",
                "RESOLUTION_METHOD": row["RESOLUTION_METHOD"],
                "HEIGHT": row["HEIGHT"],
                "HEIGHT_SOURCE": row["HEIGHT_SOURCE"],
                "PEER_COUNT": row["PEER_COUNT"],
                "PEER_RELATIVE_SPREAD": 0.0,
                "TEXT_GRIP_INDEX": text_grip_index,
                "DETAIL": "DIRECT_NATIVE_TEXT_BBOX",
            })
            continue

        same_source_values = [
            float(direct[peer]["HEIGHT"])
            for peer in source_handles[source]
            if peer in direct
        ]
        consensus = consensus_height(same_source_values, args.maximum_peer_relative_spread)
        height_source = "SAME_SOURCE_DIRECT_TEXT"
        peer_count = len(same_source_values)
        if consensus is None:
            layer = mapping.get("LAYER", "").strip().upper()
            object_name = mapping.get("OBJECT_NAME", "").strip().upper()
            same_class_values = [
                float(direct[peer]["HEIGHT"])
                for peer, peer_mapping in handle_rows.items()
                if peer in direct
                and peer_mapping.get("LAYER", "").strip().upper() == layer
                and peer_mapping.get("OBJECT_NAME", "").strip().upper() == object_name
            ]
            consensus = consensus_height(same_class_values, args.maximum_peer_relative_spread)
            height_source = "SAME_LAYER_OBJECT_CLASS_DIRECT_TEXT"
            peer_count = len(same_class_values)
        if consensus is None:
            unresolved.append(handle)
            audit.append({
                "SOURCE_HANDLE": handle,
                "SOURCE_GEOMETRY_HANDLE": source,
                "STATUS": "FAIL",
                "RESOLUTION_METHOD": "UNRESOLVED",
                "HEIGHT": "",
                "HEIGHT_SOURCE": "",
                "PEER_COUNT": peer_count,
                "PEER_RELATIVE_SPREAD": "",
                "TEXT_GRIP_INDEX": text_grip_index,
                "DETAIL": "NO_CONSISTENT_MEASURED_PEER_HEIGHT",
            })
            continue
        height, spread = consensus
        try:
            proxy = proxy_from_live_extents(
                handle,
                grip_rows.get(handle, []),
                text_grip_index,
                height,
                height_source,
                peer_count,
            )
        except ValueError as exc:
            unresolved.append(handle)
            audit.append({
                "SOURCE_HANDLE": handle,
                "SOURCE_GEOMETRY_HANDLE": source,
                "STATUS": "FAIL",
                "RESOLUTION_METHOD": "UNRESOLVED",
                "HEIGHT": height,
                "HEIGHT_SOURCE": height_source,
                "PEER_COUNT": peer_count,
                "PEER_RELATIVE_SPREAD": spread,
                "TEXT_GRIP_INDEX": text_grip_index,
                "DETAIL": str(exc),
            })
            continue
        resolved[handle] = proxy
        audit.append({
            "SOURCE_HANDLE": handle,
            "SOURCE_GEOMETRY_HANDLE": source,
            "STATUS": "PASS",
            "RESOLUTION_METHOD": proxy["RESOLUTION_METHOD"],
            "HEIGHT": height,
            "HEIGHT_SOURCE": height_source,
            "PEER_COUNT": peer_count,
            "PEER_RELATIVE_SPREAD": spread,
            "TEXT_GRIP_INDEX": text_grip_index,
            "DETAIL": "CONSERVATIVE_PROXY_FROM_LIVE_NATIVE_EXTENTS",
        })

    write_tsv(args.output_bboxes, [resolved[handle] for handle in sorted(resolved)], BBOX_FIELDS)
    write_tsv(args.output_audit, audit, AUDIT_FIELDS)
    summary = {
        "schema_version": 1,
        "status": "PASS" if not unresolved and len(resolved) == len(wanted) else "FAIL",
        "mapping_count": len(wanted),
        "direct_text_bbox_count": len(direct),
        "resolved_proxy_count": len(resolved) - len(direct),
        "resolved_total_count": len(resolved),
        "unresolved_count": len(unresolved),
        "unresolved_handles": unresolved,
        "learned_text_grip_index": text_grip_index,
        "text_grip_observation_count": text_grip_observation_count,
        "maximum_text_grip_normalized_distance": max_text_grip_distance,
        "peer_height_relative_spread_limit": args.maximum_peer_relative_spread,
        "policy": "DIRECT_TEXT_FIRST__CONSISTENT_PEER_HEIGHT__LIVE_NATIVE_EXTENTS_PROXY__FAIL_ON_AMBIGUITY",
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if summary["status"] != "PASS":
        raise SystemExit(f"TEXT_BBOX_RESOLUTION_FAILED:{unresolved}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
