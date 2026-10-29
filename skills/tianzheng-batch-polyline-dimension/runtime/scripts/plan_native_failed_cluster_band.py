#!/usr/bin/env python3
"""Promote only the residual contiguous native-dimension clusters one band.

This is the final normal-layout fallback after native text-state selection and
grip-4 along-source relief.  Passed annotations stay frozen.  Each remaining
contiguous cluster moves its native dimension-line grip 0 by the versioned
adjacent-band increment on its current source side; source association grips
2/3 are never changed.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from annotation_layout_formula import load_vector_layout_formula


def rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def unit(dx: float, dy: float) -> tuple[float, float]:
    length = math.hypot(dx, dy)
    if length <= 1.0e-9:
        raise ValueError("zero-length cluster band direction")
    return dx / length, dy / length


def circle_center(
    start: tuple[float, float],
    mid: tuple[float, float],
    end: tuple[float, float],
) -> tuple[float, float]:
    # Work in a local frame because production drawings use large survey
    # coordinates; the translated determinant avoids catastrophic cancellation.
    ax, ay = 0.0, 0.0
    bx, by = mid[0] - start[0], mid[1] - start[1]
    cx, cy = end[0] - start[0], end[1] - start[1]
    determinant = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(determinant) <= 1.0e-9:
        raise ValueError("arc points are collinear")
    a2, b2, c2 = 0.0, bx * bx + by * by, cx * cx + cy * cy
    ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / determinant
    uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / determinant
    return start[0] + ux, start[1] + uy


def contiguous_clusters(items: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    ordered = sorted(items)
    clusters: list[list[tuple[int, str]]] = []
    for item in ordered:
        if not clusters or item[0] != clusters[-1][-1][0] + 1:
            clusters.append([item])
        else:
            clusters[-1].append(item)
    return clusters


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--failed-audit", required=True, type=Path)
    parser.add_argument("--association-plan", required=True, type=Path)
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--formula", required=True, type=Path)
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    args = parser.parse_args()

    failed_payload = json.loads(args.failed_audit.read_text(encoding="utf-8"))
    failed = {str(handle).strip().upper() for handle in failed_payload.get("failed_subset", [])}
    association: dict[str, tuple[str, int]] = {}
    for row in rows(args.association_plan):
        handle = row["NATIVE_HANDLE"].strip().upper()
        source, segment = row["SOURCE_SEGMENT"].strip().upper().split(":", 1)
        association[handle] = (source, int(segment))
    geometry = {
        (row["SOURCE_HANDLE"].strip().upper(), int(row["SEGMENT_INDEX"])): row
        for row in rows(args.geometry)
    }
    grip0 = {
        row["HANDLE"].strip().upper(): (float(row["GRIP_X"]), float(row["GRIP_Y"]))
        for row in rows(args.grips)
        if int(row["GRIP_INDEX"]) == 0
    }
    heights = {
        row["SOURCE_HANDLE"].strip().upper(): float(row.get("HEIGHT", "0") or 0.0)
        for row in rows(args.text_bboxes)
    }
    missing = sorted(handle for handle in failed if handle not in association or handle not in grip0 or handle not in heights)
    if missing:
        raise SystemExit(f"cluster band inputs missing handles: {missing}")

    formula = load_vector_layout_formula(args.formula)
    increment_h = formula.endpoint_cluster.next_band_increment_h
    by_source: dict[str, list[tuple[int, str]]] = {}
    for handle in failed:
        source, segment = association[handle]
        by_source.setdefault(source, []).append((segment, handle))

    moves: list[dict[str, object]] = []
    cluster_audit: list[dict[str, object]] = []
    for source in sorted(by_source):
        for cluster_index, cluster in enumerate(contiguous_clusters(by_source[source]), start=1):
            cluster_id = f"{source}:C{cluster_index}"
            for segment, handle in cluster:
                row = geometry[(source, segment)]
                start = (float(row["START_X"]), float(row["START_Y"]))
                mid = (float(row["MID_X"]), float(row["MID_Y"]))
                end = (float(row["END_X"]), float(row["END_Y"]))
                current = grip0[handle]
                if row["SEGMENT_TYPE"].strip().upper() == "LINE":
                    source_mid = mid
                    direction = unit(current[0] - source_mid[0], current[1] - source_mid[1])
                else:
                    center = circle_center(start, mid, end)
                    source_radius = math.hypot(mid[0] - center[0], mid[1] - center[1])
                    radial = unit(current[0] - center[0], current[1] - center[1])
                    current_radius = math.hypot(current[0] - center[0], current[1] - center[1])
                    side = 1.0 if current_radius >= source_radius else -1.0
                    direction = radial[0] * side, radial[1] * side
                distance = increment_h * heights[handle]
                moves.append(
                    {
                        "HANDLE": handle,
                        "GRIP_INDEX": 0,
                        "DX": direction[0] * distance,
                        "DY": direction[1] * distance,
                        "DZ": 0.0,
                        "CLUSTER": cluster_id,
                    }
                )
            cluster_audit.append(
                {
                    "cluster": cluster_id,
                    "source": source,
                    "segments": [segment for segment, _handle in cluster],
                    "handles": [handle for _segment, handle in cluster],
                    "member_count": len(cluster),
                    "singleton_last_resort": len(cluster) == 1,
                }
            )

    args.output_plan.parent.mkdir(parents=True, exist_ok=True)
    with args.output_plan.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=("HANDLE", "GRIP_INDEX", "DX", "DY", "DZ", "CLUSTER"),
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(moves)
    payload = {
        "status": "PASS",
        "failed_input_count": len(failed),
        "move_count": len(moves),
        "cluster_count": len(cluster_audit),
        "singleton_last_resort_count": sum(item["singleton_last_resort"] for item in cluster_audit),
        "increment_h": increment_h,
        "grip_index": 0,
        "frozen_source_association_grips": [2, 3],
        "clusters": cluster_audit,
    }
    args.output_audit.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
