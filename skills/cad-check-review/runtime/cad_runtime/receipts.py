"""Read and reconcile existing native receipts; never submit or mutate CAD."""
from pathlib import Path
import re
from .common import check
from .storage import read,digest,same,atomic_new
from .protocol import SUCCESS,MUTATING_KINDS

def settled(record):
    return record['state'] in ('RECEIPTED','RESOLVED_REJECTED')

def verify_offset_dispatch_rejection(path,req,job,receipt):
    """Consume a bound native comparison; never infer no write from COM failure alone."""
    check(req['kind']=='polyline_offset' and same(receipt['request'],path) and digest(path)==receipt['request_sha256'] and req['job_sha256']==receipt['job_sha256'],'OFFSET_REJECTION_IDENTITY')
    check(receipt['source_sha256']==job['input_sha256'],'OFFSET_REJECTION_SOURCE')
    check(all(receipt.get(k) is True for k in ('read_only','model_object_set_equal','source_polylines_equal','output_absent')) and all(receipt.get(k) is False for k in ('replayed','offset_committed')),'OFFSET_REJECTION_NOT_PROVEN')
    dispatch=read(receipt['dispatch']);failed=read(receipt['preserved_dispatch'])
    check(digest(receipt['dispatch'])==receipt['dispatch_sha256'] and same(dispatch['request'],path) and dispatch['request_sha256']==digest(path),'OFFSET_DISPATCH_IDENTITY')
    check(same(dispatch['dispatch_receipt'],receipt['preserved_dispatch']) and digest(receipt['preserved_dispatch'])==receipt['failure_sha256'] and same(failed['request'],path),'OFFSET_FAILURE_IDENTITY')
    check(failed.get('status')=='BOUND_DISPATCH_FAILED' and failed.get('stage')=='send_command' and failed.get('send_attempted') is True and '80010001' in str(failed).lower(),'OFFSET_FAILURE_NOT_CALL_REJECTED')
    known='dfe072f2dab51ae329085403f46ef8b3cf6a45225b7c660e8472dfd3fdcd7002'
    check(receipt['failed_module_sha256']==dispatch['dll_sha256']==known and digest(dispatch['dll'])==known,'OFFSET_IMPLEMENTATION_UNKNOWN')
    check(receipt['pid']==dispatch['host']['pid'] and receipt['created']==dispatch['host']['created'],'OFFSET_HOST_IDENTITY')

def verified_legacy_paper_read_failure(path,req,job,receipt):
    """Two released read-only modules emitted generic failure instead of rejection.
    Preserve original receipts; settle only the source-Database ReadPaper path.
    """
    if req['kind']!='paper_read' or receipt.get('status')!='BOUND_MODULE_FAILED':return False
    check(receipt.get('write_started') is False and receipt.get('committed') is False and receipt.get('emergency') is None and 'BoundCadEditsV1.ReadPaper(' in receipt.get('error','') and 'output' not in job,'READ_ONLY_FAILURE_STAGE_UNKNOWN')
    dispatch=read(path.parent/(req['client_request_id']+'.dispatch.json'))
    check(same(dispatch['request'],path) and digest(path)==dispatch['request_sha256'] and dispatch['source_sha256']==job['input_sha256'],'READ_ONLY_FAILURE_IDENTITY')
    known={'b62bd2658ff2db9e506451e3e62a78b162dc8896ca7125cc0b13c5e97e88727a','152351a69b2b8768e00f21d52362c15fc9a1cf440fd5e8492b68504b0e6aabb4'}
    check(dispatch['dll_sha256'] in known and digest(dispatch['dll'])==dispatch['dll_sha256'],'READ_ONLY_IMPLEMENTATION_UNKNOWN')
    return True

