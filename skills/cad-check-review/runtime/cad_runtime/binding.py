"""Persist only the original project session pointer; never choose a business source."""
from pathlib import Path
import json,os,tempfile
from .common import check
from .storage import read,digest,encode,same,lock
from .host import process_identity
from .machine import load_profile
STATE=Path(__file__).resolve().parents[2]/"execution_status.json"

def update_pointer(binding, state_path=STATE):
    """只更换原技术状态中的session_client；并发变化时拒绝丢失别人的更新。"""
    state_path = Path(state_path)
    with lock(state_path.parent):
        original = state_path.read_bytes(); state = json.loads(original.decode("utf-8-sig"))
        state["session_client"] = binding
        fd, temporary = tempfile.mkstemp(prefix=".state-", dir=state_path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(encode(state)); stream.flush(); os.fsync(stream.fileno())
            check(state_path.read_bytes() == original, "STATE_CHANGED: 原状态被其他责任人更新，请重新绑定一次")
            os.replace(temporary, state_path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)

def load_binding(state_path=STATE):
    binding = read(state_path).get("session_client")
    check(binding is not None, "SESSION_UNBOUND: 宿主创建/恢复后用bind登记一次；换模型无需重新绑定")
    return binding

def bind(job, launch=None, loaded_dll=None, state_path=STATE):
    job = Path(job).resolve(); job_hash = digest(job)
    launch = Path(launch or Path(os.environ["TEMP"]) / ("HLBase736_" + job_hash[:12]) / "launch.json").resolve()
    loaded_dll = Path(loaded_dll or Path(os.environ["APPDATA"]) / "Tangent/TArch20V10/sys" / ("HLNativeV736_" + job_hash[:12] + ".dll")).resolve()
    folder = job.parent; config = read(job); started = read(launch)
    if (folder / "session_status.json").exists():
        check(read(folder / "session_status.json")["pid"] == started["pid"], "LAUNCH_PID_MISMATCH")
    check(started.get("status") == "PRIVATE_DESKTOP_PROCESS_STARTED", "PRIVATE_HOST_REQUIRED")
    check(digest(job) in str(launch.parent.name) or launch.parent.name.endswith(digest(job)[:12]), "LAUNCH_JOB_MISMATCH")
    initial_role = config.get("initial_role", "garden")
    check(initial_role in ("garden", "planting"), "INITIAL_ROLE_INVALID")
    check(same(config[initial_role], started["candidate"]) and config[initial_role + "_sha256"] == started["candidate_sha256"], "LAUNCH_INPUT_MISMATCH")
    check(loaded_dll.name == "HLNativeV736_" + digest(job)[:12] + ".dll", "LOADED_DLL_IDENTITY_REQUIRED")
    for key in ("garden", "planting", "terrain"):
        check(same(Path(config[key]).parent, folder), "SESSION_INPUT_OUTSIDE_JOB_DIRECTORY:" + key)
    binding = {"protocol": "V736", "session_dir": str(folder), "base_job": str(job),
               "base_job_sha256": digest(job), "launch": str(launch),
               "host": process_identity(started["pid"]), "loaded_dll": str(loaded_dll),
               "loaded_dll_sha256": digest(loaded_dll)}
    if started.get("environment"):
        load_profile(started["environment"])
        binding["environment"] = str(Path(started["environment"]).resolve())
        binding["environment_sha256"] = digest(binding["environment"])
    update_pointer(binding, state_path)
    return binding
