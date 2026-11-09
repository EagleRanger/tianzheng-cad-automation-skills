param([Parameter(Mandatory=$true)][string]$Desktop,[Parameter(Mandatory=$true)][string]$CloseReceipt,[Parameter(Mandatory=$true)][string]$RequestReceipt,[string]$FailureWorkReceipt)
$ErrorActionPreference='Stop'
$env:PSModulePath=$env:WINDIR+'\System32\WindowsPowerShell\v1.0\Modules'
if(Test-Path -LiteralPath $RequestReceipt){throw 'CLOSE_ALREADY_REQUESTED'}
$launch=Get-Content -LiteralPath (Join-Path $env:TEMP "$Desktop\launch.json") -Raw -Encoding UTF8|ConvertFrom-Json
$c=Get-Content -LiteralPath $CloseReceipt -Raw -Encoding UTF8|ConvertFrom-Json
if($c.status -ne 'DOCUMENTS_CLOSED_AWAITING_ORDINARY_WINDOW_CLOSE' -or $c.pid -ne $launch.pid -or @($c.documents | Where-Object {!$_.closed}).Count -ne 0){throw 'CLOSE_RECEIPT_MISMATCH'}
foreach($d in $c.documents){if((Get-FileHash -LiteralPath $d.snapshot -Algorithm SHA256).Hash.ToLower() -ne $d.sha256){throw 'PROTECTED_HASH_MISMATCH'}}
if($c.result){
 if((Get-FileHash -LiteralPath $c.result -Algorithm SHA256).Hash.ToLower() -ne $c.result_hash){throw 'RESULT_HASH_MISMATCH'}
} else {
 if(!$FailureWorkReceipt){throw 'NO_RESULT_FAILURE_RECEIPT_REQUIRED'}
 $failed=Get-Content -LiteralPath $FailureWorkReceipt -Raw -Encoding UTF8|ConvertFrom-Json
 if($failed.pid -ne $c.pid -or $failed.status -ne 'WORK_FAILED_PROTECTION_REQUIRED' -or !$failed.error -or !$failed.settings_restored -or (Test-Path -LiteralPath $failed.output)){throw 'FAILURE_RECEIPT_MISMATCH'}
}
$proc=Get-CimInstance Win32_Process -Filter "ProcessId=$($c.pid)"
if(!$proc -or !$proc.CommandLine.Contains("$Desktop\audit.scr") -or [Math]::Abs(($proc.CreationDate-([DateTimeOffset]::Parse($launch.at)).LocalDateTime).TotalSeconds) -gt 2){throw 'PROCESS_IDENTITY_MISMATCH'}
Add-Type -TypeDefinition @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class PrivateCadNormalClose {delegate bool E(IntPtr h,IntPtr l);[DllImport("user32.dll",SetLastError=true)]static extern IntPtr OpenDesktop(string s,uint f,bool i,uint a);[DllImport("user32.dll")]static extern bool EnumDesktopWindows(IntPtr d,E e,IntPtr l);[DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);[DllImport("user32.dll")]static extern int GetWindowText(IntPtr h,StringBuilder t,int n);[DllImport("user32.dll")]static extern int GetClassName(IntPtr h,StringBuilder t,int n);[DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);[DllImport("user32.dll")]static extern bool CloseDesktop(IntPtr d);[DllImport("user32.dll",SetLastError=true)]static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);[DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();public static string Run(string desktop,uint pid,string receipt){var d=OpenDesktop(desktop,0,false,65);if(d==IntPtr.Zero)throw new Exception("DESKTOP_MISMATCH");var frames=new List<IntPtr>();int dialogs=0;EnumDesktopWindows(d,(h,l)=>{uint id;GetWindowThreadProcessId(h,out id);if(id==pid){var c=new StringBuilder(256);var t=new StringBuilder(1024);GetClassName(h,c,256);GetWindowText(h,t,1024);if(c.ToString()=="AfxMDIFrame140u"&&t.ToString().TrimStart().EndsWith("AutoCAD 2021 - [开始]"))frames.Add(h);if(c.ToString()=="#32770"&&IsWindowVisible(h)&&t.ToString()!="Autodesk AutoCAD 2021 - 帮助")dialogs++;}return true;},IntPtr.Zero);if(frames.Count!=1||dialogs!=0)throw new Exception("FRAME_OR_DIALOG_MISMATCH");uint before;GetWindowThreadProcessId(GetForegroundWindow(),out before);System.IO.File.WriteAllText(receipt,"{\"status\":\"PREPARED_NO_RETRY\",\"pid\":"+pid+",\"foreground_before\":"+before+"}");bool ok=PostMessage(frames[0],16,IntPtr.Zero,IntPtr.Zero);int err=Marshal.GetLastWin32Error();uint after;GetWindowThreadProcessId(GetForegroundWindow(),out after);CloseDesktop(d);if(!ok)throw new Exception("POST_FAILED "+err);return "posted="+ok+" foreground_before="+before+" foreground_after="+after;}}
'@
[PrivateCadNormalClose]::Run($Desktop,[uint32]$c.pid,$RequestReceipt)
