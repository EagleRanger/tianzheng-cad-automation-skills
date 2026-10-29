import argparse
import csv
import json
import math
from pathlib import Path


GRIP_COORDINATES = ("GRIP_X", "GRIP_Y", "GRIP_Z")
TARGET_COORDINATES = ("TARGET_X", "TARGET_Y", "TARGET_Z")


def read_tsv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        fields = list(reader.fieldnames or [])
        rows = list(reader)
    return fields, rows


def normalized_key(row):
    return row["HANDLE"].strip().upper(), int(row["GRIP_INDEX"])


def finite_text(value: str) -> str:
    number = float(value)
    if not math.isfinite(number):
        raise RuntimeError("PREDICTED_GRIP_NONFINITE_COORDINATE")
    return format(number, ".17g")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--grips", required=True)
    parser.add_argument("--targets", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary", required=True)
    args = parser.parse_args()

    grip_fields, grip_rows = read_tsv(Path(args.grips))
    target_fields, target_rows = read_tsv(Path(args.targets))
    required_grips = {"HANDLE", "GRIP_INDEX", *GRIP_COORDINATES}
    required_targets = {"HANDLE", "GRIP_INDEX", *TARGET_COORDINATES}
    if not required_grips.issubset(grip_fields):
        raise RuntimeError("PREDICTED_GRIP_INVENTORY_SCHEMA_INVALID")
    if not required_targets.issubset(target_fields):
        raise RuntimeError("PREDICTED_GRIP_TARGET_SCHEMA_INVALID")

    grip_index = {}
    for position, row in enumerate(grip_rows):
        item_key = normalized_key(row)
        if item_key in grip_index:
            raise RuntimeError("PREDICTED_GRIP_INVENTORY_DUPLICATE_KEY")
        grip_index[item_key] = position

    target_map = {}
    for row in target_rows:
        item_key = normalized_key(row)
        if item_key in target_map:
            raise RuntimeError("PREDICTED_GRIP_TARGET_DUPLICATE_KEY")
        if item_key[1] != 0:
            raise RuntimeError("PREDICTED_GRIP_TARGET_NOT_GRIP0")
        if item_key not in grip_index:
            raise RuntimeError("PREDICTED_GRIP_TARGET_NOT_IN_INVENTORY")
        target_map[item_key] = tuple(finite_text(row[name]) for name in TARGET_COORDINATES)

    output_rows = [dict(row) for row in grip_rows]
    for item_key, coordinates in target_map.items():
        output_row = output_rows[grip_index[item_key]]
        for grip_name, coordinate in zip(GRIP_COORDINATES, coordinates):
            output_row[grip_name] = coordinate

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=grip_fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(output_rows)

    unchanged_non_target_count = 0
    for before, after in zip(grip_rows, output_rows):
        if normalized_key(before) not in target_map:
            if before != after:
                raise RuntimeError("PREDICTED_GRIP_NON_TARGET_CHANGED")
            unchanged_non_target_count += 1

    summary = {
        "schema_version": 1,
        "status": "PASS",
        "inventory_row_count": len(grip_rows),
        "target_count": len(target_rows),
        "updated_grip0_count": len(target_map),
        "unchanged_non_target_row_count": unchanged_non_target_count,
        "row_count_preserved": len(output_rows) == len(grip_rows),
        "key_set_preserved": {normalized_key(row) for row in output_rows} == set(grip_index),
        "allowed_grip_indexes": [0],
        "prediction_semantics": "BASE_LAYOUT_TARGET_GRIP0_OVERLAY_WITHOUT_CAD_MUTATION",
    }
    Path(args.summary).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
