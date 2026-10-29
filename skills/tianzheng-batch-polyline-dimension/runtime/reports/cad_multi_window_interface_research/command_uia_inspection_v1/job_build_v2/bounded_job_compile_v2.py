"""Private fixed csc library build adapter. No CAD, fixture EXE, or arbitrary command."""
import sys
import os
import hashlib
import importlib.util
sys.dont_write_bytecode = True
GUARDIAN_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../fixture_job_boundary_v1/bounded_fixture_job_v1.py"))
GUARDIAN_SHA256 = "FFA1CA568CB35D4E1A990AC876F95327D3F943A2113BC00BCADBCBB3601962D2"

def reject_reparse(path):
    cursor = os.path.abspath(path)
    while cursor:
        if os.path.lexists(cursor) and getattr(os.stat(cursor, follow_symlinks=False), "st_file_attributes", 0) & 0x400:
            raise ValueError("COMPILE_REPARSE_PATH")
        parent = os.path.dirname(cursor)
        if parent == cursor:
            break
        cursor = parent

reject_reparse(GUARDIAN_PATH)
with open(GUARDIAN_PATH, "rb") as guardian_stream:
    guardian_bytes = guardian_stream.read(65537)
if len(guardian_bytes) > 65536 or hashlib.sha256(guardian_bytes).hexdigest().upper() != GUARDIAN_SHA256:
    raise ValueError("FROZEN_GUARDIAN_HASH_CHANGED")
guardian_spec = importlib.util.spec_from_file_location("bound_guardian_v1", GUARDIAN_PATH)
guardian = importlib.util.module_from_spec(guardian_spec)
guardian_spec.loader.exec_module(guardian)  # Fixed V1 import binds this Python to its Job now.
# No spec/input read or child workload exists before the guardian self-Job above.
for _name in ["C","W","K","HANDLE","DWORD","SIZE","BOOL","PTR","MemoryStatus","Journal","BOOTSTRAP_JOB","ProcessInfo","Security","StartupEx","new_job","job_limits","checked","memory_status","create_pipe","set_handle","create_file","init_attrs","update_attr","create_process","close_handle","is_in_job","process_times","image_name","resume_thread","read_chunk","MAX_STREAM","wait_handle","query_active","terminate_job","exit_code","delete_attrs"]:
    globals()[_name] = getattr(guardian, _name)
import json
import time
import subprocess
SPEC_PATH = os.path.abspath(os.environ["CAD_JOB_COMPILE_SPEC_PATH"])
SPEC_SHA256 = os.environ["CAD_JOB_COMPILE_SPEC_SHA256"].upper()
with open(SPEC_PATH, "rb") as _public_spec_stream:
    _public_spec_bytes = _public_spec_stream.read(16385)
if len(_public_spec_bytes) > 16384 or hashlib.sha256(_public_spec_bytes).hexdigest().upper() != SPEC_SHA256:
    raise ValueError("PUBLIC_COMPILE_SPEC_HASH_OR_SIZE")
EXPECTED_SPEC = json.loads(_public_spec_bytes.decode("utf-8-sig"))
if EXPECTED_SPEC.get("load_generated_module") is not False or EXPECTED_SPEC.get("run_fixture_exe") is not False:
    raise ValueError("PUBLIC_BUILD_ONLY_NO_LOAD_OR_FIXTURE")
if EXPECTED_SPEC.get("limits") != {"process_mib": 128, "job_mib": 192, "active_limit": 3, "timeout_seconds": 20}:
    raise ValueError("PUBLIC_COMPILER_LIMITS_MUST_REMAIN_FROZEN")
if EXPECTED_SPEC.get("bootstrap_limits") != {"process_mib": 256, "job_mib": 384, "active_limit": 4}:
    raise ValueError("PUBLIC_BOOTSTRAP_LIMITS_MUST_REMAIN_FROZEN")

def file_hash(path):
    reject_reparse(path)
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        while True:
            chunk = stream.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest().upper()

