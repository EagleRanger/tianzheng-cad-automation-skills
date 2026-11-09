"""Capture an already-positioned native view in the existing private desktop."""
from pathlib import Path
import re,subprocess
from .common import check
from .storage import read,atomic_new,lock
from .protocol import SUCCESS
from .machine import load_profile
from .session import snapshot
RUNTIME=Path(__file__).resolve().parent.parent

def capture(binding, request_id):
    """Capture the actual private-desktop CAD view; CapturePreviewImage is not a screen capture."""
    check(re.fullmatch(r"[A-Za-z0-9_-]{1,96}", request_id), "CAPTURE_ID_INVALID")
    folder = Path(binding["session_dir"])
    with lock(folder):
        snap = snapshot(binding)
        check(snap["can_submit"], "CAPTURE_SESSION_NOT_READY")
        job = read(folder / (request_id + ".job.json"))
        rec = read(job["receipt"])
        check(rec.get("status") == SUCCESS["inspect"] and job.get("image"), "CAPTURE_NEEDS_COMPLETED_VIEW_REQUEST")
        checkpoint = snap["saved_checkpoint"]
        check(rec.get("source_sha256") == checkpoint["last_sha256"], "CAPTURE_SAVED_POINT_CHANGED")
        result_path = folder / (request_id + ".capture.receipt.json")
        if result_path.exists():
            return read(result_path)
        manifest_path = folder / (request_id + ".capture.json")
        manifest = {"pid": binding["host"]["pid"], "live_document": checkpoint["live_document"],
                    "layout": job["layout"], "x": job["x"], "y": job["y"], "source_sha256": checkpoint["last_sha256"],
                    "image": str(folder / (request_id + ".cad.png")), "metadata": str(folder / (request_id + ".cad.meta.json")), "receipt": str(result_path)}
        if binding.get("environment"):
            environment = load_profile(binding["environment"])
            manifest.update({k: environment[k] for k in ("capture_script", "com_progid")})
        if manifest_path.exists():
            check(read(manifest_path) == manifest, "CAPTURE_MANIFEST_CHANGED")
            return {"status": "CAPTURE_IN_PROGRESS", "receipt": str(result_path)}
        atomic_new(manifest_path, manifest)
        quote = lambda s: "'" + str(s).replace("'", "''") + "'"
        script = folder / (request_id + ".capture.ps1")
        script.write_text("& " + quote((RUNTIME / "capture_private_session.ps1")) + " -Manifest " + quote(manifest_path), encoding="utf-8-sig")
        private = "HLBase736_" + binding["base_job_sha256"][:12]
        run = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                              str((RUNTIME / "run_private_cad_script.ps1")), "-Desktop", private, "-Script", str(script)],
                             capture_output=True, timeout=20, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result_path.exists(): return read(result_path)
        check(run.returncode == 0, "PRIVATE_CAPTURE_RUNNER_FAILED:" + run.stderr.decode("utf-8", errors="replace")[-500:])
        return {"status": "CAPTURE_IN_PROGRESS", "receipt": str(result_path)}
