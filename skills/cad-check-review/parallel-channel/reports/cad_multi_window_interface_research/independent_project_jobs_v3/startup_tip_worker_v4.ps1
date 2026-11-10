param([Parameter(Mandatory)][string]$JobName,[Parameter(Mandatory)][string]$Desktop,[int]$TargetPid,[long]$TargetCreated,[string]$Session,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'));$ri=Get-Item -LiteralPath $root;if($ri.Attributes-band[IO.FileAttributes]::ReparsePoint){$root=$ri.ResolveLinkTarget($true).FullName}
$lib=Join-Path $root 'reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll';if((Get-FileHash -LiteralPath $lib).Hash-cne(Get-Content -LiteralPath (Join-Path $root 'config/parallel_receiver.json') -Raw|ConvertFrom-Json).helper_sha256){throw 'STARTUP_JOB_DLL'};$null=[Reflection.Assembly]::LoadFrom($lib);[CadCommandUiaV2.OwnHelperJob]::VerifyOwnMembership($JobName)
Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class FixedStartupTipV4 {
 delegate bool CB(IntPtr h,IntPtr p);
 [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]static extern IntPtr GetThreadDesktop(uint t);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetUserObjectInformation(IntPtr h,int i,StringBuilder b,int n,out int need);
 [DllImport("user32.dll")]static extern bool EnumWindows(CB c,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",SetLastError=true)]static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static string Desktop(){var b=new StringBuilder(256);int n;if(!GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()),2,b,b.Capacity*2,out n))throw new InvalidOperationException("DESKTOP_UNKNOWN");return b.ToString();}
 public static long Find(uint pid){long found=0;int count=0;EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p!=pid)return true;var t=new StringBuilder(256);var c=new StringBuilder(256);GetWindowText(h,t,256);GetClassName(h,c,256);if(c.ToString()=="#32770"&&t.ToString()=="日积月累"){found=h.ToInt64();count++;}return true;},IntPtr.Zero);if(count>1)throw new InvalidOperationException("MULTIPLE_TIPS");return found;}
 public static bool Close(long hwnd){return PostMessage(new IntPtr(hwnd),0x10,IntPtr.Zero,IntPtr.Zero);}
}
'@
$actual=[FixedStartupTipV4]::Desktop();if($actual-cne$Desktop){throw 'STARTUP_HELPER_DESKTOP_MISMATCH'}
if($ValidateOnly){@{status='PASS_STARTUP_PRIVATE_DESKTOP_JOB_ABI';desktop=$actual;CAD_calls=0;window_actions=0}|ConvertTo-Json -Compress;return}
if($Desktop-cnotmatch'^CXResearchV3_[A-F0-9]{16}$'-or$TargetPid-le0-or$TargetCreated-le0){throw 'STARTUP_HELPER_IDENTITY'}
function AssertTarget {$p=Get-Process -Id $TargetPid -ErrorAction Stop;if($p.StartTime.ToFileTimeUtc()-ne$TargetCreated-or$p.Path-ine'C:\Program Files\Autodesk\AutoCAD 2021\acad.exe'){throw 'STARTUP_HELPER_OWNER_CHANGED'}}
function WriteNew([string]$Path,$Data){$tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Data|ConvertTo-Json -Depth 5 -Compress));$f=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()};[IO.File]::Move($tmp,$Path,$false)}
$clock=[Diagnostics.Stopwatch]::StartNew();$attempted=$false;$closed=$false;$tip=[long]0;$errorMessage=$null
try{while($clock.Elapsed.TotalSeconds-lt80){AssertTarget;if((Test-Path -LiteralPath (Join-Path $Session 'native_ready.json'))-or@(Get-ChildItem -LiteralPath $Session -Filter 'boot_failed_*.json' -File).Count){break};if(-not$attempted){$tip=[FixedStartupTipV4]::Find([uint32]$TargetPid);if($tip){AssertTarget;WriteNew (Join-Path $Session 'startup_tip_intent.json') @{pid=$TargetPid;created=$TargetCreated;hwnd=$tip;desktop=$actual;state='INTENT_MAY_HAVE_ENTERED_NO_REPLAY';utc=[DateTimeOffset]::UtcNow.ToString('o')};$attempted=$true;$closed=[FixedStartupTipV4]::Close($tip);if(-not$closed){throw 'STARTUP_TIP_POST_FAILED_NO_RETRY'}}};Start-Sleep -Milliseconds 300}}catch{$errorMessage=$_.Exception.ToString()}
WriteNew (Join-Path $Session 'startup_tip_result.json') @{desktop=$actual;pid=$TargetPid;created=$TargetCreated;tip_hwnd=$tip;attempted=$attempted;postmessage_returned=$closed;native_ready=(Test-Path -LiteralPath (Join-Path $Session 'native_ready.json'));error=$errorMessage;elapsed_ms=$clock.ElapsedMilliseconds}
if($errorMessage){throw $errorMessage}
