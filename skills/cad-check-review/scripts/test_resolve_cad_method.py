import json
import tempfile
import unittest
from pathlib import Path

from resolve_cad_method import INDEX_PATH, expand_path, match_modules, resolve_module, workflow


class CadMethodResolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))

    def test_tree_retrieves_actual_tree_skill(self):
        result = match_modules(self.index, "乔木串线头尾和图例中心")
        self.assertEqual(result[0]["module"], "tree")
        self.assertTrue(resolve_module(self.index, "tree")["skill_path"].endswith("cad-tree-group-annotation\\SKILL.md")
                        or resolve_module(self.index, "tree")["skill_path"].endswith("cad-tree-group-annotation/SKILL.md"))

    def test_hatch_does_not_dispatch_to_plant_label(self):
        self.assertEqual(match_modules(self.index, "GRASS填充闭区与农田切割")[0]["module"], "hatch")

    def test_interface_and_landscape_cleanup_reach_both_review_rules(self):
        routes = [r["module"] for r in match_modules(self.index, "坝端汀步接边，清除坝面多余绿化范围和图例")[:3]]
        for key in ("geometry", "hatch"):
            self.assertIn(key, routes)
            refs = resolve_module(self.index, key)["sources"]
            rule = next(r for r in refs if "接头留删和区域清理" in r["sections"])
            self.assertIn("### 接头留删和区域清理", Path(rule["path"]).read_text(encoding="utf-8"))

    def test_coordinate_and_elevation_are_distinct(self):
        self.assertEqual(match_modules(self.index, "坐标轴序和真实测点")[0]["module"], "coordinate")
        self.assertEqual(match_modules(self.index, "标高符号与文字脱离")[0]["module"], "elevation")

    def test_query_ambiguity_does_not_claim_runtime_authority(self):
        matches = match_modules(self.index, "布局字高和文字压线")
        self.assertGreaterEqual(len(matches), 2)
        for match in matches:
            resolved = resolve_module(self.index, match["module"])
            self.assertFalse(resolved["runtime_authorization"])
            self.assertFalse(resolved["current_drawing_accepted"])

    def test_no_match_is_not_guessed(self):
        self.assertEqual(match_modules(self.index, "unregistered_object_foobar"), [])

    def test_workflow_references_known_modules_in_order(self):
        stages = workflow(self.index)
        self.assertIn("source", stages[0]["modules"])
        self.assertIn("delivery", stages[-1]["modules"])
        positions = {s["id"]: i for i, s in enumerate(stages)}
        for i, stage in enumerate(stages):
            for dependency in stage.get("depends_on", []):
                self.assertLess(positions[dependency], i)

    def test_registered_local_paths_are_currently_readable(self):
        failures = {key: resolve_module(self.index, key)["missing_paths"]
                    for key in self.index["modules"] if resolve_module(self.index, key)["missing_paths"]}
        self.assertEqual(failures, {})

    def test_missing_method_is_not_claimed_ready(self):
        item = {"library_root": ".", "modules": {"x": {
            "label": "x", "skill": "@skills/missing/SKILL.md", "tags": ["x"],
            "sources": [], "implementations": [], "required_current_facts": [], "acceptance": []}}}
        with tempfile.TemporaryDirectory() as folder:
            result = resolve_module(item, "x", Path(folder))
            self.assertEqual(result["status"], "METHOD_PATH_GAPS")
            self.assertFalse(result["runtime_authorization"])


if __name__ == "__main__":
    unittest.main()
