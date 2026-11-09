"""Resolve a proven missing-handle/layout read HOLD, without replay or DWG edits."""
import argparse, json, shutil, subprocess
from pathlib import Path
from cad_runtime.storage import read, digest, atomic_new, lock, same
from cad_runtime.common import check
from cad_runtime.bound_edits import require_entry
from cad_runtime.host import process_identity

ROOT = Path(__file__).resolve().parent

def check_read_failure(q, job, failure):
    if q['kind'] == 'inspect':
        check(not job.get('image') and job.get('bounds') is None and job.get('handles'), 'PLAIN_HANDLE_READ_ONLY')
        check('eUnknownHandle' in failure['error'] and 'V736BaseSession.InspectRegion' in failure['error'], 'EXPECTED_READ_FAILURE')
    elif q['kind'] == 'page_map':
        check(set(job)=={'input','input_sha256','receipt','layout','title_contains','frame_block_prefix','grid_block_name'} and isinstance(job['layout'],str) and job['layout'], 'EXACT_PAGE_MAP_READ_ONLY')
        check(failure['error'].startswith('System.InvalidOperationException: LAYOUT_NOT_FOUND:'+job['layout']+'\n') or failure['error'].startswith('System.InvalidOperationException: LAYOUT_NOT_FOUND:'+job['layout']+'\r\n'), 'EXPECTED_LAYOUT_FAILURE')
        check('V736BaseSession.PageMap' in failure['error'] and 'V736BaseSession.Pump' in failure['error'], 'EXPECTED_PAGE_MAP_STACK')
    else:
        check(False,'READ_JOB_KIND')

def run(state, build, request):
    binding = read(state)['session_client']; folder = Path(binding['session_dir'])
    with lock(folder):
        check(process_identity(binding['host']['pid']) == binding['host'], 'HOST_IDENTITY')
        request = Path(request).resolve()
        check(same(request.parent, folder), 'REQUEST_SCOPE')
        q = read(request); job = read(q['job_path'])
        check(digest(q['job_path']) == q['job_sha256'], 'READ_JOB_IDENTITY')
        failure = folder / 'session_failure.json'; resolution = Path(str(failure)+'.'+request.stem+'.read-recovery.json')
        if resolution.exists():
            return {'status':'RECOVERY_ALREADY_RECORDED','receipt':str(resolution),'replayed':False}
        f = read(failure)
        check(f['status'] == 'HOLD' and f['pid'] == binding['host']['pid'], 'EXPECTED_READ_FAILURE')
        check_read_failure(q, job, f)
        s = read(folder/'session_status.json')
        check(s['last_saved'] == job['input'] and s['last_sha256'] == job['input_sha256'] and digest(job['input']) == job['input_sha256'], 'CURRENT_SAVED_SOURCE_CHANGED')
        check(not Path(job['receipt']).exists(), 'REQUEST_ALREADY_SETTLED')
        b = read(build); check(digest(b['dll']) == b['sha256'], 'BUILD_CHANGED')
        entry = 'HLCADREADHOLDRECOVERV2'; require_entry(b['dll'], entry)
        dll = Path(binding['loaded_dll']).parent/('HLFixed_'+b['sha256'][:12]+'.dll')
        if not dll.exists(): shutil.copyfile(b['dll'], dll)
        check(digest(dll) == b['sha256'], 'TRUSTED_BINARY_CHANGED')
        manifest = folder/('read_hold_recovery.'+request.stem+'.dispatch.json')
        check(not manifest.exists(), 'ALREADY_DISPATCHED_DO_NOT_REPLAY')
        atomic_new(manifest, {**binding,'request':str(request),'request_sha256':digest(request),
            'failure':str(failure),'failure_sha256':digest(failure),'resolution':str(resolution),
            'document':s['live_document'],'saved_path':s['last_saved'],'source_sha256':s['last_sha256'],
            'dll':str(dll),'dll_sha256':b['sha256'],'entry':entry,
            'dispatch_receipt':str(folder/('read_hold_recovery.'+request.stem+'.dispatch.receipt.json'))})
        quote=lambda x:"'"+str(x).replace("'","''")+"'"
        script=manifest.with_suffix('.ps1')
        with script.open('x',encoding='utf-8-sig') as w:
            w.write("$ErrorActionPreference='Stop'\n& "+quote(ROOT/'invoke_bound_cad_module.ps1')+' -Manifest '+quote(manifest)+'\nif($LASTEXITCODE){exit $LASTEXITCODE}\n')
        r=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'run_private_cad_script.ps1'),'-Desktop','HLBase736_'+binding['base_job_sha256'][:12],'-Script',str(script)],capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        check(r.returncode == 0, 'RECOVERY_DISPATCH_FAILED_CHECK_RECEIPT_NO_REPLAY')
        return {'status':'RECOVERY_DISPATCHED_PENDING_RECEIPT','receipt':str(resolution),'replayed':False}

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for k in ('state','build','request'): p.add_argument('--'+k,required=True)
    a=p.parse_args()
    print(json.dumps(run(a.state,a.build,a.request),ensure_ascii=False))
