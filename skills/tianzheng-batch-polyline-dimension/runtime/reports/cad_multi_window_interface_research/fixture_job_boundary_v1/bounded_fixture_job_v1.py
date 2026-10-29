"""Private Windows-only, fixed Python microprobes; NOT a CAD launcher.

No third-party packages, runtime compiler, arbitrary executable, PID attachment,
breakaway, or existing-process termination. Kernel boundary before child code.
Launch using the bound PowerShell parent, python -I -S, on a fresh case directory.
"""
import ctypes as C
from ctypes import wintypes as W
import os
import sys
import time

if os.name != "nt" or C.sizeof(C.c_void_p) != 8:
    raise SystemExit("REQUIRES_WINDOWS_X64")

K = C.WinDLL("kernel32", use_last_error=True)
SIZE = C.c_size_t
HANDLE = W.HANDLE
DWORD = W.DWORD
BOOL = W.BOOL
PTR = C.c_void_p
U64 = C.c_ulonglong


class BasicLimits(C.Structure):
    _fields_ = [("process_time", C.c_longlong), ("job_time", C.c_longlong),
                ("flags", DWORD), ("minimum_ws", SIZE), ("maximum_ws", SIZE),
                ("active_limit", DWORD), ("affinity", SIZE),
                ("priority", DWORD), ("scheduling", DWORD)]


class IoCounters(C.Structure):
    _fields_ = [(name, U64) for name in
                ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]


class ExtendedLimits(C.Structure):
    _fields_ = [("basic", BasicLimits), ("io", IoCounters),
                ("process_memory", SIZE), ("job_memory", SIZE),
                ("peak_process_memory", SIZE), ("peak_job_memory", SIZE)]


class Accounting(C.Structure):
    _fields_ = [("user", C.c_longlong), ("kernel", C.c_longlong),
                ("period_user", C.c_longlong), ("period_kernel", C.c_longlong),
                ("faults", DWORD), ("total", DWORD), ("active", DWORD), ("terminated", DWORD)]


class MemoryStatus(C.Structure):
    _fields_ = [("length", DWORD), ("load", DWORD)] + [(name, U64) for name in
                ("physical_total", "physical_free", "commit_total", "commit_free",
                 "virtual_total", "virtual_free", "extended_free")]


class Security(C.Structure):
    _fields_ = [("length", DWORD), ("descriptor", PTR), ("inherit", BOOL)]


class Startup(C.Structure):
    _fields_ = [("size", DWORD), ("reserved", W.LPWSTR), ("desktop", W.LPWSTR),
                ("title", W.LPWSTR)] + [(name, DWORD) for name in
                ("x", "y", "x_size", "y_size", "x_chars", "y_chars", "fill", "flags")] + [
                ("show", W.WORD), ("reserved_bytes", W.WORD), ("reserved_ptr", PTR),
                ("stdin", HANDLE), ("stdout", HANDLE), ("stderr", HANDLE)]


class StartupEx(C.Structure):
    _fields_ = [("base", Startup), ("attributes", PTR)]


class ProcessInfo(C.Structure):
    _fields_ = [("process", HANDLE), ("thread", HANDLE), ("pid", DWORD), ("tid", DWORD)]


def api(name, result, args):
    fn = getattr(K, name)
    fn.restype, fn.argtypes = result, args
    return fn


