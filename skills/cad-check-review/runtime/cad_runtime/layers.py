"""Bound, read-only global layer state; never thaw, open, save or choose a drawing."""
from pathlib import Path
import re, subprocess
from .common import check
from .storage import read, atomic_new, lock
from .session import snapshot
from .machine import load_profile

RUNTIME = Path(__file__).resolve().parent.parent


def read_layers(binding, request_id, names):
    check(isinstance(request_id, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,72}", request_id), "LAYER_QUERY_ID_INVALID")
    check(isinstance(names, list) and 0 < len(names) <= 64 and all(isinstance(n, str) and n.strip() for n in names), "EXACT_LAYER_NAMES_REQUIRED")
    names = sorted(set(names))
    folder = Path(binding["session_dir"])
    with lock(folder):
        snap = snapshot(binding)
        check(snap["can_submit"], "LAYER_QUERY_SESSION_NOT_READY")
        point = snap["saved_checkpoint"]
        manifest_path = folder / (request_id + ".layers.json")
        result_path = folder / (request_id + ".layers.receipt.json")
        manifest = {"host": binding["host"], "document": point["live_document"],
                    "saved_path": point["last_saved"], "source_sha256": point["last_sha256"],
                    "session_status": str(folder / "session_status.json"), "names": names,
                    "receipt": str(result_path), "com_progid": "AutoCAD.Application.24"}
        if binding.get("environment"):
            manifest["com_progid"] = load_profile(binding["environment"])["com_progid"]
        if manifest_path.exists():
            check(read(manifest_path) == manifest, "LAYER_QUERY_ID_REUSED_FOR_DIFFERENT_INPUT")
            if result_path.exists():
                result = read(result_path)
                check(result.get("status") == "READ_ONLY_LAYER_STATE", "LAYER_QUERY_FAILED:" + str(result.get("error")))
                return {**result, "reused_snapshot": True}
            return {"status": "LAYER_QUERY_PENDING", "receipt": str(result_path), "replayed": False}
        check(not result_path.exists(), "ORPHAN_LAYER_RECEIPT")
        atomic_new(manifest_path, manifest)
        quote = lambda s: "'" + str(s).replace("'", "''") + "'"
        script = manifest_path.with_suffix(".ps1")
        script.write_text("& " + quote(RUNTIME / "read_cad_layers.ps1") + " -Manifest " + quote(manifest_path), encoding="utf-8-sig")
        private = "HLBase736_" + binding["base_job_sha256"][:12]
        run = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                              str(RUNTIME / "run_private_cad_script.ps1"), "-Desktop", private, "-Script", str(script)],
                             capture_output=True, timeout=20, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result_path.exists():
            result = read(result_path)
            check(result.get("status") == "READ_ONLY_LAYER_STATE", "LAYER_QUERY_FAILED:" + str(result.get("error")))
            return {**result, "reused_snapshot": False}
        check(run.returncode == 0, "LAYER_QUERY_HELPER_FAILED:" + run.stderr.decode(errors="replace")[-400:])
        return {"status": "LAYER_QUERY_PENDING", "receipt": str(result_path), "replayed": False}