def load_bound_spec(directory):
    reject_reparse(SPEC_PATH)
    if os.path.getsize(SPEC_PATH) > 16384 or file_hash(SPEC_PATH) != SPEC_SHA256:
        raise ValueError("COMPILE_SPEC_HASH_OR_SIZE")
    with open(SPEC_PATH, "r", encoding="utf-8") as stream:
        bound = json.load(stream)
    if bound != EXPECTED_SPEC:
        raise ValueError("COMPILE_SPEC_NOT_FIXED")
    expected_cases = os.path.join(os.path.dirname(SPEC_PATH), "cases")
    directory = os.path.abspath(directory)
    reject_reparse(directory)
    import re
    if os.path.normcase(os.path.dirname(directory)) != os.path.normcase(expected_cases) or not re.fullmatch(r"[a-f0-9]{32}_compile", os.path.basename(directory)):
        raise ValueError("COMPILE_CASE_DIRECTORY_NOT_BOUND")
    for entry in [bound["compiler"], bound["resource_helper"], bound["console_host"]] + bound["references"] + bound["sources"] + [bound["request"]]:
        if not os.path.isabs(entry["path"]) or file_hash(entry["path"]) != entry["sha256"]:
            raise ValueError("COMPILE_INPUT_HASH_CHANGED")
    artifact = os.path.join(directory, bound["output_leaf"])
    destination = bound["candidate_destination"]
    reject_reparse(destination)
    if os.path.lexists(destination):
        raise ValueError("COMPILE_DESTINATION_EXISTS_NO_OVERWRITE")
    arguments = ["/noconfig", "/nostdlib+", "/nologo", "/target:library", "/optimize+", "/out:" + artifact]
    arguments += ["/reference:" + entry["path"] for entry in bound["references"]]
    arguments += [entry["path"] for entry in bound["sources"]]
    return bound["compiler"]["path"], arguments, artifact, destination


