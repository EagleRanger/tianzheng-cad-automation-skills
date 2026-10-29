"""Run only the three existing synthetic algorithm suites; never imports CAD."""
from pathlib import Path
import json
import os
import runpy
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
results = []
for name, count in (
    ("test_compile_selected_typed_segment_batch.py", 10),
    ("test_typed_dimension_quantified_common_band.py", 6),
):
    completed = subprocess.run(
        [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-p", name],
        cwd=root, text=True, capture_output=True, check=False,
    )
    results.append(dict(suite=name, runner="unittest", expected_cases=count,
                        returncode=completed.returncode,
                        stdout=completed.stdout, stderr=completed.stderr))
    if completed.returncode:
        print(json.dumps(dict(status="FAIL", suites=results, cad_calls=0)))
        raise SystemExit(1)

# These existing pytest-style functions use only tmp_path and the stdlib.
# Give each the same fresh-directory contract without installing pytest or
# changing any test assertion, algorithm or expected result.
namespace = runpy.run_path(str(root / "tests/test_native_dimension_semantics_v1.py"))
functions = [
    "test_arc_angle_and_line_length_semantics_pass",
    "test_arc_without_degree_marker_is_rejected",
    "test_line_with_degree_marker_is_rejected",
    "test_direct_native_property_is_accepted_when_explode_text_is_missing",
]
for name in functions:
    with tempfile.TemporaryDirectory(prefix="cad_offline_semantics_") as directory:
        namespace[name](Path(directory))
results.append(dict(suite="test_native_dimension_semantics_v1.py",
                    runner="existing_functions_with_fresh_tmp_path_stdlib_adapter",
                    cases=len(functions), returncode=0))
print(json.dumps(dict(status="PASS_OFFLINE_SYNTHETIC_ONLY", cases=20,
                      suites=results, cad_calls=0), ensure_ascii=False))
