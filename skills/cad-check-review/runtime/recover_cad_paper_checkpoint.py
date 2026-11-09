"""Default: protect and restore a failed paper edit to its saved checkpoint.
Optional diagnosis and explicitly verified saved-erasure reconciliation keep
the valid existing output; neither path replays the edit or starts a new host.
"""
import argparse,json,subprocess,shutil
from pathlib import Path
from cad_runtime.binding import load_binding,STATE
from cad_runtime.storage import read,digest,same,atomic_new
from cad_runtime.receipts import request_records,settled
from cad_runtime.host import process_identity
from cad_runtime.common import check
from cad_runtime.bound_edits import require_entry

def recover(state,request_id,diagnose_build=None,adopt_build=None,diagnosis=None):
    binding=load_binding(state or STATE);folder=Path(binding['session_dir']);runtime=Path(__file__).parent
    check(process_identity(binding['host']['pid'])==binding['host'],'HOST_IDENTITY')
    records=request_records(folder);pending=[r for r in records if not settled(r)]
    matches=[r for r in records if r.get('id')==request_id]
    check(len(matches)==1,'EXACT_REQUEST_REQUIRED');rec=matches[0]
    if rec['state']=='RESOLVED_REJECTED':return {'state':'RESOLVED_REJECTED','replayed':False,'resolution':rec['receipt']+'.resolution.json'}
    check(pending==[rec] and rec['kind'] in ('paper_patch','text_patch','paper_index_create','paper_roots_activate','table_expand','table_patch') and rec['state']=='RECEIPT_REQUIRES_RECONCILIATION','EXACT_UNSETTLED_PAPER_FAILURE_REQUIRED')
    job=read(rec['job']);failure=read(rec['receipt']);point=read(folder/'session_status.json')
    check(failure.get('status')=='BOUND_MODULE_FAILED' and failure.get('write_started') is True and failure['source_sha256']==job['input_sha256'],'PAPER_FAILURE_REQUIRED')
    check(same(point['last_saved'],job['input']) and point['last_sha256']==job['input_sha256']==digest(job['input']),'PRE_EDIT_CHECKPOINT_CHANGED')
    check(not (diagnose_build and adopt_build),'CHOOSE_ONE_RECOVERY_ACTION')
    if diagnose_build or adopt_build:
        check(rec['kind'] in ('paper_patch','table_patch') and failure.get('committed') is True and failure['error'].startswith('System.InvalidOperationException: '+('SAVED_TABLE_STATE_CHANGED' if rec['kind']=='table_patch' else 'PAPER_SAVE_REOPEN_MISMATCH')),'EXACT_PAPER_SAVE_FAILURE')
        build=read(diagnose_build or adopt_build);check(digest(build['dll'])==build['sha256'],'BUILD_CHANGED');entry=(('HLCADTABLESAVEDRECOVERV1' if adopt_build else 'HLCADTABLESAVEDDIAGV1') if rec['kind']=='table_patch' else ('HLCADPAPERSAVEDRECOVERV2' if adopt_build else 'HLCADPAPERSAVEDDIAGV3'));require_entry(build['dll'],entry)
        dll=Path(binding['loaded_dll']).parent/('HLFixed_'+build['sha256'][:12]+'.dll')
        if not dll.exists():shutil.copyfile(build['dll'],dll)
        check(digest(dll)==build['sha256'],'TRUSTED_MODULE_CHANGED')
        receipt=rec['receipt']+'.diagnosis-v3.json'
        manifest={**binding,'request':rec['request'],'request_sha256':digest(rec['request']),'document':point['live_document'],'source_sha256':point['last_sha256'],'saved_path':point['last_saved'],'dll':str(dll),'dll_sha256':build['sha256'],'entry':entry,'failure_sha256':digest(rec['receipt']),'output_sha256':digest(job['output']),'emergency_sha256':digest(failure['emergency']),'diagnostic_receipt':receipt,'dispatch_receipt':str(folder/(request_id+'.diagnosis-v3.dispatch.receipt.json'))}
        stem=request_id+'.diagnosis-v3'
        if adopt_build:
            check(bool(diagnosis) and same(Path(diagnosis).parent,folder),'EXACT_LOCAL_DIAGNOSIS_REQUIRED')
            proof=read(diagnosis);check((proof.get('status')=='TABLE_SAVED_DIAGNOSED_READ_ONLY') if rec['kind']=='table_patch' else (proof.get('status')=='SAVED_PAPER_DIAGNOSED_READ_ONLY' and proof.get('persisted_state_matches') is True),'VERIFIED_PERSISTED_DIAGNOSIS_REQUIRED')
            stem=request_id+('.table_saved_recovery_v1' if rec['kind']=='table_patch' else '.saved_recovery_v2');receipt=rec['receipt']+('.table-saved-recovery-v1.json' if rec['kind']=='table_patch' else '.saved-recovery-v2.json')
            manifest.update(diagnosis=str(Path(diagnosis).resolve()),diagnosis_sha256=digest(diagnosis),flags_sha256=digest(str(diagnosis)+'.viewport-runtime.json') if rec['kind']=='paper_patch' else None,resolution=receipt,dispatch_receipt=str(folder/(stem+'.dispatch.receipt.json')))
        return dispatch(runtime,folder,binding,manifest,stem,{'state':'SAVED_RECOVERY_SUBMITTED' if adopt_build else 'DIAGNOSIS_SUBMITTED','receipt':receipt,'replayed':False})
    release=read(runtime/'RecoverPaperCheckpointV1.release.json')
    check(release['status']=='ISOLATED_NATIVE_VERIFIED' and digest(release['dll'])==release['sha256'],'RECOVERY_NOT_VERIFIED');require_entry(release['dll'],release['entry'])
    manifest={**binding,'request':rec['request'],'request_sha256':digest(rec['request']),'document':point['live_document'],'source_sha256':point['last_sha256'],'saved_path':point['last_saved'],'dll':release['dll'],'dll_sha256':release['sha256'],'entry':release['entry'],'dispatch_receipt':str(folder/(request_id+'.rollback.dispatch.receipt.json'))}
    return dispatch(runtime,folder,binding,manifest,request_id+'.rollback',{'state':'RECOVERY_SUBMITTED','resolution':job['receipt']+'.resolution.json','next':'original client status --id '+request_id,'replayed':False})

def dispatch(runtime,folder,binding,manifest,stem,result):
    mp=folder/(stem+'.dispatch.json');atomic_new(mp,manifest)
    q=lambda v:"'"+str(v).replace("'","''")+"'"
    script=folder/(stem+'.dispatch.ps1')
    with script.open('x',encoding='utf-8-sig') as f:f.write("$ErrorActionPreference='Stop'\n& "+q(runtime/'invoke_bound_cad_module.ps1')+' -Manifest '+q(mp))
    z=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(runtime/'run_private_cad_script.ps1'),'-Desktop','HLBase736_'+binding['base_job_sha256'][:12],'-Script',str(script)],capture_output=True,timeout=30,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    check(z.returncode==0,'RECOVERY_DISPATCH_FAILED: inspect existing dispatch; do not repeat')
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state',type=Path);p.add_argument('--id',required=True);p.add_argument('--diagnose-build',type=Path);p.add_argument('--adopt-saved-build',type=Path);p.add_argument('--diagnosis',type=Path);a=p.parse_args();print(json.dumps(recover(a.state,a.id,a.diagnose_build,a.adopt_saved_build,a.diagnosis),ensure_ascii=False,indent=2))
