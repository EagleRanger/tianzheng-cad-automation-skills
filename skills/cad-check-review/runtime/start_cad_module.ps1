param([Parameter(Mandatory=$true)][string]$Job,[Parameter(Mandatory=$true)][string]$ExpectedJobSha256,
 [Parameter(Mandatory=$true)][string]$Dll,[Parameter(Mandatory=$true)][string]$EnvironmentFile,
 [Parameter(Mandatory=$true)][string]$ProjectState)
$ErrorActionPreference='Stop'
# Hidden NoProfile launchers must not depend on a caller's module-autoload cache.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$environmentPath=(Resolve-Path -LiteralPath $EnvironmentFile).Path
$machine=Get-Content -LiteralPath $environmentPath -Raw -Encoding UTF8|ConvertFrom-Json
if($machine.schema_version -ne 1 -or $machine.backend -ne 'autocad2021-tarch20v10'){throw 'ENV_BACKEND_UNVALIDATED'}
# Resolve configured paths against this machine profile, independent of working directory.
foreach($key in @('acad_exe','tianzheng_sys','trusted_dll_dir','powershell_exe','python_exe','capture_script','compiler')){
 $value=[Environment]::ExpandEnvironmentVariables([string]$machine.$key)
 if(-not [IO.Path]::IsPathRooted($value)){$value=Join-Path (Split-Path -Parent $environmentPath) $value}
 $machine.$key=[IO.Path]::GetFullPath($value)
 if(-not (Test-Path -LiteralPath $machine.$key)){throw ('ENV_PATH_MISSING:'+ $key)}
}
if(-not (Test-Path -LiteralPath $ProjectState)){throw 'PROJECT_STATE_REQUIRED'}
$project=Get-Content -LiteralPath $ProjectState -Raw -Encoding UTF8|ConvertFrom-Json
if($project.session_client.host){
 $existing=Get-Process -Id ([int]$project.session_client.host.pid) -ErrorAction SilentlyContinue
 if($existing -and $existing.StartTime.ToFileTimeUtc() -eq [long]$project.session_client.host.created){throw 'PROJECT_HOST_ALREADY_RUNNING: resume it instead of starting another host'}
}
$buildProof=[IO.Path]::ChangeExtension([IO.Path]::GetFullPath($Dll),'.build.json')
if(-not (Test-Path -LiteralPath $buildProof)){throw 'MODULE_BUILD_RECEIPT_REQUIRED'}
$built=Get-Content -LiteralPath $buildProof -Raw -Encoding UTF8|ConvertFrom-Json
if($built.status -ne 'COMPILED_NOT_LOADED' -or $built.backend -ne $machine.backend -or (Get-FileHash -LiteralPath $Dll -Algorithm SHA256).Hash.ToLower() -ne $built.sha256){throw 'MODULE_BUILD_IDENTITY_MISMATCH'}
$health=& $machine.python_exe -X utf8 (Join-Path $PSScriptRoot 'cad_components.py') doctor --environment $environmentPath
if($LASTEXITCODE -ne 0){throw ('DEPENDENCY_CHECK_FAILED '+($health -join ' '))}
$env:HL_TIANZHENG_SYS=$machine.tianzheng_sys

