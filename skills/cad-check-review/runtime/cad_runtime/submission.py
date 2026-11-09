"""Publish one final job and request atomically; do not wait or judge CAD results."""
from pathlib import Path
import hashlib,json
from .common import check
from .storage import encode,digest,atomic_new,lock
from .protocol import validate,BRIDGE_KINDS
from .host import process_identity
from .planning import build_job
from .session import snapshot

def submit(binding, kind, params, request_id, dry_run=False, probe=process_identity):
    validate(kind, params)
    project=Path(__file__).resolve().parents[3]
    if kind in ('hatch','groundcover_create','groundcover_update') and Path(binding['session_dir']).resolve().is_relative_to(project) and (project/'执行清单.md').is_file():
        from .project_flow import guard
        guard(project/'执行清单.md',kind)
    folder = Path(binding["session_dir"])
    semantic_hash = hashlib.sha256(json.dumps({"kind": kind, "params": params}, ensure_ascii=False, sort_keys=True, allow_nan=False).encode("utf-8")).hexdigest()
    with lock(folder):
        snap = snapshot(binding, probe)
        previous = [r for r in snap["requests"] if r.get("id") == request_id]
        if previous:
            check(len(previous) == 1 and previous[0].get("params_sha256") == semantic_hash, "REQUEST_ID_REUSED_WITH_DIFFERENT_CONTENT")
            return {"state": "ALREADY_SUBMITTED", "replayed": False, "existing": previous[0]}
        job = build_job(binding, kind, params, request_id, snap)
        use_bridge=kind in BRIDGE_KINDS or (kind=='erase' and all('block' in t for t in params['targets']))
        if use_bridge:
            from .bound_edits import verified_release
            verified_release(binding,kind)
        job_path = folder / (request_id + ".job.json")
        envelope = {"kind": kind, "job_path": str(job_path), "job_sha256": hashlib.sha256(encode(job)).hexdigest(),
                    "client_request_id": request_id, "params_sha256": semantic_hash}
        if dry_run:
            return {"state": "VALIDATED_NOT_SUBMITTED", "job": job, "request": envelope}
        if job_path.exists():
            check(job_path.read_bytes() == encode(job), "PREPARED_JOB_CONFLICT")
        else: atomic_new(job_path, job)
        # 原生会立即取request；此时job必须已经是最终字节，不先写__HASH__。
        check(digest(job_path) == envelope["job_sha256"], "FINAL_JOB_HASH_MISMATCH")
        fresh = snapshot(binding, probe)
        check(fresh["can_submit"] and fresh["saved_checkpoint"] == snap["saved_checkpoint"], "SESSION_CHANGED_BEFORE_PUBLISH")
        extra={}
        if use_bridge:
            from .bound_edits import publish
            extra=publish(binding,envelope,job_path,snap['saved_checkpoint'])
        else: atomic_new(folder / "request.json", envelope)
        return {"state": "SUBMITTED", "request_id": request_id, "receipt": job["receipt"],
                "saved": False, "next": "status读取原回执；不要重复submit或另造请求",**extra}
