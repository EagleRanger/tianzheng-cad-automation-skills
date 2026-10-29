#!/usr/bin/env python3
"""Discover current-DWG polyline targets without board-specific identities.

Phase one derives style/segment signatures from reference geometry and filters a
full ModelSpace POLYLINE_STYLE_INVENTORY. Phase two proves a unique whole-
polyline geometry bijection and emits only the live current-DWG source rows.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


DIMENSIONABLE = {"ARC", "LINE"}


def read_tsv(path: Path) -> list[dict[str, str]]:
    data = path.read_bytes()
    error: UnicodeDecodeError | None = None
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            return list(csv.DictReader(data.decode(encoding).splitlines(), delimiter="\t"))
        except UnicodeDecodeError as caught:
            error = caught
    assert error is not None
    raise error


def write_tsv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def norm_number(value: str) -> str:
    return format(float(value), ".9g")


def group_geometry(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        if row["SEGMENT_TYPE"].upper() in DIMENSIONABLE:
            groups[row["SOURCE_HANDLE"].upper()].append(row)
    return dict(groups)


def reference_signatures(rows: list[dict[str, str]]) -> set[tuple[str, str, str, int, int]]:
    signatures: set[tuple[str, str, str, int, int]] = set()
    for group in group_geometry(rows).values():
        kinds = Counter(row["SEGMENT_TYPE"].upper() for row in group)
        layers = {row["LAYER"] for row in group}
        colors = {row["ENTITY_COLOR"] for row in group}
        widths = {norm_number(row["CONSTANT_WIDTH"]) for row in group}
        if len(layers) != 1 or len(colors) != 1 or len(widths) != 1:
            raise ValueError("REFERENCE_POLYLINE_STYLE_NOT_UNIFORM")
        signatures.add((next(iter(layers)), next(iter(colors)), next(iter(widths)), kinds["ARC"], kinds["LINE"]))
    return signatures


def style_candidates(style_rows: list[dict[str, str]], reference_rows: list[dict[str, str]]) -> tuple[list[str], dict[str, object]]:
    signatures = reference_signatures(reference_rows)
    handles: list[str] = []
    for row in style_rows:
        signature = (
            row["LAYER"],
            row["ENTITY_COLOR"],
            norm_number(row["CONSTANT_WIDTH"]),
            int(row["ARC_COUNT"]),
            int(row["STRAIGHT_COUNT"]),
        )
        if signature in signatures:
            handles.append(row["HANDLE"].upper())
    handles = sorted(set(handles))
    summary = {
        "status": "PASS" if handles and signatures else "FAIL",
        "full_modelspace_polyline_count": len(style_rows),
        "reference_style_segment_signature_count": len(signatures),
        "live_candidate_handle_count": len(handles),
        "selection_basis": "REFERENCE_DERIVED_LAYER_COLOR_WIDTH_AND_SEGMENT_TYPE_COUNTS",
        "fixed_current_handle_input": False,
    }
    return handles, summary


def point(row: dict[str, str], x: str, y: str) -> tuple[float, float]:
    return float(row[x]), float(row[y])


def distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])


def segment_error(current: dict[str, str], reference: dict[str, str]) -> float:
    c0, c1 = point(current, "START_X", "START_Y"), point(current, "END_X", "END_Y")
    r0, r1 = point(reference, "START_X", "START_Y"), point(reference, "END_X", "END_Y")
    error = min(distance(c0, r0) + distance(c1, r1), distance(c0, r1) + distance(c1, r0))
    if current["SEGMENT_TYPE"].upper() == "ARC":
        error += distance(point(current, "MID_X", "MID_Y"), point(reference, "MID_X", "MID_Y"))
    return error


def compatible(current: list[dict[str, str]], reference: list[dict[str, str]], tolerance: float) -> tuple[bool, float]:
    if Counter(row["SEGMENT_TYPE"].upper() for row in current) != Counter(row["SEGMENT_TYPE"].upper() for row in reference):
        return False, math.inf
    used: set[int] = set()
    maximum = 0.0
    for current_row in current:
        matches = sorted(
            (segment_error(current_row, reference_row), index)
            for index, reference_row in enumerate(reference)
            if reference_row["SEGMENT_TYPE"].upper() == current_row["SEGMENT_TYPE"].upper()
            and segment_error(current_row, reference_row) <= tolerance
        )
        available = [(error, index) for error, index in matches if index not in used]
        if len(available) != 1:
            return False, math.inf
        error, index = available[0]
        used.add(index)
        maximum = max(maximum, error)
    return len(used) == len(reference), maximum


def unique_bijection(current_rows: list[dict[str, str]], reference_rows: list[dict[str, str]], tolerance: float) -> tuple[list[dict[str, str]], list[dict[str, object]], dict[str, object]]:
    current = group_geometry(current_rows)
    reference = group_geometry(reference_rows)
    candidates: dict[str, list[tuple[str, float]]] = {}
    for reference_handle, reference_group in reference.items():
        matches = []
        for current_handle, current_group in current.items():
            okay, maximum = compatible(current_group, reference_group, tolerance)
            if okay:
                matches.append((current_handle, maximum))
        candidates[reference_handle] = sorted(matches)

    assignments: list[dict[str, tuple[str, float]]] = []
    ordered_reference = sorted(reference, key=lambda handle: (len(candidates[handle]), handle))

    def search(index: int, used: set[str], assignment: dict[str, tuple[str, float]]) -> None:
        if len(assignments) > 1:
            return
        if index == len(ordered_reference):
            assignments.append(dict(assignment))
            return
        reference_handle = ordered_reference[index]
        for current_handle, error in candidates[reference_handle]:
            if current_handle not in used:
                assignment[reference_handle] = (current_handle, error)
                search(index + 1, used | {current_handle}, assignment)
                assignment.pop(reference_handle, None)

    search(0, set(), {})
    unique = len(assignments) == 1
    selected_handles = set()
    source_map: list[dict[str, object]] = []
    maximum = 0.0
    if unique:
        for reference_handle in sorted(reference):
            current_handle, error = assignments[0][reference_handle]
            selected_handles.add(current_handle)
            maximum = max(maximum, error)
            source_map.append({
                "REFERENCE_SOURCE_HANDLE": reference_handle,
                "CURRENT_SOURCE_HANDLE": current_handle,
                "DIMENSIONABLE_SEGMENT_COUNT": len(reference[reference_handle]),
                "MAXIMUM_SEGMENT_GEOMETRY_ERROR": error,
            })
    selected = [row for row in current_rows if row["SOURCE_HANDLE"].upper() in selected_handles and row["SEGMENT_TYPE"].upper() in DIMENSIONABLE]
    selected.sort(key=lambda row: (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])))
    summary = {
        "status": "PASS" if unique else "FAIL",
        "live_candidate_source_count": len(current),
        "reference_source_count": len(reference),
        "unique_assignment_count": len(assignments),
        "selected_live_source_count": len(selected_handles),
        "reference_dimensionable_segment_count": sum(len(group) for group in reference.values()),
        "selected_current_dimensionable_segment_count": len(selected),
        "maximum_segment_geometry_error": maximum,
        "geometry_tolerance": tolerance,
        "fixed_current_handle_input": False,
    }
    if summary["reference_dimensionable_segment_count"] != len(selected):
        summary["status"] = "FAIL"
    return selected, source_map, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="mode", required=True)
    styles = subparsers.add_parser("style-candidates")
    styles.add_argument("--style-inventory", required=True, type=Path)
    styles.add_argument("--reference-geometry", required=True, type=Path)
    styles.add_argument("--output-handles", required=True, type=Path)
    styles.add_argument("--output-summary", required=True, type=Path)
    geometry = subparsers.add_parser("geometry-bijection")
    geometry.add_argument("--candidate-geometry", required=True, type=Path)
    geometry.add_argument("--reference-geometry", required=True, type=Path)
    geometry.add_argument("--geometry-tolerance", type=float, default=0.08)
    geometry.add_argument("--output-geometry", required=True, type=Path)
    geometry.add_argument("--output-source-map", required=True, type=Path)
    geometry.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()

    if args.mode == "style-candidates":
        handles, summary = style_candidates(read_tsv(args.style_inventory), read_tsv(args.reference_geometry))
        args.output_handles.parent.mkdir(parents=True, exist_ok=True)
        args.output_handles.write_text("\n".join(handles) + ("\n" if handles else ""), encoding="ascii")
        write_json(args.output_summary, summary)
    else:
        candidate_rows = read_tsv(args.candidate_geometry)
        selected, source_map, summary = unique_bijection(candidate_rows, read_tsv(args.reference_geometry), args.geometry_tolerance)
        write_tsv(args.output_geometry, selected, list(candidate_rows[0]) if candidate_rows else [])
        write_tsv(args.output_source_map, source_map, ["REFERENCE_SOURCE_HANDLE", "CURRENT_SOURCE_HANDLE", "DIMENSIONABLE_SEGMENT_COUNT", "MAXIMUM_SEGMENT_GEOMETRY_ERROR"])
        write_json(args.output_summary, summary)
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
