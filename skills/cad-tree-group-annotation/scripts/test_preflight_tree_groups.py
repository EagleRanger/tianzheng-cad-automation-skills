import copy
import hashlib
import tempfile
import unittest
from pathlib import Path

from preflight_tree_groups import audit_batch, audit_bindings


class TreeGroupGuardTests(unittest.TestCase):
    def setUp(self):
        self.plan = {
            "geometry_tolerance": 1e-8,
            "angle_tolerance_degrees": 0.1,
            "allowed_elbow_degrees": [90, 135],
            "tree_groups": [{
                "id": "g1", "quantity": 3,
                "members": [{"id": str(x), "center": [x, 0],
                             "center_basis": "validated_block_basepoint"} for x in [0, 4, 8]],
                "chain": [[0, 0], [4, 0], [8, 0]],
                "external": [[8, 0], [8, 4], [12, 4]],
            }],
        }

    def check(self, plan=None):
        return audit_batch(self.plan if plan is None else plan)

    def test_tail_and_head_are_accepted(self):
        self.assertEqual(self.check()["status"], "READY")
        self.plan["tree_groups"][0]["external"] = [[0, 0], [0, 4], [-4, 4]]
        self.assertEqual(self.check()["status"], "READY")

    def test_same_group_middle_is_rejected(self):
        self.plan["tree_groups"][0]["external"] = [[4, 0], [4, 4], [8, 4]]
        self.assertIn("EXTERNAL_ANCHOR_NOT_GROUP_ENDPOINT", self.check()["checks"][0]["errors"])

    def test_inside_canopy_is_not_symbol_center(self):
        self.plan["tree_groups"][0]["chain"][-1] = [8.1, 0]
        self.plan["tree_groups"][0]["external"][0] = [8.1, 0]
        self.assertIn("CHAIN_VERTEX_NOT_MEMBER_CENTER:2", self.check()["checks"][0]["errors"])

    def test_extra_tail_does_not_create_a_valid_end(self):
        self.plan["tree_groups"][0]["chain"].append([9, 0])
        self.plan["tree_groups"][0]["external"][0] = [9, 0]
        self.assertEqual(self.check()["status"], "BLOCKED")

    def test_duplicate_or_missing_member_cannot_pass(self):
        self.plan["tree_groups"][0]["chain"][1] = [0, 0]
        failures = self.check()["checks"][0]["errors"]
        self.assertIn("REPEATED_MEMBER_IN_CHAIN", failures)
        self.assertIn("MEMBER_CENTER_MISSING:4", failures)

    def test_unknown_center_does_not_block_independent_group(self):
        held = copy.deepcopy(self.plan["tree_groups"][0])
        held["id"] = "g2"
        held["members"][0]["center_basis"] = "bbox_midpoint_only"
        self.plan["tree_groups"].append(held)
        result = self.check()
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual(result["ready_ids"], ["g1"])
        self.assertEqual(result["hold_ids"], ["g2"])

    def test_explicit_local_hold_preserves_other_work(self):
        self.plan["tree_groups"].append({"id": "g2", "status": "hold", "reason": "COUNT_SOURCE_CONFLICT"})
        self.assertEqual(self.check()["ready_ids"], ["g1"])

    def test_quantity_conflict_fails(self):
        self.plan["tree_groups"][0]["quantity"] = 4
        self.assertIn("QUANTITY_MEMBER_MISMATCH", self.check()["checks"][0]["errors"])

    def test_nan_coordinate_and_degenerate_arm_fail(self):
        self.plan["tree_groups"][0]["chain"][0][0] = float("nan")
        self.assertEqual(self.check()["status"], "BLOCKED")
        self.setUp()
        self.plan["tree_groups"][0]["external"][1] = [8, 0]
        self.assertIn("DEGENERATE_EXTERNAL", self.check()["checks"][0]["errors"])

    def test_acute_arm_fails_and_135_passes(self):
        self.plan["tree_groups"][0]["external"] = [[8, 0], [8, 4], [12, 0]]
        self.assertIn("EXTERNAL_ELBOW_NOT_PERMITTED", self.check()["checks"][0]["errors"])
        self.plan["tree_groups"][0]["external"] = [[8, 0], [12, 4], [16, 4]]
        self.assertEqual(self.check()["status"], "READY")

    def test_unknown_tolerance_is_not_silently_assumed(self):
        self.plan["geometry_tolerance"] = 0
        with self.assertRaises(ValueError):
            self.check()

    def test_changed_receipt_file_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "consumer.py"
            path.write_text("first", encoding="utf-8")
            binding = {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            self.assertEqual(audit_bindings([binding]), [])
            path.write_text("second", encoding="utf-8")
            self.assertEqual(audit_bindings([binding])[0]["error"], "BINDING_HASH_CHANGED")


if __name__ == "__main__":
    unittest.main()
