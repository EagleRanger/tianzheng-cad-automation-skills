"""Settle an already committed native leader save mismatch; never replay DWG edits."""
import argparse,json,shutil,subprocess
from pathlib import Path
from cad_runtime.storage import read,digest,atomic_new,lock,same
from cad_runtime.common import check
from cad_runtime.host import process_identity
from cad_runtime.bound_edits import require_entry
ROOT=Path(__file__).resolve().parent

def run(state,build,request,expected):
 b=read(state)['session_client'];folder=Path(b['session_dir']);request=Path(request).resolve();expected=Path(expected).resolve()
 with lock(folder):
  check(process_identity(b['host']['pid'])==b['host'],'HOST_IDENTITY')
  check(same(request.parent,folder),'REQUEST_SCOPE');q=read(request);j=read(q['job_path']);f=read(j['receipt']);s=read(folder/'session_status.json')
  check(q['kind']=='groundcover_update' and digest(q['job_path'])==q['job_sha256'],'REQUEST_IDENTITY')
  check(f['status']=='BOUND_MODULE_FAILED' and f.get('committed') is True and f.get('write_started') is True and 'UPDATE_SAVE_REOPEN_MISMATCH' in f['error'],'EXPECTED_SAVED_FAILURE')
  check(same(s['last_saved'],j['input']) and s['last_sha256']==j['input_sha256']==digest(j['input']),'SOURCE_CHANGED')
  resolution=Path(j['receipt']+'.resolution.json');check(not resolution.exists(),'ALREADY_RESOLVED')
  release=read(build);check(digest(release['dll'])==release['sha256'],'BUILD_CHANGED');entry='HLCADGROUNDCOVERSAVEDRECOVERV1';require_entry(release['dll'],entry)
  trusted=Path(b['loaded_dll']).parent/('HLFixed_'+release['sha256'][:12]+'.dll')
  if not trusted.exists():shutil.copy2(release['dll'],trusted)
  check(digest(trusted)==release['sha256'],'TRUSTED_BINARY_CHANGED')
  base=folder/(q['client_request_id']+'.saved-recovery');cfg=Path(str(base)+'.config.json');manifest=Path(str(base)+'.dispatch.json')
  m={**b,'document':s['live_document'],'saved_path':s['last_saved'],'source_sha256':s['last_sha256'],'request':str(request),'request_sha256':digest(request),'failure':j['receipt'],'failure_sha256':digest(j['receipt']),'output_sha256':digest(j['output']),'emergency_sha256':digest(f['emergency']),'expected':str(expected),'expected_sha256':digest(expected),'receipt':str(resolution),'test_only':False,'dll':str(trusted),'dll_sha256':release['sha256'],'entry':entry,'dispatch_receipt':str(base)+'.dispatch.receipt.json','command_config':str(cfg)}
  atomic_new(cfg,m);atomic_new(manifest,m)
  quote=lambda x:"'"+str(x).replace("'","''")+"'"
  ps=Path(str(base)+'.ps1')
  with ps.open('x',encoding='utf-8-sig') as f:f.write('& '+quote(ROOT/'invoke_bound_cad_module.ps1')+' -Manifest '+quote(manifest))
  p=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'run_private_cad_script.ps1'),'-Desktop','HLBase736_'+b['base_job_sha256'][:12],'-Script',str(ps)],capture_output=True,timeout=25,creationflags=0x08000000)
  check(p.returncode==0,'DISPATCH_FAILED_CHECK_RECEIPT_NO_REPLAY')
  return {'status':'RECOVERY_DISPATCHED_CHECK_NATIVE_RECEIPT','receipt':str(resolution),'replayed':False}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['state','build','request','expected']:p.add_argument('--'+k,required=True)
 a=p.parse_args();print(json.dumps(run(a.state,a.build,a.request,a.expected),ensure_ascii=False))
