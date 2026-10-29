#!/usr/bin/env python3
"""Fail before mutation when selected source segments already have native dimensions."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def point(row, x, y):
    return float(row[x]), float(row[y])


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def endpoint_error(g2, g3, start, end):
    return min(
        distance(g2, start) + distance(g3, end),
        distance(g2, end) + distance(g3, start),
    )


def audit(geometry_rows, grip_rows, tolerance):
    grips = {}
    types = {}
    for row in grip_rows:
        handle = row["HANDLE"].upper()
        grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = point(row, "GRIP_X", "GRIP_Y")
        types[handle] = row["RXCLASS"]
    candidates = {
        handle: values for handle, values in grips.items()
        if types.get(handle) == "TDbDimension2" and 2 in values and 3 in values
    }
    rows = []
    covered = []
    ambiguous = []
    for geometry in geometry_rows:
        source = geometry["SOURCE_HANDLE"].upper()
        segment = int(geometry["SEGMENT_INDEX"])
        start = point(geometry, "START_X", "START_Y")
        end = point(geometry, "END_X", "END_Y")
        exact = sorted(
            (endpoint_error(values[2], values[3], start, end), handle)
            for handle, values in candidates.items()
            if endpoint_error(values[2], values[3], start, end) <= tolerance
        )
        if exact:
            covered.append(f"{source}:{segment}")
        if len(exact) > 1:
            ambiguous.append(f"{source}:{segment}")
        rows.append({
            "SOURCE_HANDLE": source,
            "SEGMENT_INDEX": segment,
            "SEGMENT_TYPE": geometry["SEGMENT_TYPE"].upper(),
            "EXISTING_MATCH_COUNT": len(exact),
            "EXISTING_HANDLES": ",".join(handle for _, handle in exact),
            "MINIMUM_ENDPOINT_ERROR": f"{exact[0][0]:.12f}" if exact else "",
            "STATUS": "CLEAR" if not exact else "COVERED",
        })
    passed = bool(rows) and not covered and not ambiguous
    summary = {
        "status": "PASS" if passed else "FAIL",
        "target_segment_count": len(rows),
        "native_dimension_candidate_count": len(candidates),
        "preexisting_covered_count": len(covered),
        "preexisting_covered_segments": covered,
        "ambiguous_existing_count": len(ambiguous),
        "ambiguous_existing_segments": ambiguous,
        "tolerance": tolerance,
        "detail": "NO_PREEXISTING_TARGET_DIMENSIONS" if passed else "PREEXISTING_TARGET_DIMENSIONS_FOUND__ABORT_BEFORE_MUTATION",
    }
    return rows, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--tolerance", type=float, default=0.000001)
    parser.add_argument("--output-details", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()
    rows, summary = audit(read_tsv(args.geometry), read_tsv(args.grips), args.tolerance)
    args.output_details.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    fields = ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "EXISTING_MATCH_COUNT", "EXISTING_HANDLES", "MINIMUM_ENDPOINT_ERROR", "STATUS"]
    with args.output_details.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
