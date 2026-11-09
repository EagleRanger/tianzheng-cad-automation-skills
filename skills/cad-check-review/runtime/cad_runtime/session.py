"""Observe bound host, checkpoint and settlement; no startup or publication."""
from pathlib import Path
import re
from .common import ClientError,check
from .storage import read,digest,same
from .host import process_identity
from .receipts import request_records,settled

def snapshot(binding, probe=process_identity):
    folder = Path(binding["session_dir"])
    result = {"session_dir": str(folder), "state": "HOLD", "can_submit": False, "issues": [], "warnings": [], "requests": []}
    try:
        result["requests"] = request_records(folder)
        if binding.get("environment"):
            check(digest(binding["environment"]) == binding.get("environment_sha256"), "MACHINE_ENVIRONMENT_CHANGED")
        check(digest(binding["base_job"]) == binding["base_job_sha256"], "BASE_JOB_CHANGED")
        config = read(binding["base_job"])
        # The launcher removes its trusted DLL after CAD exits. Report the dead
        # host first instead of misdiagnosing that cleanup as the root failure.
        check(probe(binding["host"]["pid"]) == binding["host"], "HOST_IDENTITY_CHANGED")
        if any(same(config["terrain"], config[k]) for k in ("garden", "planting")):
            result["warnings"].append("TERRAIN_ALIASES_PRIMARY_DRAWING: 旧会话把地形字段指向主图；READY只代表队列可用，真实外参/定位未验证，不据此判断图纸正确")
        check(digest(binding["loaded_dll"]) == binding["loaded_dll_sha256"], "LOADED_DLL_CHANGED")
        if not (folder / "session_status.json").exists():
            check(probe(binding["host"]["pid"]) == binding["host"], "HOST_IDENTITY_CHANGED")
            result["state"] = "STARTING_OR_BOOT_FAILED"
            raise ClientError("尚无原生就绪回执；只核本次启动输出，不启动第二个宿主")
        status = read(folder / "session_status.json")
        result["saved_checkpoint"] = {k: status.get(k) for k in ("last_saved", "last_sha256", "live_document", "pid")}
        check(probe(status["pid"]) == binding["host"], "HOST_IDENTITY_CHANGED")
        check(status.get("status") == "READY_SAME_DOCUMENT", "NATIVE_NOT_READY")
        check(same(Path(status["last_saved"]).parent, folder) and Path(status["last_saved"]).is_file(), "CHECKPOINT_MISSING_OR_OUTSIDE_SESSION")
        check(bool(re.fullmatch(r"[a-f0-9]{64}", status["last_sha256"])), "CHECKPOINT_HASH_INVALID")
        if (folder / "session_failure.json").exists():
            result["failure_receipt"] = str(folder / "session_failure.json")
            raise ClientError("NATIVE_FAILURE: 失败回执优先于旧READY；禁止原样重试")
        for rec in result["requests"]:
            if rec["state"] == "RECEIPTED" and rec["kind"] == "switch":
                # 切换回执写在Open之前，必须等同一宿主State更新后才算可续发。
                if (folder / "session_status.json").stat().st_mtime_ns <= Path(rec["receipt"]).stat().st_mtime_ns:
                    rec["state"] = "SWITCH_NOT_SETTLED"
        pending = [r for r in result["requests"] if not settled(r)]
        if pending:
            result["state"] = "PENDING_OR_UNSETTLED"
            result["issues"].append("已有排队、受理未回执或未核实请求；先沿原回执处理，不能重发/再发")
        else:
            result["state"] = "READY"; result["can_submit"] = True
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result["issues"].append(str(exc))
    result["next_action"] = "按唯一清单当前项，参数确定后submit一次（自动校验）；草案预演才用prepare" if result["can_submit"] else "读取本结果指出的具体回执/未决请求；同宿主不续发，不重扫历史、不自行重启"
    return result