def verify_paper_resolution(request,job,failed,resolved,failure_path):
    check(failed.get('status')=='BOUND_MODULE_FAILED' and failed.get('write_started') is True and 'UNSELECTED_OBJECT_MODIFIED_AT_COMMIT:' in failed.get('error',''),'PAPER_FAILURE_NOT_MATCHED')
    check(resolved.get('status')=='SAVED_STILL_OPEN' and same(resolved['request'],request) and resolved['request_sha256']==digest(request) and resolved['job_sha256']==read(request)['job_sha256'],'PAPER_RESOLUTION_IDENTITY')
    check(same(resolved['failure'],failure_path) and resolved['failure_sha256']==digest(failure_path) and resolved['source_sha256']==job['input_sha256'],'PAPER_FAILURE_PROTECTION')
    check(same(resolved['output'],job['output']) and resolved['sha256']==digest(job['output']) and resolved['sha256']==digest(failed['emergency']),'PAPER_RECOVERED_OUTPUT_CHANGED')
    recovery=resolved.get('recovery',{});check(recovery.get('status')=='COMMITTED_PAPER_TRANSFORM_RECOVERED' and recovery.get('replayed') is False and recovery.get('production_entities_modified') is False and recovery.get('original_failure_preserved') is True,'PAPER_RECOVERY_FLAGS')

def verify_groundcover_resolution(request,job,failed,resolved,failure_path):
    """Adopt native readback of a committed update; preserve failure, never replay."""
    check(failed.get('status')=='BOUND_MODULE_FAILED' and failed.get('write_started') is True and failed.get('committed') is True and failed.get('replayed') is False and 'UPDATE_SAVE_REOPEN_MISMATCH' in failed.get('error',''),'GROUNDCOVER_FAILURE_NOT_MATCHED')
    q=read(request)
    check(q['kind']=='groundcover_update' and resolved.get('status')=='SAVED_STILL_OPEN' and same(resolved['request'],request) and resolved['request_sha256']==digest(request) and resolved['job_sha256']==q['job_sha256'],'GROUNDCOVER_RESOLUTION_IDENTITY')
    check(same(resolved['failure'],failure_path) and resolved['failure_sha256']==digest(failure_path) and resolved['source_sha256']==job['input_sha256']==digest(job['input']),'GROUNDCOVER_SOURCE_PROTECTION')
    check(same(resolved['output'],job['output']) and resolved['sha256']==digest(job['output']) and resolved['emergency_sha256']==digest(failed['emergency']) and resolved['expected_sha256']==digest(resolved['expected']),'GROUNDCOVER_SAVED_EVIDENCE_CHANGED')
    recovery=resolved.get('recovery',{})
    check(recovery.get('status')=='COMMITTED_GROUNDCOVER_UPDATE_RECOVERED' and recovery.get('replayed') is False and recovery.get('production_entities_modified') is False and recovery.get('original_failure_preserved') is True and recovery.get('working_database_context_corrected') is True,'GROUNDCOVER_RECOVERY_FLAGS')
    changes=resolved.get('changes',{})
    check(changes.get('created')==[] and changes.get('updated')==[i['template_handle'] for i in job['items']] and changes.get('native_save_reopen_verified') is True,'GROUNDCOVER_RECOVERY_TARGETS')

def verify_preclone_resolution(path,job,receipt,resolution):
    """Original copy module proved rejection before its first clone; no replay."""
    check(receipt.get('status')=='BOUND_MODULE_FAILED' and receipt.get('committed') is False,'COPY_FAILURE_NOT_REJECTED')
    check(resolution.get('status')=='REJECTED_BEFORE_CLONE_RECOVERED' and resolution.get('stage')=='source_identity_before_any_clone','COPY_FAILURE_STAGE_UNKNOWN')
    check(all(resolution.get(k) is False for k in ('completed','replayed','cad_entities_modified')),'COPY_RESOLUTION_NOT_REJECTION')
    check(same(resolution['request'],path) and digest(path)==resolution['request_sha256'] and digest(job['receipt'])==resolution['failure_sha256'],'COPY_FAILURE_IDENTITY')
    request=read(path)
    check(resolution['job_sha256']==request['job_sha256'] and resolution['source_sha256']==job['input_sha256'] and resolution['reference_sha256']==job['source_sha256'],'COPY_RESOLUTION_SOURCE')
    check(resolution['failed_module_sha256']=='9796207639d7744af79e4dc92748ca23da352aae77bb241e2ebee82bc0182f71','COPY_FAILURE_IMPLEMENTATION_UNKNOWN')
    check(len(job['source_targets'])==1 and job['source_targets'][0]['type']=='TDbText' and receipt['error'].startswith('System.InvalidOperationException: TARGET_BOUNDS_CHANGED:'+job['source_targets'][0]['handle']+'\r\n'),'COPY_FAILURE_STAGE_MISMATCH')
    check(same(resolution['emergency'],receipt['emergency']) and digest(resolution['emergency'])==resolution['emergency_sha256'],'COPY_PROTECTION_CHANGED')

