import math
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from plan_typed_dimension_quantified_common_band import (  # noqa: E402
    choose_signed_target,
    circle_through,
    orientation,
    source_polygon,
)


class TypedDimensionQuantifiedCommonBandTests(unittest.TestCase):
    def test_circle_through_three_points(self):
        center, radius = circle_through((1.0, 0.0), (0.0, 1.0), (-1.0, 0.0))
        self.assertAlmostEqual(center[0], 0.0)
        self.assertAlmostEqual(center[1], 0.0)
        self.assertAlmostEqual(radius, 1.0)

    def test_large_wcs_circle_is_stable_and_closed(self):
        origin_x, origin_y = 40_433_700.0, 2_871_900.0
        center, radius = circle_through(
            (origin_x + 10.0, origin_y),
            (origin_x, origin_y + 10.0),
            (origin_x - 10.0, origin_y),
        )
        self.assertAlmostEqual(center[0], origin_x, places=7)
        self.assertAlmostEqual(center[1], origin_y, places=7)
        self.assertAlmostEqual(radius, 10.0, places=7)
        rows = [
            {
                "SEGMENT_INDEX": "0",
                "SEGMENT_TYPE": "ARC",
                "START_X": str(origin_x + 10.0),
                "START_Y": str(origin_y),
                "MID_X": str(origin_x),
                "MID_Y": str(origin_y + 10.0),
                "END_X": str(origin_x - 10.0),
                "END_Y": str(origin_y),
            },
            {
                "SEGMENT_INDEX": "1",
                "SEGMENT_TYPE": "ARC",
                "START_X": str(origin_x - 10.0),
                "START_Y": str(origin_y),
                "MID_X": str(origin_x),
                "MID_Y": str(origin_y - 10.0),
                "END_X": str(origin_x + 10.0),
                "END_Y": str(origin_y),
            },
        ]
        _polygon, closed = source_polygon(rows)
        self.assertTrue(closed)

    def test_native_closed_flag_overrides_sample_roundoff(self):
        rows = [{
            "SEGMENT_INDEX": "0",
            "SEGMENT_TYPE": "LINE",
            "SOURCE_CLOSED": "TRUE",
            "START_X": "0",
            "START_Y": "0",
            "MID_X": "0.5",
            "MID_Y": "0",
            "END_X": "1",
            "END_Y": "0",
        }]
        _polygon, closed = source_polygon(rows)
        self.assertTrue(closed)

    def test_closed_line_path_chooses_unique_exterior(self):
        rows = []
        points = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0))
        for index, (start, end) in enumerate(zip(points, points[1:])):
            rows.append({
                "SEGMENT_INDEX": str(index),
                "SEGMENT_TYPE": "LINE",
                "START_X": str(start[0]),
                "START_Y": str(start[1]),
                "MID_X": str((start[0] + end[0]) * 0.5),
                "MID_Y": str((start[1] + end[1]) * 0.5),
                "END_X": str(end[0]),
                "END_Y": str(end[1]),
            })
        polygon, closed = source_polygon(rows)
        self.assertTrue(closed)
        target = choose_signed_target(0.2, 0.5, (1.0, 0.5), (1.0, 0.0), polygon, closed)
        self.assertEqual(target, 0.5)

    def test_narrow_closed_path_uses_local_exterior_probe(self):
        polygon = [(0.0, 0.0), (1.0, 0.0), (1.0, 0.2), (0.0, 0.2), (0.0, 0.0)]
        target = choose_signed_target(0.2, 2.0, (1.0, 0.1), (1.0, 0.0), polygon, True, (0.0, 1.0))
        self.assertEqual(target, 2.0)
    def test_open_path_preserves_current_side(self):
        self.assertEqual(
            choose_signed_target(-0.2, 0.5, (0.0, 0.0), (0.0, 1.0), [], False),
            -0.5,
        )
        self.assertEqual(orientation(0.1, -1.0), "BOTTOM")
        self.assertEqual(orientation(-1.0, 0.1), "LEFT")


if __name__ == "__main__":
    unittest.main()
