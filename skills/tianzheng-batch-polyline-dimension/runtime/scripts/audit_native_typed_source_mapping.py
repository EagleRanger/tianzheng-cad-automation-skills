#!/usr/bin/env python3
"""Audit exact ARC/LINE source-segment mapping for a typed Tianzheng batch."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


EXPECTED_STYLES = {"ARC": "_TCH_ARROW", "LINE": "_TCH_ARCH_M_M"}


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def point(row: dict[str, str], x: str, y: str) -> tuple[float, float]:
    return float(row[x]), float(row[y])


def distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])


def endpoint_error(grip2, grip3, start, end) -> float:
    return min(
        distance(grip2, start) + distance(grip3, end),
        distance(grip2, end) + distance(grip3, start),
    )


def ccw_delta(start: float, end: float) -> float:
    return (end - start) % (2.0 * math.pi)


def arc_pick_error(row: dict[str, str], pick: tuple[float, float], tolerance: float) -> float:
    """Return radial residual when the recorded TDIMARC pick lies on this source arc."""
    required = ("START_X", "START_Y", "MID_X", "MID_Y", "END_X", "END_Y")
    if not all(row.get(key, "") for key in required):
        return math.inf
    start = point(row, "START_X", "START_Y")
    middle = point(row, "MID_X", "MID_Y")
    end = point(row, "END_X", "END_Y")
    # Work in a source-local frame.  Real survey drawings use coordinates near
    # 4e7; the expanded global circumcenter formula loses enough precision
    # there to reject a valid TDIMARC pick by metres.
    ax, ay = start
    bx, by = middle[0] - ax, middle[1] - ay
    cx, cy = end[0] - ax, end[1] - ay
    determinant = 2.0 * (bx * cy - cx * by)
    if abs(determinant) <= 1e-12:
        return math.inf
    b2 = bx * bx + by * by
    c2 = cx * cx + cy * cy
    ux = (b2 * cy - c2 * by) / determinant
    uy = (c2 * bx - b2 * cx) / determinant
    center = (ax + ux, ay + uy)
    radius = distance(center, start)
    residual = abs(distance(center, pick) - radius)
    if residual > tolerance:
        return residual
    start_angle = math.atan2(start[1] - center[1], start[0] - center[0])
    mid_angle = math.atan2(middle[1] - center[1], middle[0] - center[0])
    end_angle = math.atan2(end[1] - center[1], end[0] - center[0])
    pick_angle = math.atan2(pick[1] - center[1], pick[0] - center[0])
    angular_tolerance = max(tolerance / max(radius, tolerance), 1e-9)
    # The exported midpoint is on the exact selected segment and therefore
    # disambiguates the travelled sweep without depending on host-specific
    # bulge sign conventions.
    ccw = ccw_delta(start_angle, mid_angle) <= ccw_delta(start_angle, end_angle) + angular_tolerance
    if ccw:
        inside = ccw_delta(start_angle, pick_angle) <= ccw_delta(start_angle, end_angle) + angular_tolerance
    else:
        inside = ccw_delta(end_angle, pick_angle) <= ccw_delta(end_angle, start_angle) + angular_tolerance
    return residual if inside else math.inf


def audit(
    geometry_rows,
    detail_rows,
    grip_rows,
    tolerance,
    validated_signature_rows=None,
    signature_tolerance=None,
):
    geometry = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in geometry_rows
    }
    grips: dict[str, dict[int, tuple[float, float]]] = {}
    grip_types: dict[str, str] = {}
    grip_layers: dict[str, str] = {}
    grip_extents: dict[str, tuple[float, float, float, float]] = {}
    for row in grip_rows:
        handle = row["HANDLE"].upper()
        grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = point(
            row, "GRIP_X", "GRIP_Y"
        )
        grip_types[handle] = row["RXCLASS"]
        grip_layers[handle] = row["LAYER"]
        if all(row.get(key, "") for key in ("EXTMIN_X", "EXTMIN_Y", "EXTMAX_X", "EXTMAX_Y")):
            grip_extents[handle] = (
                float(row["EXTMIN_X"]), float(row["EXTMIN_Y"]),
                float(row["EXTMAX_X"]), float(row["EXTMAX_Y"]),
            )

    validated_signatures = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in (validated_signature_rows or [])
    }
    if signature_tolerance is None:
        signature_tolerance = tolerance

    results = []
    failures = []
    used_handles: set[str] = set()
    arc_count = 0
    line_count = 0
    max_error = 0.0
    max_primary_error = 0.0
    validated_signature_count = 0
    generation_pick_count = 0
    for detail in detail_rows:
        source = detail["SOURCE_HANDLE"].upper()
        segment = int(detail["SEGMENT_INDEX"])
        segment_type = detail["SEGMENT_TYPE"].upper()
        handle = detail["ADDED_HANDLE"].upper()
        identity = (source, segment)
        reasons = []
        error = math.inf
        primary_error = math.inf
        signature_error = math.inf
        generation_pick_residual = math.inf
        association_mode = ""

        if segment_type == "ARC":
            arc_count += 1
        elif segment_type == "LINE":
            line_count += 1
        else:
            reasons.append("UNSUPPORTED_SEGMENT_TYPE")
        source_row = geometry.get(identity)
        if source_row is None:
            reasons.append("SOURCE_SEGMENT_MISSING_FROM_GEOMETRY")
        elif source_row["SEGMENT_TYPE"].upper() != segment_type:
            reasons.append("SOURCE_SEGMENT_TYPE_MISMATCH")
        if detail.get("STATUS", "").upper() != "PASS":
            reasons.append("GENERATION_STATUS_NOT_PASS")
        if not handle:
            reasons.append("ADDED_HANDLE_MISSING")
        elif handle in used_handles:
            reasons.append("ADDED_HANDLE_DUPLICATED")
        else:
            used_handles.add(handle)
        if detail.get("OBJECT_NAME", "") != "TDbDimension2":
            reasons.append("DETAIL_OBJECT_TYPE_INVALID")
        if detail.get("LAYER", "") != "PUB_DIM":
            reasons.append("DETAIL_LAYER_INVALID")
        if detail.get("DIM_STYLE", "") != EXPECTED_STYLES.get(segment_type, ""):
            reasons.append("DIM_STYLE_INVALID_FOR_SEGMENT_TYPE")

        handle_grips = grips.get(handle, {})
        if grip_types.get(handle) != "TDbDimension2":
            reasons.append("GRIP_OBJECT_TYPE_INVALID")
        if grip_layers.get(handle) != "PUB_DIM":
            reasons.append("GRIP_LAYER_INVALID")
        if 2 not in handle_grips or 3 not in handle_grips:
            reasons.append("SOURCE_ENDPOINT_GRIPS_MISSING")
        elif source_row is not None:
            error = endpoint_error(
                handle_grips[2], handle_grips[3],
                point(source_row, "START_X", "START_Y"),
                point(source_row, "END_X", "END_Y"),
            )
            max_error = max(max_error, error)
            if error <= tolerance:
                association_mode = "ENDPOINT_GRIPS"
                primary_error = error
            else:
                reference = validated_signatures.get(identity)
                observed_extents = grip_extents.get(handle)
                reference_eligible = (
                    segment_type == "ARC"
                    and reference is not None
                    and observed_extents is not None
                    and reference.get("RXCLASS", "") == "TDbDimension2"
                    and reference.get("LAYER", "") == "PUB_DIM"
                    and reference.get("DIM_STYLE", "") == EXPECTED_STYLES["ARC"]
                    and int(reference.get("GRIP_COUNT", "0")) == len(handle_grips)
                )
                if reference_eligible:
                    expected_extents = tuple(float(reference[key]) for key in (
                        "EXTMIN_X", "EXTMIN_Y", "EXTMAX_X", "EXTMAX_Y"
                    ))
                    signature_error = max(
                        abs(observed - expected)
                        for observed, expected in zip(observed_extents, expected_extents)
                    )
                    if signature_error <= signature_tolerance:
                        association_mode = "VALIDATED_NATIVE_BBOX_SIGNATURE"
                        primary_error = signature_error
                        validated_signature_count += 1
                    else:
                        reasons.append("VALIDATED_NATIVE_SIGNATURE_MISMATCH")
                if not association_mode and segment_type == "ARC" and all(
                    detail.get(key, "") for key in ("PICK_X", "PICK_Y")
                ):
                    generation_pick_residual = arc_pick_error(
                        source_row, point(detail, "PICK_X", "PICK_Y"), tolerance
                    )
                    if generation_pick_residual <= tolerance:
                        association_mode = "GENERATION_PICK_ON_SOURCE_ARC"
                        primary_error = generation_pick_residual
                        generation_pick_count += 1
                if not association_mode:
                    reasons.append("SOURCE_ENDPOINT_ASSOCIATION_FAILED")

        if not math.isinf(primary_error):
            max_primary_error = max(max_primary_error, primary_error)

        status = "PASS" if not reasons else "FAIL"
        if reasons:
            failures.append(f"{source}:{segment}:{'|'.join(reasons)}")
        results.append({
            "SOURCE_HANDLE": source,
            "SEGMENT_INDEX": segment,
            "SEGMENT_TYPE": segment_type,
            "NATIVE_HANDLE": handle,
            "STATUS": status,
            "ENDPOINT_ERROR": "" if math.isinf(error) else f"{error:.12f}",
            "ASSOCIATION_MODE": association_mode,
            "PRIMARY_ASSOCIATION_ERROR": "" if math.isinf(primary_error) else f"{primary_error:.12f}",
            "REFERENCE_SIGNATURE_ERROR": "" if math.isinf(signature_error) else f"{signature_error:.12f}",
            "GENERATION_PICK_ERROR": "" if math.isinf(generation_pick_residual) else f"{generation_pick_residual:.12f}",
            "EXPECTED_DIM_STYLE": EXPECTED_STYLES.get(segment_type, ""),
            "OBSERVED_DIM_STYLE": detail.get("DIM_STYLE", ""),
            "FAILURE_REASONS": "|".join(reasons),
        })

    expected = set(geometry)
    observed = {(row["SOURCE_HANDLE"], int(row["SEGMENT_INDEX"])) for row in results}
    missing = sorted(expected - observed)
    extra = sorted(observed - expected)
    if missing:
        failures.append("MISSING_GENERATED_SEGMENTS:" + ",".join(f"{h}:{i}" for h, i in missing))
    if extra:
        failures.append("EXTRA_GENERATED_SEGMENTS:" + ",".join(f"{h}:{i}" for h, i in extra))
    passed = bool(results) and not failures and len(results) == len(geometry)
    summary = {
        "status": "PASS" if passed else "FAIL",
        "expected_segment_count": len(geometry),
        "audited_segment_count": len(results),
        "arc_segment_count": arc_count,
        "line_segment_count": line_count,
        "unique_native_handle_count": len(used_handles),
        "maximum_endpoint_error": max_error,
        "maximum_primary_association_error": max_primary_error,
        "validated_signature_association_count": validated_signature_count,
        "generation_pick_association_count": generation_pick_count,
        "tolerance": tolerance,
        "missing_source_segments": [f"{h}:{i}" for h, i in missing],
        "extra_generated_segments": [f"{h}:{i}" for h, i in extra],
        "failures": failures,
    }
    return results, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--generation-details", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--tolerance", type=float, default=0.000001)
    parser.add_argument("--validated-signatures", type=Path)
    parser.add_argument("--signature-tolerance", type=float)
    parser.add_argument("--output-mapping", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()
    results, summary = audit(
        read_tsv(args.geometry), read_tsv(args.generation_details),
        read_tsv(args.grips), args.tolerance,
        read_tsv(args.validated_signatures) if args.validated_signatures else None,
        args.signature_tolerance,
    )
    args.output_mapping.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "NATIVE_HANDLE",
                  "STATUS", "ENDPOINT_ERROR", "ASSOCIATION_MODE",
                  "PRIMARY_ASSOCIATION_ERROR", "REFERENCE_SIGNATURE_ERROR", "EXPECTED_DIM_STYLE",
                  "GENERATION_PICK_ERROR",
                  "OBSERVED_DIM_STYLE", "FAILURE_REASONS"]
    with args.output_mapping.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(results)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
