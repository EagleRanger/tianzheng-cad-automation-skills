import argparse
import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    for name in ("mapping", "source", "grips", "text-bboxes", "formula", "targets", "audit-tsv", "summary"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    v1 = root / "scripts" / "plan_arc_capacity_side_flip_v1.py"
    output_dir = Path(args.targets).resolve().parent
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="capacity_v2_", dir=output_dir) as temp_dir:
        temp = Path(temp_dir)
        old_targets = temp / "targets.tsv"
        old_audit = temp / "audit.tsv"
        old_summary = temp / "summary.json"
        command = [
            sys.executable,
            str(v1),
            "--mapping", args.mapping,
            "--source", args.source,
            "--grips", args.grips,
            "--text-bboxes", args.text_bboxes,
            "--formula", args.formula,
            "--targets", str(old_targets),
            "--audit-tsv", str(old_audit),
            "--summary", str(old_summary),
        ]
        subprocess.run(command, check=True)

        with old_targets.open("r", encoding="utf-8", newline="") as source_file:
            reader = csv.DictReader(source_file, delimiter="\t")
            fields = list(reader.fieldnames or [])
            rows = list(reader)
        if "AXIS_KIND" not in fields:
            raise RuntimeError("CAPACITY_V2_AXIS_KIND_COLUMN_MISSING")
        for row in rows:
            if row["AXIS_KIND"] != "ARC_RADIUS_OPPOSITE_CAPACITY":
                raise RuntimeError("CAPACITY_V2_UNEXPECTED_V1_AXIS_KIND:" + row["AXIS_KIND"])
            row["AXIS_KIND"] = "ARC_RADIUS"

        with Path(args.targets).open("w", encoding="utf-8", newline="") as target_file:
            writer = csv.DictWriter(target_file, fieldnames=fields, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        Path(args.audit_tsv).write_bytes(old_audit.read_bytes())
        summary = json.loads(old_summary.read_text(encoding="utf-8"))
        summary["axis_kind_contract"] = "ARC_RADIUS"
        summary["placement_mode"] = "OPPOSITE_CAPACITY"
        summary["formula_numeric_contract"] = "UNCHANGED_FROM_V1"
        Path(args.summary).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
