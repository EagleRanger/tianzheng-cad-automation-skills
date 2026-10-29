#!/usr/bin/env python3
"""Audit native dimension text semantics against runtime source geometry."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path


DEGREE_ESCAPE = "\\U+00B0"
MTEXT_PREFIX = re.compile(r"\\A\d+;", re.IGNORECASE)
NUMBER = re.compile(r"[-+]?\d+(?:[.,]\d+)?")


def read_tsv(path: Path, encoding: str) -> list[dict[str, str]]:
    with path.open("r", encoding=encoding, newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def normalize_handle(value: str | None) -> str:
    return (value or "").strip().upper()


def normalize_text(raw: str) -> str:
    value = raw.replace(DEGREE_ESCAPE, "°").replace(DEGREE_ESCAPE.lower(), "°")
    value = MTEXT_PREFIX.sub("", value)
    return value.replace("{", "").replace("}", "").strip()


def first_number(value: str) -> float | None:
    match = NUMBER.search(value)
    if not match:
        return None
    return float(match.group(0).replace(",", "."))


def row_key(row: dict[str, str]) -> tuple[str, str, int]:
    return (
        normalize_handle(row.get("SOURCE_HANDLE")),
        (row.get("SEGMENT_TYPE") or "").strip().upper(),
        int(row.get("SEGMENT_INDEX") or "-1"),
    )


def write_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "SOURCE_HANDLE",
        "SEGMENT_TYPE",
        "SEGMENT_INDEX",
        "NATIVE_HANDLE",
        "TEXT_ROW_COUNT",
        "RAW_TEXT",
        "NORMALIZED_TEXT",
        "HAS_DEGREE_MARKER",
        "NUMERIC_VALUE",
        "EXPECTED_INCLUDED_ANGLE_DEG",
        "ANGLE_ERROR_DEG",
        "STATUS",
        "REASON",
    ]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--text-inventory", type=Path)
    parser.add_argument("--text-bboxes", type=Path, help="Legacy alias for text inventory")
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    parser.add_argument("--geometry-encoding", default="utf-8-sig")
    parser.add_argument("--mapping-encoding", default="utf-8-sig")
    parser.add_argument("--text-encoding", default="utf-8-sig")
    parser.add_argument("--angle-tolerance-deg", type=float, default=0.011)
    args = parser.parse_args()
    text_path = args.text_inventory or args.text_bboxes
    if text_path is None:
        parser.error("one of --text-inventory or --text-bboxes is required")

    geometry_rows = read_tsv(args.geometry, args.geometry_encoding)
    mapping_rows = [
        row
        for row in read_tsv(args.mapping, args.mapping_encoding)
        if (row.get("STATUS") or "").strip().upper() == "PASS"
    ]
    text_rows = read_tsv(text_path, args.text_encoding)

    geometry = {row_key(row): row for row in geometry_rows}
    text_by_handle: dict[str, list[str]] = {}
    for row in text_rows:
        handle = normalize_handle(row.get("NATIVE_HANDLE") or row.get("HANDLE") or row.get("SOURCE_HANDLE"))
        candidates = []
        for field in ("TEXTCONTENT", "TEXT", "TEXTSTRING", "TEXTOVERRIDE", "DIMENSIONTEXT", "EXPLODED_TEXT"):
            value = (row.get(field) or "").strip()
            if value and value not in candidates:
                candidates.append(value)
        if handle and candidates:
            text_by_handle.setdefault(handle, []).extend(candidates)

    audit_rows: list[dict[str, object]] = []
    angle_errors: list[float] = []
    arc_count = 0
    line_count = 0
    arc_degree_marker_count = 0
    line_without_degree_count = 0

    for mapping in mapping_rows:
        key = row_key(mapping)
        source_handle, segment_type, segment_index = key
        native_handle = normalize_handle(mapping.get("NATIVE_HANDLE"))
        source = geometry.get(key)
        texts = text_by_handle.get(native_handle, [])
        raw_text = " | ".join(texts)
        normalized = normalize_text(raw_text)
        has_degree = "°" in normalized or DEGREE_ESCAPE.lower() in raw_text.lower()
        numeric_value = first_number(normalized)
        expected_angle: float | None = None
        angle_error: float | None = None
        reasons: list[str] = []

        if source is None:
            reasons.append("SOURCE_GEOMETRY_MISSING")
        if not native_handle:
            reasons.append("NATIVE_HANDLE_MISSING")
        if not texts:
            reasons.append("NATIVE_TEXT_MISSING")
        if numeric_value is None:
            reasons.append("NUMERIC_TEXT_MISSING")

        if segment_type == "ARC":
            arc_count += 1
            if has_degree:
                arc_degree_marker_count += 1
            else:
                reasons.append("ARC_DEGREE_MARKER_MISSING")
            if source is not None:
                try:
                    bulge = abs(float(source.get("BULGE") or "0"))
                    expected_angle = abs(math.degrees(4.0 * math.atan(bulge)))
                    if numeric_value is not None:
                        angle_error = abs(numeric_value - expected_angle)
                        angle_errors.append(angle_error)
                        if angle_error > args.angle_tolerance_deg:
                            reasons.append("ARC_INCLUDED_ANGLE_MISMATCH")
                except ValueError:
                    reasons.append("ARC_BULGE_INVALID")
        elif segment_type == "LINE":
            line_count += 1
            if has_degree:
                reasons.append("LINE_DEGREE_MARKER_FORBIDDEN")
            else:
                line_without_degree_count += 1
        else:
            reasons.append("UNSUPPORTED_SEGMENT_TYPE")

        audit_rows.append(
            {
                "SOURCE_HANDLE": source_handle,
                "SEGMENT_TYPE": segment_type,
                "SEGMENT_INDEX": segment_index,
                "NATIVE_HANDLE": native_handle,
                "TEXT_ROW_COUNT": len(texts),
                "RAW_TEXT": raw_text,
                "NORMALIZED_TEXT": normalized,
                "HAS_DEGREE_MARKER": str(has_degree).lower(),
                "NUMERIC_VALUE": "" if numeric_value is None else f"{numeric_value:.12f}",
                "EXPECTED_INCLUDED_ANGLE_DEG": "" if expected_angle is None else f"{expected_angle:.12f}",
                "ANGLE_ERROR_DEG": "" if angle_error is None else f"{angle_error:.12f}",
                "STATUS": "PASS" if not reasons else "FAIL",
                "REASON": "PASS" if not reasons else "|".join(reasons),
            }
        )

    failure_rows = [row for row in audit_rows if row["STATUS"] != "PASS"]
    summary = {
        "schema_version": 1,
        "status": "PASS" if mapping_rows and not failure_rows else "FAIL",
        "mapping_count": len(mapping_rows),
        "geometry_key_count": len(geometry),
        "native_text_handle_count": len(text_by_handle),
        "arc_count": arc_count,
        "line_count": line_count,
        "pass_count": len(audit_rows) - len(failure_rows),
        "fail_count": len(failure_rows),
        "arc_degree_marker_count": arc_degree_marker_count,
        "line_without_degree_count": line_without_degree_count,
        "max_arc_angle_error_deg": max(angle_errors, default=0.0),
        "angle_tolerance_deg": args.angle_tolerance_deg,
        "board_specific_algorithm_literals": 0,
        "algorithm_basis": "RUNTIME_SOURCE_MAPPING__BULGE_INCLUDED_ANGLE__NATIVE_TEXT",
        "cross_drawing_generalization": "UNVERIFIED",
        "failure_reasons": sorted({str(row["REASON"]) for row in failure_rows}),
    }

    write_tsv(args.output_audit, audit_rows)
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"status": summary["status"], "pass_count": summary["pass_count"], "fail_count": summary["fail_count"]}))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
