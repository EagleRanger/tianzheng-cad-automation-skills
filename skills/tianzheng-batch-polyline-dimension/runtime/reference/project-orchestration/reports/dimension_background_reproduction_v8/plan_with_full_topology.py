"""Supply complete source topology to the unchanged common-band planner."""

from __future__ import annotations

import argparse
import csv
import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("accepted_common_band", ROOT / "scripts/plan_typed_dimension_quantified_common_band.py")
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


def bind_full_topology(module, full_rows):
    native_polygon = module.source_polygon
    by_source = {}
    by_key = {}
    for row in full_rows:
        if row["SEGMENT_TYPE"].upper() not in {"ARC", "LINE"}:
            continue
        source = row["SOURCE_HANDLE"].upper()
        identity = source, int(row["SEGMENT_INDEX"])
        if identity in by_key:
            raise ValueError("DUPLICATE_FULL_SOURCE_TOPOLOGY")
        by_key[identity] = row
        by_source.setdefault(source, []).append(row)

    def full_source_polygon(selected_rows):
        sources = {row["SOURCE_HANDLE"].upper() for row in selected_rows}
        if len(sources) != 1:
            raise ValueError("ONE_SOURCE_PER_TOPOLOGY_CALL_REQUIRED")
        source = next(iter(sources))
        for row in selected_rows:
            original = by_key.get((source, int(row["SEGMENT_INDEX"])))
            if original is None:
                raise ValueError("SELECTED_SEGMENT_NOT_IN_FULL_NATIVE_SOURCE")
            for name in ("SEGMENT_TYPE", "START_X", "START_Y", "MID_X", "MID_Y", "END_X", "END_Y", "BULGE", "SEGMENT_LENGTH", "CONSTANT_WIDTH"):
                if row.get(name) != original.get(name):
                    raise ValueError("SELECTED_AND_FULL_NATIVE_GEOMETRY_DIFFER:" + name)
        # Original sampling, closure, polygon and exterior arithmetic stay in
        # the accepted module. Only the missing native source rows are supplied.
        return native_polygon(by_source[source])

    module.source_polygon = full_source_polygon
    return full_source_polygon


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--full-source-geometry", type=Path, required=True)
    args, original_args = parser.parse_known_args()
    with args.full_source_geometry.open(encoding="utf-8-sig", newline="") as stream:
        full_rows = list(csv.DictReader(stream, delimiter="\t"))
    bind_full_topology(planner, full_rows)
    sys.argv = [sys.argv[0], *original_args]
    return planner.main()


if __name__ == "__main__":
    raise SystemExit(main())