$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.Runtime.InteropServices;using System.Text;
public static class PrivateV736Base {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]public struct STARTUPINFO{public int cb;public string reserved;public string desktop;public string title;public uint x,y,xsize,ysize,xchars,ychars,fill,flags;public short show,reserved2;public IntPtr reservedPtr,stdin,stdout,stderr;}
 [StructLayout(LayoutKind.Sequential)]public struct PROCESS_INFORMATION{public IntPtr process,thread;public uint pid,tid;}
 [StructLayout(LayoutKind.Sequential)]public struct SECURITY_ATTRIBUTES{public int length;public IntPtr descriptor;[MarshalAs(UnmanagedType.Bool)]public bool inherit;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr CreateDesktop(string name,IntPtr device,IntPtr devmode,uint flags,uint access,IntPtr security);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool CloseDesktop(IntPtr desktop);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr CreateFile(string name,uint access,uint share,ref SECURITY_ATTRIBUTES security,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool CreateProcess(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref STARTUPINFO si,out PROCESS_INFORMATION pi);
 [DllImport("kernel32.dll",SetLastError=true)]public static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)]public static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll",SetLastError=true)]public static extern bool CloseHandle(IntPtr h);
 public static uint Pid(IntPtr h){uint p;GetWindowThreadProcessId(h,out p);return p;}
}
'@
$r=Split-Path -Parent $PSScriptRoot;$jobPath=(Resolve-Path -LiteralPath $Job).Path;$jobHash=(Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash.ToLower();if($jobHash -ne $ExpectedJobSha256.ToLower()){throw 'JOB_HASH_MISMATCH'};$v=Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8|ConvertFrom-Json
# Match V736BaseSession.CheckPath before starting CAD; otherwise BOOT fails before any receipt exists.
$sessionRoot=Split-Path -Parent $jobPath
foreach($inputKey in @('garden','planting','terrain')){
 $inputPath=[IO.Path]::GetFullPath([string]$v.$inputKey)
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($inputPath),$sessionRoot,[StringComparison]::OrdinalIgnoreCase)){throw "SESSION_INPUT_OUTSIDE_JOB_DIRECTORY:$inputKey"}
}
# The terrain slot is an external dependency, never the primary drawing copied into all three slots.
foreach($primaryKey in @('garden','planting')){
 if([string]::Equals([IO.Path]::GetFullPath([string]$v.terrain),[IO.Path]::GetFullPath([string]$v.$primaryKey),[StringComparison]::OrdinalIgnoreCase)){
  throw 'TERRAIN_ALIASES_PRIMARY_DRAWING: bind the actual terrain dependency; a primary DWG is not xref verification'
 }
}
if($v.status -ne 'READY' -or (Get-FileHash -LiteralPath $v.garden -Algorithm SHA256).Hash.ToLower() -ne $v.garden_sha256 -or (Get-FileHash -LiteralPath $v.planting -Algorithm SHA256).Hash.ToLower() -ne $v.planting_sha256 -or (Get-FileHash -LiteralPath $v.terrain -Algorithm SHA256).Hash.ToLower() -ne $v.terrain_sha256){throw 'CANDIDATE_OR_DEPENDENCY_IDENTITY_MISMATCH'}
$desktopName='HLBase736_'+$jobHash.Substring(0,12);$folder=Join-Path $env:TEMP $desktopName;if(Test-Path -LiteralPath $folder){throw 'PRIVATE_RUN_EXISTS'};New-Item -ItemType Directory -Path $folder|Out-Null
$sourceDll=$Dll
$dll=Join-Path $machine.trusted_dll_dir ('HLNativeV736_'+$jobHash.Substring(0,12)+'.dll');if(Test-Path -LiteralPath $dll){throw 'TRUSTED_DLL_NAME_EXISTS'};if(-not (Test-Path -LiteralPath $sourceDll)){throw 'SOURCE_DLL_MISSING'};Copy-Item -LiteralPath $sourceDll -Destination $dll;$dllHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
$env:HL_BASE_JOB=$jobPath;$env:HL_BASE_JOB_SHA256=$jobHash

