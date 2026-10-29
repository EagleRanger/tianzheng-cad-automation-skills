import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "compile_selected_typed_segment_batch.py"


class CompileSelectedTypedSegmentBatchTests(unittest.TestCase):
    def run_compile(
        self,
        ledger_text: str,
        source_handles: str = "",
        expected_drawing: str = r"C:\work\mixed.dwg",
        drawing_binding: str = "owner-state",
        cleanup_handles: str = "",
        source_offsets: str = "",
        segment_offsets: str = "",
    ):
        folder = tempfile.TemporaryDirectory()
        root = Path(folder.name)
        ledger = root / "ledger.tsv"
        output = root / "task.lsp"
        report = root / "report.json"
        ledger.write_text(ledger_text, encoding="utf-8")
        command = [
                sys.executable,
                str(SCRIPT),
                "--ledger",
                str(ledger),
                "--output",
                str(output),
                "--report",
                str(report),
                "--expected-drawing",
                expected_drawing,
                "--drawing-binding",
                drawing_binding,
                "--offset",
                "2.17770",
                "--group",
                "SHORE",
            ]
        if source_handles:
            command.extend(["--source-handles", source_handles])
        if cleanup_handles:
            command.extend(["--cleanup-handles", cleanup_handles])
        if source_offsets:
            command.extend(["--source-offsets", source_offsets])
        if segment_offsets:
            command.extend(["--segment-offsets", segment_offsets])
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
        )
        return folder, completed, output, report

    def test_arc_line_arc_is_emitted_in_original_index_order(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t2\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "652B5\t1\tLINE\tDEFERRED_LENGTH_DIMENSION\n"
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = output.read_text(encoding="ascii")
            self.assertIn(
                '("652B5" (("ARC" 0) ("LINE" 1) ("ARC" 2)) 2.1777 "SHORE")',
                text,
            )
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["dispatch_mode"], "AUTO_TYPED")
            self.assertEqual(payload["target_segment_count"], 3)
            self.assertEqual(payload["arc_segment_count"], 2)
            self.assertEqual(payload["line_segment_count"], 1)
            self.assertEqual(payload["silent_deferred_line_count"], 0)
        finally:
            folder.cleanup()

    def test_unclassified_segment_fails_before_task_spec_is_written(self):
        folder, completed, output, _ = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B4\t7\tUNCLASSIFIED\tREQUIRES_GEOMETRY_PROBE\n"
        )
        try:
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("UNCLASSIFIED_SEGMENT_FORBIDDEN", completed.stderr)
            self.assertFalse(output.exists())
        finally:
            folder.cleanup()

    def test_line_cannot_be_silently_marked_as_angle_or_ignored(self):
        folder, completed, output, _ = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t1\tLINE\tANGLE_DIMENSION_THIS_PASS\n"
        )
        try:
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("LINE_DISPOSITION_MISMATCH", completed.stderr)
            self.assertFalse(output.exists())
        finally:
            folder.cleanup()

    def test_duplicate_source_segment_fails_closed(self):
        folder, completed, _, _ = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
        )
        try:
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("DUPLICATE_SOURCE_SEGMENT", completed.stderr)
        finally:
            folder.cleanup()

    def test_exact_source_subset_does_not_inherit_other_source_failure(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "652B5\t1\tLINE\tDEFERRED_LENGTH_DIMENSION\n"
            "652B4\t7\tUNCLASSIFIED\tREQUIRES_GEOMETRY_PROBE\n",
            source_handles="652B5",
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(output.exists())
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["source_handles"], ["652B5"])
            self.assertEqual(payload["target_segment_count"], 2)
        finally:
            folder.cleanup()

    def test_chinese_drawing_path_is_reported_but_not_embedded_in_ascii_spec(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n",
            expected_drawing=r"C:\work\阶段03_工作稿.dwg",
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = output.read_text(encoding="ascii")
            self.assertIn('(setq cx:*full-batch-expected-drawing* "")', text)
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["drawing_binding"], "owner-state")
            self.assertEqual(
                payload["expected_drawing"], "C:/work/阶段03_工作稿.dwg"
            )

        finally:
            folder.cleanup()

    def test_chinese_drawing_path_cannot_be_embedded_in_ascii_spec(self):
        folder, completed, output, _ = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n",
            expected_drawing=r"C:\work\阶段03_工作稿.dwg",
            drawing_binding="embedded",
        )
        try:
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn(
                "EMBEDDED_EXPECTED_DRAWING_MUST_BE_ASCII",
                completed.stderr,
            )
            self.assertFalse(output.exists())
        finally:
            folder.cleanup()

    def test_opposite_side_retry_can_replace_only_validated_native_handles(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "652B5\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n",
            cleanup_handles="6B778,6B779",
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = output.read_text(encoding="ascii")
            self.assertIn(
                '(setq cx:*full-batch-cleanup-handles* \'("6B778" "6B779"))',
                text,
            )
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["cleanup_handles"], ["6B778", "6B779"])
        finally:
            folder.cleanup()

    def test_per_source_signed_offsets_preserve_one_complete_batch(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "EA8\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "EF4\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n",
            source_offsets="EA8=7,EF4=-7",
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = output.read_text(encoding="ascii")
            self.assertIn('("EA8" (("ARC" 0)) 7 "SHORE")', text)
            self.assertIn('("EF4" (("ARC" 0)) -7 "SHORE")', text)
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["offset_mode"], "PER_SOURCE")
            self.assertEqual(payload["source_offsets"], {"EA8": 7.0, "EF4": -7.0})
            self.assertEqual(payload["target_segment_count"], 2)
        finally:
            folder.cleanup()

    def test_segment_offset_override_splits_source_without_losing_scope(self):
        folder, completed, output, report = self.run_compile(
            "SOURCE_HANDLE\tSEGMENT_INDEX\tSEGMENT_TYPE\tDISPOSITION\n"
            "EA8\t0\tARC\tANGLE_DIMENSION_THIS_PASS\n"
            "EA8\t1\tLINE\tLENGTH_DIMENSION_THIS_PASS\n"
            "EA8\t2\tARC\tANGLE_DIMENSION_THIS_PASS\n",
            source_offsets="EA8=7",
            segment_offsets="EA8:2=10",
        )
        try:
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = output.read_text(encoding="ascii")
            self.assertIn('("EA8" (("ARC" 0) ("LINE" 1)) 7 "SHORE")', text)
            self.assertIn('("EA8" (("ARC" 2)) 10 "SHORE")', text)
            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(payload["target_segment_count"], 3)
            self.assertEqual(payload["offset_mode"], "PER_SEGMENT_OVERRIDE")
            self.assertEqual(payload["segment_offsets"], {"EA8:2": 10.0})
        finally:
            folder.cleanup()


if __name__ == "__main__":
    unittest.main()