create_job = api("CreateJobObjectW", HANDLE, [PTR, W.LPCWSTR])
set_job = api("SetInformationJobObject", BOOL, [HANDLE, C.c_int, PTR, DWORD])
query_job = api("QueryInformationJobObject", BOOL, [HANDLE, C.c_int, PTR, DWORD, PTR])
assign_job = api("AssignProcessToJobObject", BOOL, [HANDLE, HANDLE])
current_process = api("GetCurrentProcess", HANDLE, [])
close_handle = api("CloseHandle", BOOL, [HANDLE])
terminate_job = api("TerminateJobObject", BOOL, [HANDLE, W.UINT])
memory_status = api("GlobalMemoryStatusEx", BOOL, [C.POINTER(MemoryStatus)])
create_pipe = api("CreatePipe", BOOL, [C.POINTER(HANDLE), C.POINTER(HANDLE), C.POINTER(Security), DWORD])
set_handle = api("SetHandleInformation", BOOL, [HANDLE, DWORD, DWORD])
create_file = api("CreateFileW", HANDLE, [W.LPCWSTR, DWORD, DWORD, C.POINTER(Security), DWORD, DWORD, HANDLE])
init_attrs = api("InitializeProcThreadAttributeList", BOOL, [PTR, DWORD, DWORD, C.POINTER(SIZE)])
update_attr = api("UpdateProcThreadAttribute", BOOL, [PTR, DWORD, SIZE, PTR, SIZE, PTR, PTR])
delete_attrs = api("DeleteProcThreadAttributeList", None, [PTR])
create_process = api("CreateProcessW", BOOL, [W.LPCWSTR, W.LPWSTR, PTR, PTR, BOOL, DWORD, PTR,
                                               W.LPCWSTR, C.POINTER(StartupEx), C.POINTER(ProcessInfo)])
resume_thread = api("ResumeThread", DWORD, [HANDLE])
wait_handle = api("WaitForSingleObject", DWORD, [HANDLE, DWORD])
exit_code = api("GetExitCodeProcess", BOOL, [HANDLE, C.POINTER(DWORD)])
peek_pipe = api("PeekNamedPipe", BOOL, [HANDLE, PTR, DWORD, PTR, C.POINTER(DWORD), PTR])
read_pipe = api("ReadFile", BOOL, [HANDLE, PTR, DWORD, C.POINTER(DWORD), PTR])
process_times = api("GetProcessTimes", BOOL, [HANDLE, C.POINTER(W.FILETIME), C.POINTER(W.FILETIME),
                                               C.POINTER(W.FILETIME), C.POINTER(W.FILETIME)])
image_name = api("QueryFullProcessImageNameW", BOOL, [HANDLE, DWORD, W.LPWSTR, C.POINTER(DWORD)])
is_in_job = api("IsProcessInJob", BOOL, [HANDLE, HANDLE, C.POINTER(BOOL)])


def checked(value, operation):
    if not value:
        raise OSError(C.get_last_error(), operation)
    return value


def new_job(process_mib, total_mib, active):
    handle = checked(create_job(None, None), "CreateJobObjectW")
    limits = ExtendedLimits()
    # ACTIVE_PROCESS | PROCESS_MEMORY | JOB_MEMORY | KILL_ON_JOB_CLOSE.
    # No BREAKAWAY_OK or SILENT_BREAKAWAY_OK. Job handle is not inheritable.
    limits.basic.flags = 0x8 | 0x100 | 0x200 | 0x2000
    limits.basic.active_limit = active
    limits.process_memory = process_mib * 1024 * 1024
    limits.job_memory = total_mib * 1024 * 1024
    try:
        checked(set_job(handle, 9, C.byref(limits), C.sizeof(limits)), "SetJobExtendedLimits")
        return handle
    except BaseException:
        close_handle(handle)
        raise


# Minimal bootstrap: only fixed stdlib/native declarations above, no file input,
# third-party/site imports, child process, runtime compilation, or user workload.
# Parent enforces the separate bootstrap time/observed-memory watchdog.
BOOTSTRAP_JOB = new_job(256, 384, 3)
try:
    checked(assign_job(BOOTSTRAP_JOB, current_process()), "BindBootstrapJobNoBreakaway")
except BaseException:
    close_handle(BOOTSTRAP_JOB)
    raise
# Retain the sole non-inherited handle until normal process exit; do not close it
# early and kill ourselves before final evidence is flushed.

import json
import hashlib
import subprocess

MAX_STREAM = 65536
MAX_LOG = 262144
ALLOWED = {"validate", "normal", "timeout", "output", "memory"}


