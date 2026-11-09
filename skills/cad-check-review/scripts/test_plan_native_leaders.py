"""Vector and bounded-batch regression cases; no CAD or drawing access."""
import copy
import math
import unittest
from plan_native_leaders import angle, build, paper, plan_one, segment_hits_box, ROLES


def fixture(profile="leader4-paper"):
    grips = [[0., 0., 0.] for _ in range(7 if profile == "index-paper" else 4)]
    for i, point in zip(ROLES[profile], ([0., 0., 0.], [5., 5., 0.], [0., 5., 0.])):
        grips[i] = point
    native = dict(handle="ABC", rxclass="TEST", layer="annotation", profile=profile,
                  grips=grips, properties={}, joint=dict(status="FAIL", native_segments_verified=True),
                  viewport=dict(handle="DEF", target=[0, 0, 0], center=[0, 0, 0],
                                view_center=[0, 0], scale=1, twist=0))
    req = dict(handle="ABC", source=dict(state="active", feature_id="road", evidence="test",
               handle="123", layer="road", tolerance=.01), leader_lengths_paper=[5, 10],
               bar_length_paper=7, max_leader_paper=15, max_bearing_paper=10)
    return native, req


class VectorRules(unittest.TestCase):
    def test_observed_acute_index_is_not_complemented(self):
        self.assertAlmostEqual(angle([3313.1,735.6], [3379.6857964442406,786], [3340,786]), 37.122741, places=5)

    def test_all_three_profiles_choose_right_angle(self):
        for profile in ROLES:
            with self.subTest(profile=profile):
                n, r = fixture(profile)
                a, reason = plan_one(n, r)
                self.assertIsNone(reason)
                self.assertAlmostEqual(a["planned_angle"], 90)

    def test_rotated_scaled_viewport(self):
        n, r = fixture("coord3-model")
        n["viewport"].update(twist=math.pi/2, scale=2, target=[100,200,0], center=[20,40,0])
        self.assertAlmostEqual(paper([101,200,0], n["viewport"])[1], 42)
        a, reason = plan_one(n, r)
        self.assertIsNone(reason)
        self.assertAlmostEqual(a["planned_angle"], 90)

    def test_unknown_source_stops_before_aesthetic(self):
        n, r = fixture(); r["source"]["state"] = "unknown"
        self.assertEqual(plan_one(n, r)[1], "SOURCE_PENDING_BEFORE_PLACEMENT")

    def test_cancelled_source_requires_explicit_deletion(self):
        n, r = fixture(); r["source"]["state"] = "cancelled"
        self.assertIsNone(plan_one(n, r)[0])
        r["operation"] = "delete_cancelled"
        self.assertEqual(plan_one(n, r)[0]["operation"], "delete_cancelled")

    def test_good_existing_annotation_is_kept(self):
        n, r = fixture(); n["joint"]["status"] = "PASS"
        self.assertEqual(plan_one(n, r)[1], "KEEP_ACCEPTED_GEOMETRY")

    def test_coordinate_value_move_is_not_silently_applied(self):
        n, r = fixture("coord3-model"); r["target_world"] = [1,1,0]
        self.assertEqual(plan_one(n, r)[1], "COORDINATE_VALUE_CHANGE_USE_TYPED_RECIPE")

    def test_real_obstacle_blocks_but_soft_obstacle_does_not(self):
        n, r = fixture(); r["obstacles"] = [dict(role="hard", box=[-100,-100,100,100])]
        self.assertEqual(plan_one(n, r)[1], "NO_BOUNDED_CANDIDATE")
        r["obstacles"][0]["role"] = "soft"
        self.assertIsNotNone(plan_one(n, r)[0])
        self.assertTrue(segment_hits_box([0,0], [5,5], [2,2,3,3]))
        self.assertFalse(segment_hits_box([0,0], [1,1], [2,2,3,3]))

    def test_unknown_topology_does_not_enter_batch(self):
        n, r = fixture(); n["joint"]["native_segments_verified"] = False
        self.assertEqual(plan_one(n, r)[1], "NATIVE_ROLE_NOT_VERIFIED")

    def test_bad_request_does_not_block_other_objects(self):
        n, r = fixture(); bad = copy.deepcopy(r); bad["leader_lengths_paper"] = [None]
        result = build(dict(rows=[dict(handle="ABC", native=n)], document="test", host_pid=1), [bad, r], "test", "probe")
        self.assertEqual(len(result["pending"]), 1)
        self.assertEqual(len(result["actions"]), 1)

    def test_degenerate_or_nonfinite_rays_rejected(self):
        for args in (([0,0], [0,0], [1,0]), ([math.inf,0], [0,0], [1,0])):
            with self.assertRaises(ValueError): angle(*args)


if __name__ == "__main__":
    unittest.main()
