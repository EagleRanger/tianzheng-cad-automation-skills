#!/usr/bin/env python3
"""V4 sharp planner aligned with open-path virtual-exterior semantics."""

from __future__ import annotations

import plan_quantized_sharp_cluster_band_v3 as base
from plan_typed_dimension_quantified_common_band_v2 import source_polygon_for_exterior


def main() -> int:
    # The sharp pass must see the same planning topology as the ordinary pass.
    # Thus an open source can only move farther outward; it cannot flip an
    # isolated segment or cluster back across the path.
    base.source_polygon = source_polygon_for_exterior
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
