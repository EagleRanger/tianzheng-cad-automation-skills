#!/usr/bin/env python3
"""Resolve conservative text envelopes only with native rendered-text evidence."""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path


EVIDENCE_FIELDS = (
    "EXPLODED_TEXT",
    "TEXTCONTENT",
    "TEXT",
    "TEXTSTRING",
    "TEXTOVERRIDE",
    "DIMENSIONTEXT",
)


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        return list(reader.fieldnames or []), list(reader)


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def clean(value: str | None) -> str:
    return (value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--semantic-inventory", required=True, type=Path)
    parser.add_argument("--output-bboxes", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    base = root / "scripts" / "resolve_native_dimension_text_bboxes_v2.py"
    staging = args.output_summary.parent / (args.output_summary.stem + "_v2_staging")
    staging.mkdir(parents=True, exist_ok=True)
    base_bboxes = staging / "resolved_text_bboxes.tsv"
    base_audit = staging / "text_bbox_resolution_audit.tsv"
    base_summary = staging / "text_bbox_resolution_summary.json"
    completed = subprocess.run(
        [
            sys.executable, str(base), "--mapping", str(args.mapping), "--grips", str(args.grips),
            "--text-bboxes", str(args.text_bboxes), "--output-bboxes", str(base_bboxes),
            "--output-audit", str(base_audit), "--output-summary", str(base_summary),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise SystemExit("TEXT_BBOX_V4_BASE_FAILED:" + clean(completed.stderr or completed.stdout))

    bbox_fields, bbox_rows = read_tsv(base_bboxes)
    audit_fields, audit_rows = read_tsv(base_audit)
    _, semantic_rows = read_tsv(args.semantic_inventory)
    semantic: dict[str, tuple[str, str]] = {}
    for row in semantic_rows:
        handle = clean(row.get("HANDLE") or row.get("SOURCE_HANDLE")).upper()
        candidates = [(field, clean(row.get(field))) for field in EVIDENCE_FIELDS]
        candidates = [(field, value) for field, value in candidates if value]
        if not handle or not candidates:
            continue
        field, value = candidates[0]
        if handle in semantic and semantic[handle][1] != value:
            raise SystemExit("TEXT_BBOX_V4_SEMANTIC_DUPLICATE:" + handle)
        semantic[handle] = (field, value)

    unresolved: list[str] = []
    rendered_resolved = 0
    direct = 0
    by_handle = {clean(row.get("SOURCE_HANDLE")).upper(): row for row in audit_rows}
    for row in bbox_rows:
        handle = clean(row.get("SOURCE_HANDLE")).upper()
        method = clean(row.get("RESOLUTION_METHOD"))
        if method == "DIRECT_TEXT_EXPLODE":
            direct += 1
            continue
        evidence = semantic.get(handle)
        if evidence is None:
            unresolved.append(handle)
            if handle in by_handle:
                by_handle[handle]["STATUS"] = "FAIL"
                by_handle[handle]["DETAIL"] = "NATIVE_RENDERED_TEXT_REQUIRED_FOR_PROXY_GEOMETRY"
            continue
        field, value = evidence
        row["TEXT"] = value
        row["RESOLUTION_METHOD"] = "NATIVE_RENDERED_TEXT_LIVE_GRIP_CONSERVATIVE_PEER_ENVELOPE"
        row["OBJECT_NAME"] = "TDBDIMENSION2_RENDERED_TEXT_CONSERVATIVE_ENVELOPE"
        if handle in by_handle:
            by_handle[handle]["RESOLUTION_METHOD"] = row["RESOLUTION_METHOD"]
            by_handle[handle]["DETAIL"] = f"{field}_PLUS_LIVE_TEXT_GRIP_PLUS_CONSERVATIVE_PEER_ENVELOPE"
        rendered_resolved += 1

    expected = len(bbox_rows)
    status = "PASS" if expected and not unresolved and direct + rendered_resolved == expected else "FAIL"
    write_tsv(args.output_bboxes, bbox_fields, bbox_rows)
    write_tsv(args.output_audit, audit_fields, audit_rows)
    summary = {
        "schema_version": 4,
        "status": status,
        "resolved_total_count": direct + rendered_resolved,
        "direct_text_bbox_count": direct,
        "native_rendered_text_resolved_count": rendered_resolved,
        "proxy_only_count": 0 if not unresolved else len(unresolved),
        "unresolved_count": len(unresolved),
        "unresolved_handles": unresolved,
        "formal_evidence_policy": "DIRECT_BBOX_OR_NATIVE_RENDERED_TEXT_WITH_CONSERVATIVE_LIVE_GRIP_ENVELOPE",
        "business_object_mutation_count": 0,
        "board_specific_algorithm_literals": 0,
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
