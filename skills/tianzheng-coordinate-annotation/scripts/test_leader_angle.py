"""Geometry regressions; these do not establish native CAD drawing acceptance."""
import math
import unittest

from check_leader_angle import (check_horizontal_leader, check_leader_angle,
                                check_leader_joint)


class LeaderJointTests(unittest.TestCase):
    def test_mirrors_and_endpoint_order(self):
        for mirror in (-1, 1):
            e = (0, 0)
            t = (3 * mirror, 0)
            for p, expected_angle, expected_ok in [
                    ((2 * mirror, -2), 45, False),
                    ((0, -2), 90, True),
                    ((-2 * mirror, -2), 135, True)]:
                for leader in ((p, e), (e, p)):
                    for bearing in ((t, e), (e, t)):
                        with self.subTest(leader=leader, bearing=bearing):
                            r = check_leader_joint(leader, bearing)
                            self.assertEqual(r['ok'], expected_ok)
                            self.assertAlmostEqual(r['angle_degrees'], expected_angle)

    def test_rigid_transform_does_not_change_angle(self):
        for turn in (0, 0.3, 1.7, math.pi):
            def project(p):
                x, y = p
                return (2843000 + x * math.cos(turn) - y * math.sin(turn),
                        431000 + x * math.sin(turn) + y * math.cos(turn))
            r = check_leader_joint([project((-2, -2)), project((0, 0))],
                                   [project((0, 0)), project((-3, 0))])
            self.assertFalse(r['ok'])
            self.assertAlmostEqual(r['angle_degrees'], 45, places=6)

    def test_reverse_ray_would_hide_failure(self):
        self.assertFalse(check_leader_angle((-2, -2), (0, 0), (-3, 0))['ok'])
        self.assertTrue(check_leader_angle((-2, -2), (0, 0), (3, 0))['ok'])
        # Actual segment endpoint order cannot cause this ray reversal.
        for bearing in [((-3, 0), (0, 0)), ((0, 0), (-3, 0))]:
            self.assertFalse(check_leader_joint(((-2, -2), (0, 0)), bearing)['ok'])

    def test_missing_or_ambiguous_joint_is_not_a_pass(self):
        for a, b, reason in [
                (((-2, -2), (0, 0)), ((1, 0), (3, 0)), 'no_shared_endpoint'),
                (((0, -2), (0, 2)), ((-3, 0), (3, 0)), 'no_shared_endpoint'),
                (((0, 0), (3, 0)), ((3, 0), (0, 0)), 'ambiguous_shared_endpoints'),
                (((0, 0), (0, 0)), ((0, 0), (3, 0)), 'zero_length_segment')]:
            r = check_leader_joint(a, b)
            self.assertFalse(r['ok'])
            self.assertEqual(r['reason'], reason)

    def test_straight_mode_is_separate(self):
        self.assertFalse(check_leader_joint(((-2, 0), (0, 0)),
                                            ((0, 0), (3, 0)))['ok'])
        for pts in [[(-2, 0), (0, 0), (3, 0)], [(3, 0), (0, 0), (-2, 0)]]:
            self.assertTrue(check_horizontal_leader(pts)['ok'])
        self.assertFalse(check_horizontal_leader([(-2, 0), (0, 0), (-1, 0)])['ok'])

    def test_nonfinite_and_zero_rays(self):
        with self.assertRaises(ValueError):
            check_leader_joint(((float('nan'), 0), (0, 0)), ((0, 0), (3, 0)))
        self.assertFalse(check_leader_angle((0, 0), (0, 0), (3, 0))['ok'])


if __name__ == '__main__':
    unittest.main()
