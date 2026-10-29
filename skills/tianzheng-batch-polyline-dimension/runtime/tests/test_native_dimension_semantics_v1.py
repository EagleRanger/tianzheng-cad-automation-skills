from __future__ import annotations

import csv
import json
import math
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "audit_native_dimension_semantics_v1.py"


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def run_fixture(tmp_path: Path, arc_text: str, line_text: str) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
    geometry = tmp_path / "geometry.tsv"
    mapping = tmp_path / "mapping.tsv"
    text = tmp_path / "text.tsv"
    audit = tmp_path / "audit.tsv"
    summary = tmp_path / "summary.json"
    write_tsv(
        geometry,
        ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "BULGE", "SEGMENT_LENGTH"],
        [
            {"SOURCE_HANDLE": "S1", "SEGMENT_INDEX": 0, "SEGMENT_TYPE": "ARC", "BULGE": math.tan(math.radians(22.5)), "SEGMENT_LENGTH": 20},
            {"SOURCE_HANDLE": "S1", "SEGMENT_INDEX": 1, "SEGMENT_TYPE": "LINE", "BULGE": 0, "SEGMENT_LENGTH": 12.34},
        ],
    )
    write_tsv(
        mapping,
        ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "STATUS", "NATIVE_HANDLE"],
        [
            {"SOURCE_HANDLE": "S1", "SEGMENT_INDEX": 0, "SEGMENT_TYPE": "ARC", "STATUS": "PASS", "NATIVE_HANDLE": "A1"},
            {"SOURCE_HANDLE": "S1", "SEGMENT_INDEX": 1, "SEGMENT_TYPE": "LINE", "STATUS": "PASS", "NATIVE_HANDLE": "A2"},
        ],
    )
    write_tsv(
        text,
        ["SOURCE_HANDLE", "TEXT_INDEX", "TEXT"],
        [
            {"SOURCE_HANDLE": "A1", "TEXT_INDEX": 1, "TEXT": arc_text},
            {"SOURCE_HANDLE": "A2", "TEXT_INDEX": 1, "TEXT": line_text},
        ],
    )
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--geometry",
            str(geometry),
            "--mapping",
            str(mapping),
            "--text-bboxes",
            str(text),
            "--output-audit",
            str(audit),
            "--output-summary",
            str(summary),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    return result, json.loads(summary.read_text(encoding="utf-8"))


def test_arc_angle_and_line_length_semantics_pass(tmp_path: Path) -> None:
    result, summary = run_fixture(tmp_path, r"\A1;90.00\U+00B0", r"\A1;12.34")
    assert result.returncode == 0, result.stderr + result.stdout
    assert summary["status"] == "PASS"
    assert summary["arc_count"] == 1
    assert summary["line_count"] == 1
    assert summary["arc_degree_marker_count"] == 1
    assert summary["line_without_degree_count"] == 1
    assert summary["max_arc_angle_error_deg"] < 1.0e-9
    assert summary["board_specific_algorithm_literals"] == 0


def test_arc_without_degree_marker_is_rejected(tmp_path: Path) -> None:
    result, summary = run_fixture(tmp_path, r"\A1;20.00", r"\A1;12.34")
    assert result.returncode == 1
    assert summary["status"] == "FAIL"
    assert any("ARC_DEGREE_MARKER_MISSING" in reason for reason in summary["failure_reasons"])


def test_line_with_degree_marker_is_rejected(tmp_path: Path) -> None:
    result, summary = run_fixture(tmp_path, r"\A1;90.00\U+00B0", r"\A1;12.34\U+00B0")
    assert result.returncode == 1
    assert summary["status"] == "FAIL"
    assert any("LINE_DEGREE_MARKER_FORBIDDEN" in reason for reason in summary["failure_reasons"])


def test_direct_native_property_is_accepted_when_explode_text_is_missing(tmp_path: Path) -> None:
    geometry = tmp_path / "geometry.tsv"
    mapping = tmp_path / "mapping.tsv"
    text = tmp_path / "text.tsv"
    audit = tmp_path / "audit.tsv"
    summary = tmp_path / "summary.json"
    write_tsv(geometry, ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "BULGE"], [
        {"SOURCE_HANDLE": "S9", "SEGMENT_INDEX": 7, "SEGMENT_TYPE": "ARC", "BULGE": math.tan(math.radians(20.0))}
    ])
    write_tsv(mapping, ["SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "STATUS", "NATIVE_HANDLE"], [
        {"SOURCE_HANDLE": "S9", "SEGMENT_INDEX": 7, "SEGMENT_TYPE": "ARC", "STATUS": "PASS", "NATIVE_HANDLE": "B7"}
    ])
    write_tsv(text, ["HANDLE", "TEXT", "TEXTSTRING", "TEXTOVERRIDE", "DIMENSIONTEXT", "EXPLODED_TEXT"], [
        {"HANDLE": "B7", "TEXT": r"80.00\U+00B0", "TEXTSTRING": "", "TEXTOVERRIDE": "", "DIMENSIONTEXT": "", "EXPLODED_TEXT": ""}
    ])
    result = subprocess.run([sys.executable, str(SCRIPT), "--geometry", str(geometry), "--mapping", str(mapping), "--text-inventory", str(text), "--output-audit", str(audit), "--output-summary", str(summary)], text=True, capture_output=True, check=False)
    data = json.loads(summary.read_text(encoding="utf-8"))
    assert result.returncode == 0, result.stderr + result.stdout
    assert data["status"] == "PASS"