def write_capture_diagnostics(directory, captures):
    if len(captures) != 2 or any(len(value) > MAX_STREAM for value in captures):
        raise ValueError("DIAGNOSTIC_CAPTURE_BOUND")
    proofs = []
    for leaf, value in zip(("stdout.bin", "stderr.bin"), captures):
        path = os.path.join(directory, leaf)
        reject_reparse(path)
        payload = bytes(value)
        with open(path, "xb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        digest = hashlib.sha256(payload).hexdigest().upper()
        if os.path.getsize(path) != len(payload) or file_hash(path) != digest:
            raise ValueError("DIAGNOSTIC_CAPTURE_WRITE_MISMATCH")
        proofs.append(dict(path=path, length=len(payload), sha256=digest))
    return proofs


# This version only observes the own compiler Job. Never enumerates or kills by name.
class CompilerJobPids(C.Structure):
    _fields_ = [("assigned", DWORD), ("count", DWORD), ("pids", SIZE * 3)]

open_member = K.OpenProcess
open_member.restype, open_member.argtypes = HANDLE, [DWORD, BOOL, DWORD]

def expected_compile_tool(identity, root, compiler, helper):
    if identity["pid"] == root["pid"]:
        return "root_csc", dict(path=compiler, sha256=EXPECTED_SPEC["compiler"]["sha256"])
    image = os.path.normcase(os.path.realpath(identity["image"]))
    console = EXPECTED_SPEC["console_host"]
    if image == os.path.normcase(os.path.realpath(console["path"])):
        return "console_host", console
    return "resource_helper", helper

def validate_compile_member(identity, root, compiler, helper):
    if not identity["in_job"]:
        raise ValueError("COMPILE_OBSERVED_MEMBER_NOT_OWN_JOB")
    kind, expected = expected_compile_tool(identity, root, compiler, helper)
    image = os.path.normcase(os.path.realpath(identity["image"]))
    if identity["pid"] == root["pid"]:
        if image != os.path.normcase(os.path.realpath(compiler)) or identity["creation_filetime"] != root["creation_filetime"]:
            raise ValueError("COMPILE_ROOT_MEMBER_IDENTITY_CHANGED")
        return "ROOT_CSC_ACTUAL"
    if image != os.path.normcase(os.path.realpath(expected["path"])) or file_hash(identity["image"]) != expected["sha256"]:
        raise ValueError("COMPILE_UNEXPECTED_MEMBER_IMAGE_OR_HASH")
    return "CONHOST_ACTUAL_IMAGE_HASH_JOB_BOUND" if kind == "console_host" else "CVTRES_ACTUAL_IMAGE_HASH_JOB_BOUND"

def record_compile_member(record, root, compiler, helper, members, journal):
    record["status"] = "IDENTITY_PENDING"
    record["tool_kind"], expected = expected_compile_tool(record, root, compiler, helper)
    record["expected_image"] = expected["path"]
    record["expected_sha256"] = expected["sha256"]
    record["path_match"] = os.path.normcase(os.path.realpath(record["image"])) == os.path.normcase(os.path.realpath(record["expected_image"]))
    record["hash_match"] = None
    members[record["pid"]] = record
    journal.write("JOB_MEMBER_RAW_IDENTITY", **record)
    try:
        try:
            record["image_sha256"] = file_hash(record["image"])
            record["hash_match"] = record["image_sha256"] == record["expected_sha256"]
        except Exception as error:
            record["hash_error"] = str(error)[:500]
            journal.write("JOB_MEMBER_IMAGE_HASH_ERROR", **record)
            raise
        journal.write("JOB_MEMBER_IMAGE_HASH", **record)
        record["status"] = validate_compile_member(record, root, compiler, helper)
        if not record["hash_match"]:
            raise ValueError("COMPILE_EXPECTED_IMAGE_HASH_CHANGED")
    except Exception as error:
        record["status"] = "OBSERVED_REJECTED"
        record["rejection_reason"] = str(error)[:500]
        journal.write("JOB_MEMBER_REJECTED", **record)
        raise
    journal.write("JOB_MEMBER_IDENTITY_OBSERVED", **record)

def observe_compile_members(job, root, compiler, helper, members, handles, journal):
    rows = CompilerJobPids()
    checked(guardian.query_job(job, 3, C.byref(rows), C.sizeof(rows), None), "QueryOwnCompilerJobPids")
    if rows.count > 3:
        raise ValueError("COMPILE_JOB_MEMBER_SET_EXCEEDED_THREE")
    for index in range(rows.count):
        member_pid = int(rows.pids[index])
        if member_pid in members:
            continue
        if len(members) >= 3:
            raise ValueError("COMPILE_UNEXPECTED_ADDITIONAL_MEMBER")
        record = dict(pid=member_pid, status="IDENTITY_PENDING", in_job=None, image=None,
                      creation_filetime=None, expected_image=helper["path"], expected_sha256=helper["sha256"],
                      path_match=None, hash_match=None)
        members[member_pid] = record
        journal.write("JOB_MEMBER_DISCOVERED", **record)
        try:
            handle = open_member(0x1000 | 0x100000, False, member_pid)
            if not handle:
                error_code = C.get_last_error()
                if error_code == 87:
                    record["status"] = "EXITED_BEFORE_IDENTITY_UNOBSERVED"
                    journal.write("JOB_MEMBER_OBSERVATION_GAP", **record)
                    continue
                raise OSError(error_code, "OpenOwnJobMember")
            handles.append(handle)
            member = BOOL()
            checked(is_in_job(handle, job, C.byref(member)), "VerifyObservedOwnJobMember")
            record["in_job"] = bool(member.value)
            journal.write("JOB_MEMBER_MEMBERSHIP", **record)
            timestamps = [W.FILETIME() for _ in range(4)]
            checked(process_times(handle, *(C.byref(t) for t in timestamps)), "GetObservedMemberTimes")
            record["creation_filetime"] = (timestamps[0].dwHighDateTime << 32) | timestamps[0].dwLowDateTime
            buffer, length = C.create_unicode_buffer(32768), DWORD(32768)
            checked(image_name(handle, 0, buffer, C.byref(length)), "GetObservedMemberImage")
            record["image"] = buffer.value
            record_compile_member(record, root, compiler, helper, members, journal)
        except Exception as error:
            if record["status"] != "OBSERVED_REJECTED":
                record["status"] = "PARTIAL_IDENTITY_UNVERIFIED"
                record["rejection_reason"] = str(error)[:500]
                journal.write("JOB_MEMBER_PARTIAL_FAILURE", **record)
            raise



def configure_compile_bootstrap(journal):
    before = job_limits(BOOTSTRAP_JOB)
    journal.write("BOOTSTRAP_EXISTING_JOB_BEFORE", limits=before, current_pid=os.getpid())
    if any(before[name] != value for name, value in dict(flags=8968, process_bytes=256 * 1024**2, job_bytes=384 * 1024**2, active_limit=3).items()):
        raise ValueError("BOOTSTRAP_ORIGINAL_LIMITS_NOT_FROZEN_EXPECTED")
    member = BOOL()
    checked(is_in_job(guardian.current_process(), BOOTSTRAP_JOB, C.byref(member)), "VerifyCurrentPythonOwnBootstrapJobBefore")
    if not member.value:
        raise ValueError("BOOTSTRAP_CURRENT_PROCESS_NOT_OWN_JOB")
    limits = guardian.ExtendedLimits()
    checked(guardian.query_job(BOOTSTRAP_JOB, 9, C.byref(limits), C.sizeof(limits), None), "ReadOwnBootstrapExtendedLimits")
    if limits.basic.flags != 8968 or limits.basic.active_limit != 3 or limits.process_memory != 256 * 1024**2 or limits.job_memory != 384 * 1024**2:
        raise ValueError("BOOTSTRAP_RAW_LIMITS_NOT_FROZEN_EXPECTED")
    limits.basic.active_limit = 4  # Only the actual toolchain process count changes.
    journal.write("BOOTSTRAP_ACTIVE_COUNT_SET_INTENT", before_active=3, after_active=4)
    checked(guardian.set_job(BOOTSTRAP_JOB, 9, C.byref(limits), C.sizeof(limits)), "SetOnlyOwnBootstrapActiveFour")
    after = job_limits(BOOTSTRAP_JOB)
    checked(is_in_job(guardian.current_process(), BOOTSTRAP_JOB, C.byref(member)), "VerifyCurrentPythonOwnBootstrapJobAfter")
    journal.write("BOOTSTRAP_EXISTING_JOB_AFTER", limits=after, current_process_in_exact_job=bool(member.value))
    if not member.value or any(after[name] != value for name, value in dict(flags=8968, process_bytes=256 * 1024**2, job_bytes=384 * 1024**2, active_limit=4).items()):
        raise ValueError("BOOTSTRAP_TOOLCHAIN_LIMITS_NOT_CONFIRMED")
    return dict(before=before, after=after, current_process_in_exact_job=True)


def run_compilation(mode, directory):
    compiler, arguments, artifact, destination = load_bound_spec(directory)
    if os.path.lexists(artifact):
        raise ValueError("COMPILE_CASE_ARTIFACT_EXISTS_NO_OVERWRITE")
    journal = Journal(directory)
    status = MemoryStatus()
    status.length = C.sizeof(status)
    checked(memory_status(C.byref(status)), "GlobalMemoryStatusEx")
    journal.write("BOOTSTRAP_BOUND", pid=os.getpid(), kernel_limits=job_limits(BOOTSTRAP_JOB),
                  physical_free=status.physical_free, commit_free=status.commit_free,
                  cad_calls=0, bootstrap_prebind_is_not_claimed_kernel_capped=True)
    if min(status.physical_free, status.commit_free) < 4 * 1024**3:
        raise ValueError("INSUFFICIENT_SYSTEM_HEADROOM_NO_CHILD")
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
    members = {}
    final_accounting = None
    bootstrap_delta = None
    try:
        bootstrap_delta = configure_compile_bootstrap(journal)
        job = new_job(128, 192, 3)
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
        command = C.create_unicode_buffer(subprocess.list2cmdline([compiler] + arguments))
        journal.write("CREATE_INTENT", mode=mode, kernel_job_list=True, inherit_only_stdio=True,
                      executable=compiler, seconds=20.0)
        checked(create_process(compiler, command, None, None, True,
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
        if os.path.normcase(os.path.realpath(path_buffer.value)) != os.path.normcase(os.path.realpath(compiler)):
            raise ValueError("CREATED_IMAGE_MISMATCH")
        members[pi.pid] = dict(root_identity, in_job=True, status="ROOT_CSC_ACTUAL")
        journal.write("CREATED_SUSPENDED_JOB_BOUND", identity=root_identity)
        if resume_thread(pi.thread) == 0xFFFFFFFF:
            raise OSError(C.get_last_error(), "ResumeCreatedThread")
        journal.write("RESUMED", identity=root_identity)
        started = time.monotonic()
        deadline = started + 20.0
        while True:
            observe_compile_members(job, root_identity, compiler, EXPECTED_SPEC["resource_helper"], members, handles, journal)
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
                accounting = guardian.Accounting()
                checked(guardian.query_job(job, 1, C.byref(accounting), C.sizeof(accounting), None), "GetFinalCompilerJobAccounting")
                final_accounting = dict(total_assigned=accounting.total, active=accounting.active, terminated=accounting.terminated)
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
    diagnostics = None
    diagnostic_error = None
    try:
        diagnostics = write_capture_diagnostics(directory, captures)
    except Exception as error:
        diagnostic_error = str(error)[:1000]
    compiled_hash = None
    artifact_error = None
    expected = cleanup_ok and reason == "NATURAL_EXIT" and code == 0 and not operation_error and not diagnostic_error
    if expected:
        try:
            load_bound_spec(directory)  # Recheck every input after compiler exit.
            reject_reparse(artifact)
            if not os.path.isfile(artifact) or not 0 < os.path.getsize(artifact) <= 1024 * 1024:
                raise ValueError("COMPILED_LIBRARY_MISSING_OR_OVERSIZE")
            with open(artifact, "rb") as stream:
                payload = stream.read(1024 * 1024 + 1)
            if payload[:2] != b"MZ":
                raise ValueError("COMPILED_LIBRARY_NOT_PE")
            compiled_hash = hashlib.sha256(payload).hexdigest().upper()
            # csc only writes a unique own-case path. Publish by exclusive creation.
            with open(destination, "xb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            if file_hash(destination) != compiled_hash:
                raise ValueError("COMPILED_DESTINATION_HASH_MISMATCH")
        except Exception as error:
            artifact_error = str(error)[:1000]
            expected = False
    result = dict(status="PASS_COMPILED_NOT_LOADED" if cleanup_ok and expected and not operation_error else "FAILED_OR_UNKNOWN",
                  mode=mode, reason=reason, error=operation_error, cleanup_errors=cleanup_errors,
                  child_created=created, identity=root_identity, root_handle_exited=root_exited,
                  job_active=active, stdout_eof=out_eof, stderr_eof=err_eof, cleanup_verified=cleanup_ok,
                  exit_code=code, output_bytes=totals, capture_bytes=[len(x) for x in captures],
                  stdout_sha256=hashlib.sha256(captures[0]).hexdigest(),
                  stderr_sha256=hashlib.sha256(captures[1]).hexdigest(), limits=child_limits,
                  cad_calls=0, compiler_calls=1 if created else 0, full_fixture_verified=False,
                  generated_module_loaded=False, module_sha256=compiled_hash,
                  artifact_error=artifact_error, artifact_path=artifact, candidate_destination=destination,
                  diagnostics=diagnostics, diagnostic_error=diagnostic_error,
                  observed_members=list(members.values()), final_job_accounting=final_accounting, bootstrap_toolchain_delta=bootstrap_delta,
                  console_host_identity_status="OBSERVED_ACTUAL_CONHOST" if any(x["status"] == "CONHOST_ACTUAL_IMAGE_HASH_JOB_BOUND" for x in members.values()) else "UNOBSERVED_NOT_VERIFIED",
                  helper_identity_status="OBSERVED_ACTUAL_CVTRES" if any(x["status"] == "CVTRES_ACTUAL_IMAGE_HASH_JOB_BOUND" for x in members.values()) else ("OBSERVED_REJECTED" if any(x["status"] == "OBSERVED_REJECTED" for x in members.values()) else ("PARTIAL_IDENTITY_UNVERIFIED" if any(x["status"] == "PARTIAL_IDENTITY_UNVERIFIED" for x in members.values()) else "UNOBSERVED_NOT_VERIFIED")))
    journal.write("CLEANUP_RESULT", **result)
    journal.finish(result)
    return result


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "compile":
        raise SystemExit("FIXED_COMPILE_MODE_REQUIRED")
    try:
        result = run_compilation("compile", sys.argv[2])
        print(json.dumps(result, separators=(",", ":")), flush=True)
        raise SystemExit(0 if result["status"] == "PASS_COMPILED_NOT_LOADED" else 1)
    except Exception as error:
        print(json.dumps(dict(status="FAILED_OR_UNKNOWN", error=str(error)[:1000],
                              cad_calls=0, full_fixture_verified=False)), flush=True)
        raise SystemExit(1)