class Journal:
    def __init__(self, directory):
        if not os.path.isabs(directory) or not os.path.isdir(directory):
            raise ValueError("CASE_DIRECTORY_REQUIRED")
        self.directory = directory
        self.sequence = 0
        self.bytes = 0
        self.stream = open(os.path.join(directory, "stages.jsonl"), "xb", buffering=0)

    def write(self, stage, **facts):
        self.sequence += 1
        row = dict(sequence=self.sequence, utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   monotonic=time.monotonic(), stage=stage, **facts)
        payload = (json.dumps(row, ensure_ascii=True, separators=(",", ":")) + "\n").encode("ascii")
        if len(payload) > 8192 or self.bytes + len(payload) > MAX_LOG:
            raise ValueError("JOURNAL_LIMIT")
        self.stream.write(payload)
        os.fsync(self.stream.fileno())
        self.bytes += len(payload)

    def finish(self, result):
        with open(os.path.join(self.directory, "result.json"), "x", encoding="utf-8") as stream:
            json.dump(result, stream, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())


def query_active(job):
    value = Accounting()
    checked(query_job(job, 1, C.byref(value), C.sizeof(value), None), "QueryJobAccounting")
    return value.active


def job_limits(job):
    value = ExtendedLimits()
    checked(query_job(job, 9, C.byref(value), C.sizeof(value), None), "QueryJobLimits")
    return {"flags": value.basic.flags, "process_bytes": value.process_memory,
            "job_bytes": value.job_memory, "active_limit": value.basic.active_limit,
            "peak_process_bytes": value.peak_process_memory, "peak_job_bytes": value.peak_job_memory}


def read_chunk(handle, total, captured):
    available = DWORD()
    if not peek_pipe(handle, None, 0, None, C.byref(available), None):
        if C.get_last_error() == 109:
            return total, captured, True
        raise OSError(C.get_last_error(), "PeekNamedPipe")
    if available.value:
        buffer = C.create_string_buffer(min(4096, available.value))
        got = DWORD()
        checked(read_pipe(handle, buffer, len(buffer), C.byref(got), None), "ReadPipe")
        total += got.value
        captured.extend(buffer.raw[:min(got.value, max(0, MAX_STREAM - len(captured)))])
    return total, captured, False


