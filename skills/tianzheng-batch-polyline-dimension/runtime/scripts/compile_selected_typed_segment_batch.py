#!/usr/bin/env python3
"""Compile an exact selected-source ledger into one typed Tianzheng batch.

The selection ledger remains the scope authority.  Every classified ARC and
LINE segment is emitted in its original source-local index order; a LINE may
not be silently deferred by this compiler.  The trusted frozen batch engine
then dispatches ARC to TDIMARC and LINE to TDimMP.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from collections import defaultdict
from pathlib import Path


HANDLE = re.compile(r"^[0-9A-F]+$")
ARC_DISPOSITIONS = {"ANGLE_DIMENSION_THIS_PASS"}
LINE_DISPOSITIONS = {
    "DEFERRED_LENGTH_DIMENSION",
    "DEFER_STRAIGHT_LENGTH",
    "LENGTH_DIMENSION_THIS_PASS",
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def normalize_drawing(path: str) -> str:
    return path.replace("\\", "/")


def compile_rows(rows: list[dict[str, str]]) -> tuple[list[str], dict[str, object]]:
    grouped: dict[str, list[tuple[int, str]]] = defaultdict(list)
    seen: set[tuple[str, int]] = set()
    arc_count = 0
    line_count = 0

    if not rows:
        raise ValueError("EMPTY_SELECTION_LEDGER")

    for row_number, row in enumerate(rows, start=2):
        source = row.get("SOURCE_HANDLE", "").strip().upper()
        segment_text = row.get("SEGMENT_INDEX", "").strip()
        segment_type = row.get("SEGMENT_TYPE", "").strip().upper()
        disposition = row.get("DISPOSITION", "").strip().upper()

        if not HANDLE.fullmatch(source):
            raise ValueError(f"INVALID_SOURCE_HANDLE_AT_ROW_{row_number}:{source}")
        try:
            segment = int(segment_text)
        except ValueError as error:
            raise ValueError(
                f"INVALID_SEGMENT_INDEX_AT_ROW_{row_number}:{segment_text}"
            ) from error
        if segment < 0:
            raise ValueError(f"NEGATIVE_SEGMENT_INDEX_AT_ROW_{row_number}:{segment}")
        identity = (source, segment)
        if identity in seen:
            raise ValueError(f"DUPLICATE_SOURCE_SEGMENT:{source}:{segment}")
        seen.add(identity)

        if segment_type == "ARC":
            if disposition not in ARC_DISPOSITIONS:
                raise ValueError(
                    f"ARC_DISPOSITION_MISMATCH:{source}:{segment}:{disposition}"
                )
            arc_count += 1
        elif segment_type == "LINE":
            if disposition not in LINE_DISPOSITIONS:
                raise ValueError(
                    f"LINE_DISPOSITION_MISMATCH:{source}:{segment}:{disposition}"
                )
            line_count += 1
        else:
            raise ValueError(
                f"UNCLASSIFIED_SEGMENT_FORBIDDEN:{source}:{segment}:{segment_type}"
            )
        grouped[source].append((segment, segment_type))

    task_lines: list[str] = []
    for source, segments in grouped.items():
        ordered = sorted(segments)
        typed = " ".join(f'(\"{segment_type}\" {index})' for index, segment_type in ordered)
        task_lines.append(f'  (\"{source}\" ({typed}) {{OFFSET}} \"{{GROUP}}\")')

    summary: dict[str, object] = {
        "status": "PASS",
        "dispatch_mode": "AUTO_TYPED",
        "source_count": len(grouped),
        "target_segment_count": len(seen),
        "arc_segment_count": arc_count,
        "line_segment_count": line_count,
        "unclassified_segment_count": 0,
        "silent_deferred_line_count": 0,
        "source_handles": list(grouped),
    }
    return task_lines, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expected-drawing", required=True)
    parser.add_argument(
        "--drawing-binding",
        choices=("owner-state", "embedded"),
        default="owner-state",
        help=(
            "owner-state keeps the ASCII task spec path-free and relies on the "
            "owned-document gate; embedded writes an ASCII-only drawing path into "
            "the frozen engine spec."
        ),
    )
    parser.add_argument("--offset", type=float, required=True)
    parser.add_argument(
        "--source-offsets",
        default="",
        help="Optional comma-separated exact source=nonzero_offset map.",
    )
    parser.add_argument(
        "--segment-offsets",
        default="",
        help="Optional comma-separated source:segment=nonzero_offset overrides.",
    )
    parser.add_argument("--group", choices=("ROAD", "SHORE"), required=True)
    parser.add_argument(
        "--source-handles",
        default="",
        help="Optional comma-separated exact subset already present in the ledger.",
    )
    parser.add_argument(
        "--cleanup-handles",
        default="",
        help=(
            "Optional comma-separated native annotation handles to replace in the "
            "same governed transaction. The frozen engine validates type, layer and "
            "dimension style before deleting them."
        ),
    )
    parser.add_argument("--summary-path", default="C:/tmp/cx_tdimarc_full_typed_summary.tsv")
    parser.add_argument("--details-path", default="C:/tmp/cx_tdimarc_full_typed_details.tsv")
    args = parser.parse_args()

    if args.offset == 0:
        raise SystemExit("OFFSET_MUST_BE_NONZERO")

    rows = read_rows(args.ledger)
    requested_sources = {
        item.strip().upper()
        for item in args.source_handles.split(",")
        if item.strip()
    }
    cleanup_handles = [
        item.strip().upper()
        for item in args.cleanup_handles.split(",")
        if item.strip()
    ]
    invalid_cleanup_handles = [
        handle for handle in cleanup_handles if not HANDLE.fullmatch(handle)
    ]
    if invalid_cleanup_handles:
        raise SystemExit(
            "INVALID_CLEANUP_HANDLES:" + ",".join(invalid_cleanup_handles)
        )
    if len(set(cleanup_handles)) != len(cleanup_handles):
        raise SystemExit("DUPLICATE_CLEANUP_HANDLES")
    if requested_sources:
        ledger_sources = {
            row.get("SOURCE_HANDLE", "").strip().upper() for row in rows
        }
        missing_sources = sorted(requested_sources - ledger_sources)
        if missing_sources:
            raise SystemExit(
                "REQUESTED_SOURCE_ABSENT_FROM_LEDGER:" + ",".join(missing_sources)
            )
        rows = [
            row
            for row in rows
            if row.get("SOURCE_HANDLE", "").strip().upper() in requested_sources
        ]

    try:
        task_templates, summary = compile_rows(rows)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    source_offsets: dict[str, float] = {}
    for item in (part.strip() for part in args.source_offsets.split(",")):
        if not item:
            continue
        if "=" not in item:
            raise SystemExit("INVALID_SOURCE_OFFSET_ITEM:" + item)
        source, value_text = item.split("=", 1)
        source = source.strip().upper()
        if not HANDLE.fullmatch(source) or source in source_offsets:
            raise SystemExit("INVALID_OR_DUPLICATE_SOURCE_OFFSET:" + source)
        try:
            value = float(value_text)
        except ValueError as error:
            raise SystemExit("INVALID_SOURCE_OFFSET_VALUE:" + item) from error
        if not math.isfinite(value) or value == 0:
            raise SystemExit("SOURCE_OFFSET_MUST_BE_FINITE_NONZERO:" + source)
        source_offsets[source] = value
    compiled_sources = set(summary["source_handles"])
    if source_offsets and set(source_offsets) != compiled_sources:
        missing = sorted(compiled_sources - set(source_offsets))
        extra = sorted(set(source_offsets) - compiled_sources)
        raise SystemExit(
            "SOURCE_OFFSET_SET_MISMATCH:missing=" + ",".join(missing)
            + ":extra=" + ",".join(extra)
        )
    segment_offsets: dict[tuple[str, int], float] = {}
    for item in (part.strip() for part in args.segment_offsets.split(",")):
        if not item:
            continue
        if "=" not in item or ":" not in item.split("=", 1)[0]:
            raise SystemExit("INVALID_SEGMENT_OFFSET_ITEM:" + item)
        identity_text, value_text = item.split("=", 1)
        source, segment_text = identity_text.split(":", 1)
        source = source.strip().upper()
        try:
            identity = (source, int(segment_text))
            value = float(value_text)
        except ValueError as error:
            raise SystemExit("INVALID_SEGMENT_OFFSET_VALUE:" + item) from error
        if not HANDLE.fullmatch(source) or identity in segment_offsets:
            raise SystemExit("INVALID_OR_DUPLICATE_SEGMENT_OFFSET:" + identity_text)
        if not math.isfinite(value) or value == 0:
            raise SystemExit("SEGMENT_OFFSET_MUST_BE_FINITE_NONZERO:" + identity_text)
        segment_offsets[identity] = value
    compiled_identities = {
        (row.get("SOURCE_HANDLE", "").strip().upper(), int(row["SEGMENT_INDEX"]))
        for row in rows
    }
    extra_segment_offsets = sorted(set(segment_offsets) - compiled_identities)
    if extra_segment_offsets:
        raise SystemExit(
            "SEGMENT_OFFSET_OUTSIDE_COMPILED_SCOPE:"
            + ",".join(f"{source}:{segment}" for source, segment in extra_segment_offsets)
        )
    if segment_offsets:
        grouped_tasks: dict[tuple[str, float], list[tuple[int, str]]] = defaultdict(list)
        for row in rows:
            source = row["SOURCE_HANDLE"].strip().upper()
            segment = int(row["SEGMENT_INDEX"])
            offset = segment_offsets.get(
                (source, segment), source_offsets.get(source, args.offset)
            )
            grouped_tasks[(source, offset)].append(
                (segment, row["SEGMENT_TYPE"].strip().upper())
            )
        task_lines = []
        for (source, offset), segments in grouped_tasks.items():
            typed = " ".join(
                f'(\"{segment_type}\" {index})'
                for index, segment_type in sorted(segments)
            )
            task_lines.append(
                f'  (\"{source}\" ({typed}) {format(offset, ".12g")} \"{args.group}\")'
            )
    else:
        task_lines = []
        for line in task_templates:
            source = line.split('"', 2)[1]
            offset = source_offsets.get(source, args.offset)
            task_lines.append(
                line.replace("{OFFSET}", format(offset, ".12g")).replace(
                    "{GROUP}", args.group
                )
            )
    normalized_drawing = normalize_drawing(args.expected_drawing)
    if args.drawing_binding == "embedded":
        try:
            normalized_drawing.encode("ascii")
        except UnicodeEncodeError as error:
            raise SystemExit(
                "EMBEDDED_EXPECTED_DRAWING_MUST_BE_ASCII__USE_OWNER_STATE_BINDING"
            ) from error
        task_spec_drawing = normalized_drawing
    else:
        # The whitelist action already binds exact PID, HWND and target DWG from
        # owner_state.json before loading this data-only spec.  Keeping the
        # engine field empty avoids corrupting Chinese DWG paths in an ASCII
        # AutoLISP task file while retaining the stronger outer ownership gate.
        task_spec_drawing = ""

    content = "\n".join(
        [
            ";; Generated data only for the frozen typed-segment dispatcher.",
            ";; AUTO_TYPED is fail-closed: ARC and LINE are both mandatory targets.",
            "(setq cx:*full-batch-tasks* '(",
            *task_lines,
            "))",
            "(setq cx:*full-batch-cleanup-handles* '("
            + " ".join(f'\"{handle}\"' for handle in cleanup_handles)
            + "))",
            "(setq cx:*full-batch-clean-slate-object-names* '())",
            f'(setq cx:*full-batch-expected-drawing* "{task_spec_drawing}")',
            f'(setq cx:*full-batch-summary-path* "{args.summary_path}")',
            f'(setq cx:*full-batch-details-path* "{args.details_path}")',
            "(setq cx:*full-batch-save-on-success* nil)",
            "",
        ]
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="ascii")
    summary.update(
        {
            "ledger": str(args.ledger),
            "output": str(args.output),
            "expected_drawing": normalized_drawing,
            "drawing_binding": args.drawing_binding,
            "task_spec_embedded_drawing": task_spec_drawing,
            "offset": args.offset,
            "source_offsets": source_offsets,
            "segment_offsets": {
                f"{source}:{segment}": value
                for (source, segment), value in segment_offsets.items()
            },
            "offset_mode": (
                "PER_SEGMENT_OVERRIDE" if segment_offsets
                else "PER_SOURCE" if source_offsets else "UNIFORM"
            ),
            "group": args.group,
            "requested_source_handles": sorted(requested_sources),
            "cleanup_handles": cleanup_handles,
        }
    )
    args.report.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
