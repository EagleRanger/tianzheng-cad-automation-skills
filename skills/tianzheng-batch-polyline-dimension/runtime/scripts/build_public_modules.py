"""Build the shipped C# sources with the receiver's SDK; never load CAD/DLLs.

This is a standard compiler invocation, not a security sandbox. The original
resource-bounded research compiler remains available separately and fail-closed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def local(relative):
    path=(ROOT/relative).resolve()
    if not path.is_relative_to(ROOT) or path==ROOT:
        raise ValueError('Path outside source root')
    return path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk',required=True,help='Installed matching AutoCAD SDK directory')
    parser.add_argument('--framework',default=str(Path(os.environ.get('WINDIR','C:/Windows'))/'Microsoft.NET/Framework64/v4.0.30319'))
    args=parser.parse_args()
    if os.name!='nt':raise RuntimeError('Windows compiler required')
    sdk=Path(args.sdk).resolve();framework=Path(args.framework).resolve()
    compiler=framework/'csc.exe'
    if not compiler.is_file():raise FileNotFoundError('csc.exe not found')
    mapping=json.loads((ROOT/'config/public_module_builds.json').read_text(encoding='utf-8-sig'))
    manifest=ROOT/'config/receiver_build_manifest.json'
    if manifest.exists():raise FileExistsError('Build manifest exists; preserve/compare the prior build first')
    plans=[]
    for module in mapping['modules']:
        output=local(module['output'])
        if output.suffix.lower()!='.dll' or output.exists():raise FileExistsError('No overwrite of module: '+str(output))
        sources=[local(s) for s in module['sources']]
        refs=[(framework/r if r.startswith('WPF/') or r not in ('acmgd.dll','acdbmgd.dll','accoremgd.dll') else sdk/r).resolve() for r in module['references']]
        for path in sources+refs:
            if not path.is_file():raise FileNotFoundError(str(path))
        plans.append((module,output,sources,refs))
    built=[]
    for module,output,sources,refs in plans:
        inputs={str(p):sha(p) for p in [compiler,*sources,*refs]}
        output.parent.mkdir(parents=True,exist_ok=True)
        command=[str(compiler),'/nologo','/noconfig','/nostdlib+','/target:library','/out:'+str(output),*['/r:'+str(p) for p in refs],*[str(p) for p in sources]]
        result=subprocess.run(command,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or not output.is_file():
            message=(result.stdout+result.stderr).decode('utf-8','replace')
            raise RuntimeError('Compile failed: '+module['id']+'\n'+message[:8000])
        if any(sha(Path(p))!=expected for p,expected in inputs.items()):raise RuntimeError('Build input changed')
        built.append({'id':module['id'],'path':module['output'],'sha256':sha(output),
            'sources':[{'path':rel,'sha256':sha(local(rel))} for rel in module['sources']],
            'native_commands':module.get('commands',[]),'lisp_functions':module.get('lisp_functions',[]),'loaded':False})
    # No stale manifest can masquerade as this invocation's successful build.
    with manifest.open('x',encoding='utf-8') as stream:
        json.dump({'schema_version':1,'kind':'RECEIVER_LOCAL_BUILD_ONLY','compiler_kind':'STANDARD_CSC_NOT_SANDBOXED',
            'cad_loaded':False,'module_registration_verified':False,'modules':built},stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    print(json.dumps({'status':'BUILD_ONLY_NO_CAD_LOAD_OR_BUSINESS_ACCEPTANCE','manifest_relative':'config/receiver_build_manifest.json',
        'pin_sha256':sha(manifest),'pin_environment_variable':'CAD_BUILD_MANIFEST_SHA256','module_count':len(built)}))


if __name__=='__main__':main()
