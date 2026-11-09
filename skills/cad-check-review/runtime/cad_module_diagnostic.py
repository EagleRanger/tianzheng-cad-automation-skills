"""Management-only fixed-module validation on an explicitly bound isolated host.

No production routing, CAD startup, source selection or automatic retry.
"""
import argparse,json,os,re,shutil,subprocess,sys
from pathlib import Path
from cad_runtime.common import check
from cad_runtime.storage import read,digest,atomic_new,lock
from cad_runtime.session import snapshot
from cad_runtime.bound_edits import require_entry

ROOT=Path(__file__).resolve().parent

def prepare(state_path,build_path,entry,config_path,name):
    state=read(state_path)
    check(state.get('session_purpose')=='isolated_module_test','ISOLATED_TEST_STATE_REQUIRED')
    binding=state['session_client']; observed=snapshot(binding)
    check(observed['can_submit'],'ISOLATED_HOST_NOT_READY: '+'; '.join(observed['issues']))
    check(bool(re.fullmatch(r'[A-Za-z0-9_-]{1,100}',name)),'INVALID_DIAGNOSTIC_ID')
    config_path=Path(config_path).resolve(); config=read(config_path)
    check(digest(config['source'])==config['source_sha256'],'TEST_SOURCE_CHANGED')
    build=read(build_path); check(digest(build['dll'])==build['sha256'],'MODULE_BINARY_CHANGED')
    require_entry(build['dll'],entry)
    folder=Path(binding['session_dir']); path=folder/(name+'.module-dispatch.json')
    if path.exists():
        prior=read(path)
        check(prior['command_config_sha256']==digest(config_path) and prior['entry']==entry and prior['dll_sha256']==build['sha256'],'DIAGNOSTIC_ID_REUSED')
        return path,False
    check(not Path(config['receipt']).exists(),'NATIVE_RECEIPT_EXISTS')
    for prior in folder.glob('*.module-dispatch.json'):
        item=read(prior)
        check(Path(item['native_receipt']).exists(),'UNSETTLED_DIAGNOSTIC: '+str(prior))
    # Use the existing loaded trusted directory, never an installation path guessed by the caller.
    dll=Path(binding['loaded_dll']).parent/('HLFixed_'+build['sha256'][:12]+'.dll')
    if not dll.exists():shutil.copyfile(build['dll'],dll)
    check(digest(dll)==build['sha256'],'TRUSTED_MODULE_BINARY_CHANGED')
    point=observed['saved_checkpoint']
    manifest={**binding,'request':str(config_path),'command_config':str(config_path),'command_config_sha256':digest(config_path),
        'native_receipt':config['receipt'],'document':point['live_document'],'saved_path':point['last_saved'],
        'source_sha256':point['last_sha256'],'dll':str(dll),'dll_sha256':build['sha256'],'entry':entry,
        'dispatch_receipt':str(folder/(name+'.module-dispatch.receipt.json'))}
    atomic_new(path,manifest)
    return path,True

def run(state,build,entry,config,name):
    folder=Path(read(state)['session_client']['session_dir'])
    with lock(folder):
        path,fresh=prepare(state,build,entry,config,name)
        manifest=read(path)
        if not fresh:return {'status':'ALREADY_DISPATCHED','manifest':str(path),'native_receipt':manifest['native_receipt'],'replayed':False}
        quote=lambda x:"'"+str(x).replace("'","''")+"'"
        script=path.with_suffix('.ps1')
        with script.open('x',encoding='utf-8-sig') as f:f.write("$ErrorActionPreference='Stop'\n& "+quote(ROOT/'invoke_bound_cad_module.ps1')+' -Manifest '+quote(path)+'\nif($LASTEXITCODE){exit $LASTEXITCODE}\n')
        result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'run_private_cad_script.ps1'),
            '-Desktop','HLBase736_'+manifest['base_job_sha256'][:12],'-Script',str(script)],capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        check(result.returncode==0,'DIAGNOSTIC_HELPER_FAILED: '+result.stdout.decode(errors='replace')[-500:]+'; inspect '+str(path)+'; do not replay')
    return {'status':'DISPATCHED_PENDING_NATIVE_RECEIPT','manifest':str(path),'native_receipt':manifest['native_receipt'],'replayed':False}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('state','build','entry','config','name'):p.add_argument('--'+key,required=True)
    a=p.parse_args()
    try:print(json.dumps(run(a.state,a.build,a.entry,a.config,a.name),ensure_ascii=False));return 0
    except (ValueError,OSError,KeyError,subprocess.SubprocessError) as e:print(json.dumps({'status':'REJECTED','error':str(e)},ensure_ascii=False));return 2

if __name__=='__main__':sys.exit(main())