def verify_failed_base_resolution(path,job,receipt,resolution):
    kind=read(path)['kind']
    expected={'base_replace':'BASE_REPLACE_FAILED','viewport_camera':'VIEWPORT_SIDE_FAILED','paper_roots_copy':'PAPER_ROOTS_COPY_FAILED'}.get(kind)
    check(expected is not None and receipt.get('status')==expected and receipt.get('active_document_changed') is False and receipt.get('source_sha256')==job['input_sha256'],'BASE_FAILURE_NOT_SAFE_TO_RESOLVE')
    check(resolution.get('status')=='FAILED_WITH_LIVE_DOCUMENT_UNCHANGED' and resolution.get('completed') is False and resolution.get('replayed') is False,'BASE_RESOLUTION_NOT_FAILURE')
    check(digest(job['receipt'])==resolution['failure_sha256'] and same(resolution['request'],path),'BASE_FAILURE_IDENTITY')
    probe=read(resolution['idle_observation'])
    check(digest(resolution['idle_observation'])==resolution['idle_observation_sha256'] and probe.get('status')=='BOUND_HOST_READ_ONLY' and probe.get('cmdactive')==0 and same(probe['request'],path) and probe.get('source_sha256')==job['input_sha256'],'BASE_FAILURE_IDLE_EVIDENCE')
    request=read(path);dispatch=read(path.parent/(request['client_request_id']+'.dispatch.json'))
    check(same(dispatch['request'],path) and probe.get('pid')==dispatch['host']['pid'] and probe.get('created')==dispatch['host']['created'] and same(probe['document'],dispatch['document']),'BASE_FAILURE_LIVE_IDENTITY')
    check(digest(job['input'])==job['input_sha256'],'BASE_FAILURE_INPUT_CHANGED')
    # A failed candidate may exist but is never approved or substituted for the live document.
    check(resolution['candidate_exists']==Path(job['output']).is_file(),'BASE_FAILURE_CANDIDATE_EVIDENCE')
    if resolution['candidate_exists']:check(resolution['candidate_sha256']==digest(job['output']),'BASE_FAILED_CANDIDATE_CHANGED')

def resolve_failed_base(folder,request_id,probe_path):
    matches=[r for r in request_records(folder) if r.get('id')==request_id]
    check(len(matches)==1 and matches[0]['kind'] in ('base_replace','viewport_camera','paper_roots_copy'),'EXACT_BASE_REQUEST_REQUIRED')
    record=matches[0];path=Path(record['request']);job=read(record['job']);receipt=read(record['receipt'])
    check(record['state']=='RECEIPT_REQUIRES_RECONCILIATION','BASE_REQUEST_NOT_UNSETTLED_FAILURE')
    probe_path=Path(probe_path).resolve();check(same(probe_path.parent,folder),'PROBE_OUTSIDE_SESSION')
    check(probe_path.stat().st_mtime_ns>=Path(job['receipt']).stat().st_mtime_ns,'PROBE_PREDATES_FAILURE')
    output=Path(job['output']);resolution={'status':'FAILED_WITH_LIVE_DOCUMENT_UNCHANGED','request':str(path),'failure_sha256':digest(job['receipt']),'idle_observation':str(probe_path),'idle_observation_sha256':digest(probe_path),'candidate_exists':output.is_file(),'candidate_sha256':digest(output) if output.is_file() else None,'completed':False,'replayed':False}
    verify_failed_base_resolution(path,job,receipt,resolution)
    sidecar=Path(job['receipt']+'.resolution.json');atomic_new(sidecar,resolution)
    return {'state':'RESOLVED_REJECTED','resolution':str(sidecar),'completed':False,'replayed':False}

