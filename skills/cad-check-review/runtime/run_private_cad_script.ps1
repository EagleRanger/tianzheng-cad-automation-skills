param([Parameter(Mandatory=$true)][string]$Desktop,[Parameter(Mandatory=$true)][string]$Script)
$ErrorActionPreference='Stop'
if($Desktop -notmatch '^HLBase736_[0-9a-f]{12}$'){throw 'NOT_PROJECT_PRIVATE_DESKTOP'}
$scriptPath=(Resolve-Path -LiteralPath $Script).Path
Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class CadPrivateRunner {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct SI{public int cb;public string reserved,desktop,title;public uint x,y,xsize,ysize,xchars,ychars,fill,flags;public short show,reserved2;public IntPtr reservedPtr,stdin,stdout,stderr;}
 [StructLayout(LayoutKind.Sequential)] public struct PI{public IntPtr process,thread;public uint pid,tid;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool CreateProcess(string app,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref SI si,out PI pi);
 [DllImport("kernel32.dll")]public static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll")]public static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll")]public static extern bool CloseHandle(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
}
'@
$before=[CadPrivateRunner]::GetForegroundWindow()
$si=New-Object CadPrivateRunner+SI;$si.cb=[Runtime.InteropServices.Marshal]::SizeOf($si);$si.desktop=$Desktop;$si.flags=1;$si.show=0
$pi=New-Object CadPrivateRunner+PI
$exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$cmd=New-Object Text.StringBuilder(('"'+$exe+'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$scriptPath+'"'))
if(-not [CadPrivateRunner]::CreateProcess($exe,$cmd,[IntPtr]::Zero,[IntPtr]::Zero,$false,0x08000400,[IntPtr]::Zero,$PSScriptRoot,[ref]$si,[ref]$pi)){throw ('PRIVATE_HELPER_FAILED '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
$wait=[CadPrivateRunner]::WaitForSingleObject($pi.process,10000)
[uint32]$childExit=259;[void][CadPrivateRunner]::GetExitCodeProcess($pi.process,[ref]$childExit)
[void][CadPrivateRunner]::CloseHandle($pi.thread);[void][CadPrivateRunner]::CloseHandle($pi.process)
@{helper_pid=$pi.pid;wait=$wait;exit_code=$childExit;foreground_before=$before.ToInt64();foreground_after=[CadPrivateRunner]::GetForegroundWindow().ToInt64()}|ConvertTo-Json -Compress
if($wait -eq 0 -and $childExit -ne 0){exit $childExit}