$scr=Join-Path $folder 'audit.scr';$stdout=Join-Path $folder 'stdout.txt';$stderr=Join-Path $folder 'stderr.txt'
$scriptCommands=@('_.ARX','_L',('"'+(Join-Path $machine.tianzheng_sys 'tch_kernal.arx').Replace('\','/')+'"'),'_.NETLOAD',('"'+$dll.Replace('\','/')+'"'),'HL736BASE')
# AutoCAD 2021 command scripts use the machine ANSI codepage; reject lossy conversion.
$codepage=[Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
$scriptEncoding=[Text.Encoding]::GetEncoding($codepage,[Text.EncoderExceptionFallback]::new(),[Text.DecoderExceptionFallback]::new())
[IO.File]::WriteAllBytes($scr,$scriptEncoding.GetBytes(($scriptCommands -join "`r`n")+"`r`n"))
$desktop=[PrivateV736Base]::CreateDesktop($desktopName,[IntPtr]::Zero,[IntPtr]::Zero,0,0x01FF,[IntPtr]::Zero)
if($desktop -eq [IntPtr]::Zero){throw ('CREATE_PRIVATE_DESKTOP_FAILED '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
$sa=New-Object PrivateV736Base+SECURITY_ATTRIBUTES;$sa.length=[Runtime.InteropServices.Marshal]::SizeOf($sa);$sa.inherit=$true
$out=[PrivateV736Base]::CreateFile($stdout,0x40000000,1,[ref]$sa,2,0,[IntPtr]::Zero);$err=[PrivateV736Base]::CreateFile($stderr,0x40000000,1,[ref]$sa,2,0,[IntPtr]::Zero);$nul=[PrivateV736Base]::CreateFile('NUL',[uint32]2147483648,3,[ref]$sa,3,0,[IntPtr]::Zero)
if($out.ToInt64() -eq -1 -or $err.ToInt64() -eq -1 -or $nul.ToInt64() -eq -1){throw 'REDIRECTION_HANDLE_FAILED'}
# Visible only on this private desktop so AutoCAD's graphics surface is actually rendered.
# SW_SHOWNOACTIVATE does not activate a window and the user's input desktop is never switched.
$si=New-Object PrivateV736Base+STARTUPINFO;$si.cb=[Runtime.InteropServices.Marshal]::SizeOf($si);$si.desktop=$desktopName;$si.flags=0x101;$si.show=4;$si.stdin=$nul;$si.stdout=$out;$si.stderr=$err
$exe=$machine.acad_exe;$command=New-Object System.Text.StringBuilder(('"'+$exe+'" /nologo /b "'+$scr+'"'))
$fg=[PrivateV736Base]::Pid([PrivateV736Base]::GetForegroundWindow());$pi=New-Object PrivateV736Base+PROCESS_INFORMATION
$ok=[PrivateV736Base]::CreateProcess($exe,$command,[IntPtr]::Zero,[IntPtr]::Zero,$true,0x08000400,[IntPtr]::Zero,$machine.tianzheng_sys,[ref]$si,[ref]$pi)
if(!$ok){throw ('CREATE_PROCESS_FAILED '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
$initialRole=if($v.initial_role -eq 'planting'){'planting'}else{'garden'}
$initialHashKey=$initialRole+'_sha256'
$after=[PrivateV736Base]::Pid([PrivateV736Base]::GetForegroundWindow());$launch=@{environment=$environmentPath;status='PRIVATE_DESKTOP_PROCESS_STARTED';pid=$pi.pid;foreground_before=$fg;foreground_after=$after;stdout=$stdout;stderr=$stderr;candidate=$v.$initialRole;candidate_sha256=$v.$initialHashKey;at=[DateTimeOffset]::Now.ToString('o')}
$launch|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $folder 'launch.json') -Encoding UTF8;$launch|ConvertTo-Json
# Register this actual PID/DLL/job in the existing technical state, before waiting for native READY.
# No CAD request is submitted here. A new model reads the same pointer through 接续读取.py.
& $machine.python_exe -X utf8 (Join-Path $PSScriptRoot 'cad_session_client.py') --state $ProjectState bind --job $jobPath --launch (Join-Path $folder 'launch.json') --loaded-dll $dll
if($LASTEXITCODE -ne 0){Write-Warning 'SESSION_CLIENT_BIND_FAILED: inspect this launch; do not start a second CAD process'}
# A known Tianzheng tip can block LoadArx when the private window is rendered.
# Handle only this process's exact tip title on its private desktop, once per HWND, bounded to startup.
$startupScript=Join-Path $folder 'startup_helper.ps1'
$q={param($s) "'"+([string]$s).Replace("'","''")+"'"}
$startupLine='& '+(& $q (Join-Path $PSScriptRoot 'handle_cad_startup.ps1'))+' -Launch '+(& $q (Join-Path $folder 'launch.json'))+' -Session '+(& $q $sessionRoot)
[IO.File]::WriteAllText($startupScript,$startupLine,[Text.UTF8Encoding]::new($true))
& (Join-Path $PSScriptRoot 'run_private_cad_script.ps1') -Desktop $desktopName -Script $startupScript
[void][PrivateV736Base]::CloseHandle($pi.thread);[void][PrivateV736Base]::CloseHandle($out);[void][PrivateV736Base]::CloseHandle($err);[void][PrivateV736Base]::CloseHandle($nul)
[void][PrivateV736Base]::WaitForSingleObject($pi.process,[uint32]4294967295);$exit=0;[void][PrivateV736Base]::GetExitCodeProcess($pi.process,[ref]$exit);[void][PrivateV736Base]::CloseHandle($pi.process);[void][PrivateV736Base]::CloseDesktop($desktop)
# FixedProfile is shared with manually launched CAD, even for a private desktop.
# Read the two real settings after the child exits, including an abnormal exit.
$dialogKey=$machine.manual_dialog_registry
foreach($name in @('FileDialog','CommandDialogs')){
 $value=Get-ItemPropertyValue -LiteralPath $dialogKey -Name $name -ErrorAction Stop
 if($value -ne 1){Set-ItemProperty -LiteralPath $dialogKey -Name $name -Type DWord -Value 1 -ErrorAction Stop}
 if((Get-ItemPropertyValue -LiteralPath $dialogKey -Name $name) -ne 1){throw ('MANUAL_DIALOG_RESTORE_FAILED '+$name)}
}
@{pid=$pi.pid;exit_code=$exit;at=[DateTimeOffset]::Now.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $folder 'exit.json') -Encoding UTF8
if((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -eq $dllHash){Remove-Item -LiteralPath $dll};Write-Output "PRIVATE_DESKTOP_PROCESS_EXITED $exit"