def run_probe(mode, directory):
    # These are deliberately finite microprobes, not arbitrary code inputs.
    scripts = {
        "normal": "import os;os.write(1,b'FIXTURE_OK\\n');os.write(2,b'ERR_OK\\n')",
        "timeout": "import time;time.sleep(5)",
        "output": "import os;[(os.write(1,b'x'*4096),os.write(2,b'y'*4096)) for _ in range(20)]",
        "memory": "import sys\ntry:\n x=bytearray(96*1024*1024);sys.exit(7)\nexcept MemoryError:\n print('MEMORY_LIMIT_OBSERVED');sys.exit(23)",
    }
    journal = Journal(directory)
    status = MemoryStatus()
    status.length = C.sizeof(status)
    checked(memory_status(C.byref(status)), "GlobalMemoryStatusEx")
    journal.write("BOOTSTRAP_BOUND", pid=os.getpid(), kernel_limits=job_limits(BOOTSTRAP_JOB),
                  physical_free=status.physical_free, commit_free=status.commit_free,
                  cad_calls=0, bootstrap_prebind_is_not_claimed_kernel_capped=True)
    if min(status.physical_free, status.commit_free) < 4 * 1024**3:
        raise ValueError("INSUFFICIENT_SYSTEM_HEADROOM_NO_CHILD")
    if mode == "validate":
        result = dict(status="PASS_BOOTSTRAP_ONLY_NO_CHILD", limits=job_limits(BOOTSTRAP_JOB),
                      child_count=0, cad_calls=0)
        journal.write("VALIDATED_NO_CHILD")
        journal.finish(result)
        return result

    job = None
    attributes = None
    initialized = False
    handles = []
    pi = ProcessInfo()
    created = False
    root_exited = False
    active = None
    out_eof = err_eof = False
    totals = [0, 0]
    captures = [bytearray(), bytearray()]
    reason = "NATURAL_EXIT"
    operation_error = None
    cleanup_errors = []
    child_limits = None
    root_identity = None
    code = None
    try:
        job = new_job(64, 96, 1)
        journal.write("JOB_CONFIGURED", mode=mode, limits=job_limits(job))
        security = Security(C.sizeof(Security), None, True)
        reads, writes = [], []
        for _ in range(2):
            read, write = HANDLE(), HANDLE()
            checked(create_pipe(C.byref(read), C.byref(write), C.byref(security), 4096), "CreatePipe")
            handles.extend([read.value, write.value])
            checked(set_handle(read, 1, 0), "DisableReadHandleInheritance")
            reads.append(read.value)
            writes.append(write.value)
        stdin = create_file("NUL", 0x80000000, 3, C.byref(security), 3, 0, None)
        if stdin == C.c_void_p(-1).value:
            raise OSError(C.get_last_error(), "OpenNulStdin")
        handles.append(stdin)
        required = SIZE()
        init_attrs(None, 2, 0, C.byref(required))
        if required.value <= 0 or required.value > 65536:
            raise ValueError("ATTRIBUTE_SIZE_REJECTED")
        attributes = C.create_string_buffer(required.value)
        checked(init_attrs(attributes, 2, 0, C.byref(required)), "InitializeAttributes")
        initialized = True
        inherit_list = (HANDLE * 3)(stdin, *writes)
        # Atomic at CreateProcess: no suspended-but-unassigned orphan window.
        job_list = (HANDLE * 1)(job)
        checked(update_attr(attributes, 0, 0x20002, inherit_list, C.sizeof(inherit_list), None, None),
                "SetExplicitStdioHandleList")
        checked(update_attr(attributes, 0, 0x2000D, job_list, C.sizeof(job_list), None, None),
                "SetAtomicJobList")
        startup = StartupEx()
        startup.base.size = C.sizeof(startup)
        startup.base.flags = 0x100 | 1
        startup.base.show = 0
        startup.base.stdin, startup.base.stdout, startup.base.stderr = stdin, writes[0], writes[1]
        startup.attributes = C.cast(attributes, PTR)
        command = C.create_unicode_buffer(subprocess.list2cmdline([sys.executable, "-I", "-S", "-c", scripts[mode]]))
        journal.write("CREATE_INTENT", mode=mode, kernel_job_list=True, inherit_only_stdio=True,
                      executable=sys.executable, seconds=0.6 if mode == "timeout" else 3.0)
        checked(create_process(sys.executable, command, None, None, True,
                               0x08000000 | 0x00080000 | 0x4, None, directory,
                               C.byref(startup), C.byref(pi)), "CreateAtomicJobProcess")
        created = True
        for write in writes:
            checked(close_handle(write), "CloseParentChildWriter")
            handles.remove(write)
        checked(close_handle(stdin), "CloseParentChildStdin")
        handles.remove(stdin)
        member = BOOL()
        checked(is_in_job(pi.process, job, C.byref(member)), "CheckChildJobMembership")
        if not member.value:
            raise ValueError("CREATED_PROCESS_NOT_IN_JOB")
        timestamps = [W.FILETIME() for _ in range(4)]
        checked(process_times(pi.process, *(C.byref(t) for t in timestamps)), "GetCreatedProcessTimes")
        path_buffer, path_length = C.create_unicode_buffer(32768), DWORD(32768)
        checked(image_name(pi.process, 0, path_buffer, C.byref(path_length)), "GetCreatedProcessImage")
        root_identity = dict(pid=pi.pid, creation_filetime=(timestamps[0].dwHighDateTime << 32) |
                             timestamps[0].dwLowDateTime, image=path_buffer.value)
        if os.path.normcase(os.path.realpath(path_buffer.value)) != os.path.normcase(os.path.realpath(sys.executable)):
            raise ValueError("CREATED_IMAGE_MISMATCH")
        journal.write("CREATED_SUSPENDED_JOB_BOUND", identity=root_identity)
        if resume_thread(pi.thread) == 0xFFFFFFFF:
            raise OSError(C.get_last_error(), "ResumeCreatedThread")
        journal.write("RESUMED", identity=root_identity)
        started = time.monotonic()
        deadline = started + (0.6 if mode == "timeout" else 3.0)
        while True:
            for index, read in enumerate(reads):
                totals[index], captures[index], eof = read_chunk(read, totals[index], captures[index])
                if index == 0:
                    out_eof = eof
                else:
                    err_eof = eof
            if max(totals) > MAX_STREAM:
                reason = "OUTPUT_LIMIT"
                break
            root_exited = wait_handle(pi.process, 0) == 0
            active = query_active(job)
            if root_exited and active == 0 and out_eof and err_eof:
                break
            if time.monotonic() >= deadline:
                reason = "TIMEOUT"
                break
            time.sleep(0.01)
        journal.write("STAGE_STOP", reason=reason, root_exited=root_exited, job_active=active,
                      output_bytes=totals)
    except BaseException as error:
        operation_error = str(error)[:1000]
        reason = "OPERATION_ERROR"
    finally:
        # Even errors before resume use the exact job, never PID enumeration.
        if job is not None:
            try:
                if query_active(job):
                    checked(terminate_job(job, 124), "TerminateOwnJob")
                drain_end = time.monotonic() + 2.0
                while time.monotonic() < drain_end:
                    if created:
                        root_exited = wait_handle(pi.process, 0) == 0
                        for index, read in enumerate(reads):
                            totals[index], captures[index], eof = read_chunk(read, totals[index], captures[index])
                            if index == 0:
                                out_eof = eof
                            else:
                                err_eof = eof
                    active = query_active(job)
                    if active == 0 and (not created or (root_exited and out_eof and err_eof)):
                        break
                    time.sleep(0.01)
                child_limits = job_limits(job)
                if created and root_exited:
                    value = DWORD()
                    checked(exit_code(pi.process, C.byref(value)), "GetChildExitCode")
                    code = value.value
            except BaseException as error:
                cleanup_errors.append(str(error)[:500])
        if initialized:
            delete_attrs(attributes)
        for handle in handles + ([pi.thread, pi.process] if created else []):
            if handle and not close_handle(handle):
                cleanup_errors.append("CLOSE_HANDLE_FAILED")
        if job is not None and not close_handle(job):
            cleanup_errors.append("CLOSE_JOB_FAILED")

    cleanup_ok = (not cleanup_errors and active == 0 and
                  (not created or (root_exited and out_eof and err_eof)))
    out = bytes(captures[0]).decode("ascii", errors="replace")
    err = bytes(captures[1]).decode("ascii", errors="replace")
    expected = {"normal": reason == "NATURAL_EXIT" and code == 0 and out == "FIXTURE_OK\n" and err == "ERR_OK\n",
                "timeout": reason == "TIMEOUT",
                "output": reason == "OUTPUT_LIMIT",
                "memory": reason == "NATURAL_EXIT" and code == 23 and "MEMORY_LIMIT_OBSERVED" in out}[mode]
    result = dict(status="PASS_MICROPROBE_ONLY" if cleanup_ok and expected and not operation_error else "FAILED_OR_UNKNOWN",
                  mode=mode, reason=reason, error=operation_error, cleanup_errors=cleanup_errors,
                  child_created=created, identity=root_identity, root_handle_exited=root_exited,
                  job_active=active, stdout_eof=out_eof, stderr_eof=err_eof, cleanup_verified=cleanup_ok,
                  exit_code=code, output_bytes=totals, capture_bytes=[len(x) for x in captures],
                  stdout_sha256=hashlib.sha256(captures[0]).hexdigest(),
                  stderr_sha256=hashlib.sha256(captures[1]).hexdigest(), limits=child_limits,
                  cad_calls=0, compiler_calls=0, full_fixture_verified=False)
    journal.write("CLEANUP_RESULT", **result)
    journal.finish(result)
    return result


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ALLOWED:
        raise SystemExit("FIXED_MODE_AND_NEW_CASE_DIRECTORY_REQUIRED")
    try:
        result = run_probe(sys.argv[1], sys.argv[2])
        print(json.dumps(result, separators=(",", ":")), flush=True)
        raise SystemExit(0 if result["status"].startswith("PASS_") else 1)
    except Exception as error:
        # Small diagnostic only; no false claim that a child never existed.
        print(json.dumps(dict(status="FAILED_OR_UNKNOWN", error=str(error)[:1000],
                              cad_calls=0, full_fixture_verified=False)), flush=True)
        raise SystemExit(1)