def request_records(folder):
    records = []
    def names():
        return {p.name for p in folder.glob("request*.json") if p.name == "request.json" or p.name.startswith("request_")}
    before = names(); files = [folder / n for n in before]
    for path in sorted(files):
        try:
            req = read(path); job_path = Path(req["job_path"])
            check(same(job_path.parent, folder), "JOB_OUTSIDE_SESSION")
            check(digest(job_path) == req["job_sha256"], "JOB_IDENTITY")
            job = read(job_path); receipt_path = Path(job["receipt"])
            check(same(receipt_path.parent, folder), "RECEIPT_OUTSIDE_SESSION")
            receipt = read(receipt_path) if receipt_path.exists() else None
            outcome = "QUEUED" if path.name == "request.json" else "ACCEPTED_UNSETTLED"
            if receipt:
                outcome = "RECEIPT_REQUIRES_RECONCILIATION"
                expected = SUCCESS.get(req["kind"])
                if expected and receipt.get("status") == expected:
                    if req["kind"] in MUTATING_KINDS:
                        check(same(receipt["output"], job["output"]) and re.fullmatch(r"[a-f0-9]{64}", receipt["sha256"]), "SAVE_RECEIPT_IDENTITY")
                        check(Path(receipt["output"]).is_file(), "SAVED_OUTPUT_MISSING")
                    else:
                        if req["kind"] != "switch":
                            expected_source = job["source_sha256"] if req["kind"] == "text_read" and "source" in job else job["input_sha256"]
                            check(receipt.get("source_sha256") == expected_source, "RECEIPT_SOURCE_IDENTITY")
                    outcome = "RECEIPTED"
                elif receipt.get('status')=='REJECTED_BEFORE_WRITE':
                    check(receipt.get('write_started') is False and receipt.get('committed',False) is False and receipt.get('replayed') is False and receipt.get('emergency') is None and receipt.get('source_sha256')==job['input_sha256'],'PREWRITE_REJECTION_INVALID')
                    outcome='RESOLVED_REJECTED'
                elif verified_legacy_paper_read_failure(path,req,job,receipt):
                    outcome='RESOLVED_REJECTED'
                elif req['kind']=='polyline_offset' and receipt.get('status')=='RECONCILED_OFFSET_DISPATCH_REJECTION':
                    verify_offset_dispatch_rejection(path,req,job,receipt)
                    outcome='RESOLVED_REJECTED'
                elif req['kind']=='inspect' and receipt.get('status')=='RECONCILED_READ_ONLY_REJECTION':
                    check(receipt.get('source_sha256')==job['input_sha256'] and receipt.get('reason')=='LAYOUT_INVALID_BEFORE_VIEW_CHANGE' and receipt.get('inspection_completed') is False and receipt.get('replayed') is False,'INVALID_RECONCILED_REJECTION')
                    check(Path(receipt['preserved_failure']).is_file() and Path(receipt['emergency']).is_file(),'RECONCILIATION_PROTECTION_MISSING')
                    outcome='RESOLVED_REJECTED'
                elif req['kind']=='inspect' and receipt.get('status')=='RECONCILED_READ_ONLY_DISPATCH_FAILURE':
                    check(receipt.get('source_sha256')==job['input_sha256'] and receipt.get('inspection_completed') is False and receipt.get('replayed') is False,'DISPATCH_RECONCILIATION_IDENTITY')
                    failed=read(receipt['preserved_dispatch']);probe=read(receipt['idle_observation'])
                    check(failed.get('status')=='BOUND_DISPATCH_FAILED' and same(failed['request'],path),'DISPATCH_FAILURE_EVIDENCE')
                    check(digest(receipt['idle_observation'])==receipt['idle_observation_sha256'] and probe.get('status')=='BOUND_HOST_READ_ONLY' and probe.get('cmdactive')==0 and same(probe['request'],path) and probe.get('source_sha256')==job['input_sha256'],'DISPATCH_IDLE_EVIDENCE')
                    outcome='RESOLVED_REJECTED'
                elif req['kind'] in ('paper_patch','text_patch','paper_index_create','paper_roots_activate','table_expand') and Path(str(receipt_path)+'.resolution.json').is_file():
                    r=read(str(receipt_path)+'.resolution.json')
                    check(r.get('status')=='ROLLED_BACK_TO_SAVED_CHECKPOINT' and r.get('completed') is False and r.get('replayed') is False and r.get('failed_candidate_adopted') is False,'PAPER_ROLLBACK_FLAGS')
                    check(r['request_sha256']==digest(path) and same(r['request'],path) and r['job_sha256']==req['job_sha256'] and r['failure_sha256']==digest(receipt_path),'PAPER_ROLLBACK_IDENTITY')
                    check(same(r['checkpoint'],job['input']) and r['checkpoint_sha256']==job['input_sha256']==digest(job['input']),'PAPER_ROLLBACK_CHECKPOINT')
                    check(same(r['emergency'],receipt['emergency']) and digest(r['emergency'])==r['emergency_sha256'] and digest(r['protection'])==r['protection_sha256'],'PAPER_ROLLBACK_PROTECTION')
                    sw=read(r['switch_receipt'])
                    check(digest(r['switch_receipt'])==r['switch_receipt_sha256'] and sw['status']=='CURRENT_SAVED_BEFORE_SWITCH' and same(sw['next'],job['input']) and same(sw['saved'],r['protection']) and sw['sha256']==r['protection_sha256'] and sw['pid']==r['pid'],'PAPER_ROLLBACK_NATIVE_SWITCH')
                    outcome='RESOLVED_REJECTED'
                elif req['kind'] in ('base_replace','viewport_camera','paper_roots_copy') and Path(str(receipt_path)+'.resolution.json').is_file():
                    verify_failed_base_resolution(path,job,receipt,read(str(receipt_path)+'.resolution.json'))
                    outcome='RESOLVED_REJECTED'
                elif req['kind']=='paper_copy' and Path(str(receipt_path)+'.resolution.json').is_file():
                    verify_preclone_resolution(path,job,receipt,read(str(receipt_path)+'.resolution.json'))
                    outcome='RESOLVED_REJECTED'
                elif req['kind']=='groundcover_update' and Path(str(receipt_path)+'.resolution.json').is_file():
                    resolved_path=Path(str(receipt_path)+'.resolution.json');resolved=read(resolved_path)
                    verify_groundcover_resolution(path,job,receipt,resolved,receipt_path)
                    receipt_path=resolved_path;receipt=resolved;outcome='RECEIPTED'
                elif req['kind']=='paper_transform' and Path(str(receipt_path)+'.resolution.json').is_file():
                    resolved_path=Path(str(receipt_path)+'.resolution.json');resolved=read(resolved_path)
                    verify_paper_resolution(path,job,receipt,resolved,receipt_path)
                    receipt_path=resolved_path;receipt=resolved;outcome='RECEIPTED'
            records.append({"request": str(path), "id": req.get("client_request_id"), "kind": req["kind"],
                            "job": str(job_path), "receipt": str(receipt_path), "state": outcome,
                            "observed_mtime_ns": (receipt_path if receipt is not None else path).stat().st_mtime_ns,
                            "params_sha256": req.get("params_sha256"), "saved_output": receipt.get("output") if receipt else None})
        except (OSError, ValueError, KeyError, TypeError) as exc:
            records.append({"request": str(path), "state": "UNREADABLE_REQUEST", "error": str(exc)})
    check(before == names(), "QUEUE_CHANGED_DURING_READ: 原生正在接单；只重读状态，不发请求")
    # Queue archive names contain random IDs. Time orders this diagnostic list only;
    # it must never select a drawing, establish authorization, or prove acceptance.
    return sorted(records, key=lambda r: (r.get("observed_mtime_ns", 0), r["request"]))


def status_view(snap, request_id=None):
    """Bounded status, with all unsettled requests retained and no replay side effect."""
    records = snap["requests"]
    pending = [r for r in records if not settled(r)]
    if request_id is not None:
        check(isinstance(request_id, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,72}", request_id), "REQUEST_ID_INVALID")
        selected = [r for r in records if r.get("id") == request_id]
        check(selected, "REQUEST_ID_NOT_FOUND: " + request_id + "；未查到不代表未执行，禁止据此重发")
        check(len(selected) == 1, "REQUEST_ID_AMBIGUOUS: " + request_id)
    else:
        selected = [r for r in records if settled(r)][-3:]
    return {**snap, "request_counts": {"total": len(records), "unsettled": len(pending)},
            "requests": pending + [r for r in selected if r not in pending],
            "requested_id": request_id, "replayed": False,
            "ordering": "receipt/request file mtime; display order only, not drawing authority"}
