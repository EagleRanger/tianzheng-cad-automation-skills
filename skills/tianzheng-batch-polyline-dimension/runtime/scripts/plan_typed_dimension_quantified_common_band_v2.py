#!/usr/bin/env python3
"""V2 common-band planner with deterministic exterior for open source paths.

Closed paths keep the established topology-exterior rule.  An open path is
temporarily closed by its endpoint chord only for side classification.  This
turns the user's visual idea of the path's exterior into a deterministic
path-level rule while leaving source geometry untouched.  Degenerate virtual
closures stop planning instead of falling back to the native creation side.
"""

from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

import plan_typed_dimension_quantified_common_band as base


_native_source_polygon = base.source_polygon


def _argument_path(flag: str) -> Path:
    try:
        return Path(sys.argv[sys.argv.index(flag) + 1])
    except (ValueError, IndexError) as exc:
        raise SystemExit(f"missing required argument {flag}") from exc


def _virtual_closure_metadata(rows: list[dict[str, str]]) -> dict[str, object]:
    points, native_closed = _native_source_polygon(rows)
    if native_closed:
        return {
            "points": points,
            "native_closed": True,
            "planning_closed": True,
            "policy": "NATIVE_CLOSED_TOPOLOGY_EXTERIOR",
            "gap": 0.0,
            "area": base.polygon_signed_area(points),
        }
    if len(points) < 3:
        raise ValueError("open source has too few sampled points for virtual closure")
    gap = math.dist(points[0], points[-1])
    area = base.polygon_signed_area(points)
    span_x = max(point[0] for point in points) - min(point[0] for point in points)
    span_y = max(point[1] for point in points) - min(point[1] for point in points)
    scale = max(span_x, span_y, gap, 1.0)
    if gap <= 1.0e-5 or abs(area) <= 1.0e-8 * scale * scale:
        raise ValueError("open source virtual closure is degenerate")
    return {
        "points": points,
        "native_closed": False,
        "planning_closed": True,
        "policy": "OPEN_PATH_ENDPOINT_CHORD_VIRTUAL_EXTERIOR",
        "gap": gap,
        "area": area,
    }


def source_polygon_for_exterior(rows: list[dict[str, str]]):
    metadata = _virtual_closure_metadata(rows)
    return metadata["points"], bool(metadata["planning_closed"])


def _source_metadata(geometry_path: Path) -> dict[str, dict[str, object]]:
    rows = base.read_tsv(geometry_path)
    by_source: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        if row["SEGMENT_TYPE"].upper() in {"ARC", "LINE"}:
            by_source.setdefault(row["SOURCE_HANDLE"].upper(), []).append(row)
    return {source: _virtual_closure_metadata(source_rows) for source, source_rows in by_source.items()}


def _rewrite_outputs(audit_path: Path, summary_path: Path, metadata) -> None:
    with audit_path.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    fields = list(rows[0]) + ["SIDE_POLICY", "VIRTUAL_CLOSURE_GAP", "VIRTUAL_CLOSURE_AREA"]
    for row in rows:
        item = metadata[row["SOURCE_HANDLE"].upper()]
        row["SOURCE_PATH_CLOSED"] = str(item["native_closed"]).upper()
        row["SIDE_POLICY"] = str(item["policy"])
        row["VIRTUAL_CLOSURE_GAP"] = f"{float(item['gap']):.12g}"
        row["VIRTUAL_CLOSURE_AREA"] = f"{float(item['area']):.12g}"
    base.write_tsv(audit_path, rows, tuple(fields))

    payload = json.loads(summary_path.read_text(encoding="utf-8"))
    for source, item in metadata.items():
        payload["source_bands"][source]["closed"] = bool(item["native_closed"])
        payload["source_bands"][source]["side_policy"] = item["policy"]
        payload["source_bands"][source]["virtual_closure_gap"] = item["gap"]
        payload["source_bands"][source]["virtual_closure_area"] = item["area"]
    payload["open_path_side_policy"] = "ENDPOINT_CHORD_VIRTUAL_EXTERIOR__NO_NATIVE_SIDE_FALLBACK"
    summary_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    geometry_path = _argument_path("--geometry")
    audit_path = _argument_path("--output-audit")
    summary_path = _argument_path("--output-summary")
    metadata = _source_metadata(geometry_path)
    base.source_polygon = source_polygon_for_exterior
    result = base.main()
    _rewrite_outputs(audit_path, summary_path, metadata)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
