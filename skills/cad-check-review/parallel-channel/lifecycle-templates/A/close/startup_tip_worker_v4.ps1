# BINDING TEMPLATE ONLY: replace PID/created/HWND=0, DBMOD=-1, root/run/desktop/hash from current evidence; never infer or replay.
param([Parameter(Mandatory)][string]$JobName)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root='C:\RECEIVER\CAD_ROOT';$dir=Join-Path $root 'runs/RECEIVER_RUN_ID/resource_closeout/A';$target=Join-Path $dir 'work_A_preserved_0.dwg';$intent=Join-Path $dir 'close_intent.json';$hash='RECEIVER_PROTECTED_SHA256'
$null=[Reflection.Assembly]::LoadFrom((Join-Path $root 'reports/cad_multi_window_interface_research/independent_project_jobs_v3/bin/OwnStartupJobV4.dll'));[CadResearchStartupJobV4.OwnHelperJob]::VerifyOwnMembership($JobName)
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class Quit112 {
 [DllImport("oleaut32.dll",PreserveSig=false)] static extern void GetActiveObject(ref Guid clsid,IntPtr reserved,[MarshalAs(UnmanagedType.IUnknown)]out object instance);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static object Application(){var t=Type.GetTypeFromProgID("AutoCAD.Application.24",true);Guid g=t.GUID;object o;GetActiveObject(ref g,IntPtr.Zero,out o);return o;}
}
'@
$r=[ordered]@{status='UNKNOWN';error=$null;close_attempted=$false;pid=0;protected=$target}
try{
 if(Test-Path -LiteralPath $intent){throw 'CLOSE_ALREADY_ATTEMPTED'}
 $p=Get-Process -Id 0 -ErrorAction Stop;if($p.StartTime.ToUniversalTime().ToFileTimeUtc()-ne0 -or $p.Path-ine'C:\Program Files\Autodesk\AutoCAD 2021\acad.exe'){throw 'PROCESS_MISMATCH'}
 $w=[IntPtr]0;$pidValue=[uint32]0;if(-not [Quit112]::IsWindow($w)){throw 'WINDOW_MISSING'};$null=[Quit112]::GetWindowThreadProcessId($w,[ref]$pidValue);if($pidValue-ne0){throw 'WINDOW_OWNER_MISMATCH'}
 $app=[Quit112]::Application();if([int64]$app.HWND-ne0 -or -not [bool]$app.GetAcadState().IsQuiescent){throw 'APPLICATION_MISMATCH_OR_BUSY'}
 $active=$app.ActiveDocument;if([int]$app.Documents.Count-ne1 -or [string]$active.FullName-ine$target -or -not [bool]$active.Saved -or [int]$active.GetVariable('DBMOD')-ne0 -or [int]$active.GetVariable('CMDACTIVE')-ne0 -or -not [string]::IsNullOrWhiteSpace([string]$active.GetVariable('CMDNAMES'))){throw 'ACTIVE_DOCUMENT_NOT_PROTECTED_OR_NOT_IDLE'}
 foreach($doc in $app.Documents){if([string]$doc.FullName-ine$target -and (([string]$doc.Name-cne'Drawing1.dwg') -or -not [string]::IsNullOrWhiteSpace([string]$doc.FullName) -or -not [bool]$doc.Saved -or [int]$doc.GetVariable('DBMOD')-ne0)){throw 'OTHER_DOCUMENT_NOT_CLEAN'}}
 if((& (Join-Path $root 'scripts/get_shared_file_sha256_v1.ps1') -Path $target)-cne$hash){throw 'PROTECTED_FILE_HASH_MISMATCH'}
 $b=[Text.UTF8Encoding]::new($false).GetBytes((@{utc=[DateTime]::UtcNow.ToString('o');pid=0;protected=$target;sha256=$hash;action='NORMAL_QUIT'}|ConvertTo-Json));$f=[IO.File]::Open($intent,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
 $r.close_attempted=$true;$app.Quit();$r.status='QUIT_RETURNED_VERIFY_PROCESS'
}catch{$r.error=$_.Exception.ToString()}
$r|ConvertTo-Json -Depth 8 -Compress
