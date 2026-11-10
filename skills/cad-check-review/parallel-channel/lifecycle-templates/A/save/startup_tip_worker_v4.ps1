# BINDING TEMPLATE ONLY: replace PID/created/HWND=0, DBMOD=-1, root/run/desktop/hash from current evidence; never infer or replay.
param([Parameter(Mandatory)][string]$JobName)
$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root='C:\RECEIVER\CAD_ROOT';$dir=Join-Path $root 'runs/RECEIVER_RUN_ID/resource_closeout/A'
$target=Join-Path $dir 'work_A_preserved_0.dwg';$expected=Join-Path $root 'runs/RECEIVER_RUN_ID/hosts/A/AB/work.dwg';$intent=Join-Path $dir 'save_intent.json'
$null=[Reflection.Assembly]::LoadFrom((Join-Path $root 'reports/cad_multi_window_interface_research/independent_project_jobs_v3/bin/OwnStartupJobV4.dll'));[CadResearchStartupJobV4.OwnHelperJob]::VerifyOwnMembership($JobName)
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class Save112 {
 [DllImport("oleaut32.dll",PreserveSig=false)] static extern void GetActiveObject(ref Guid clsid,IntPtr reserved,[MarshalAs(UnmanagedType.IUnknown)]out object instance);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static object Application(){var t=Type.GetTypeFromProgID("AutoCAD.Application.24",true);Guid g=t.GUID;object o;GetActiveObject(ref g,IntPtr.Zero,out o);return o;}
}
'@
$r=[ordered]@{status='UNKNOWN';phase='PRECHECK';save_attempted=$false;target=$target;error=$null}
try{
 if((Test-Path -LiteralPath $target)-or(Test-Path -LiteralPath $intent)){throw 'TARGET_OR_INTENT_EXISTS_NO_RETRY'}
 $p=Get-Process -Id 0 -ErrorAction Stop;if($p.StartTime.ToUniversalTime().ToFileTimeUtc()-ne 0 -or $p.Path -ine 'C:\Program Files\Autodesk\AutoCAD 2021\acad.exe'){throw 'PROCESS_MISMATCH'}
 $w=[IntPtr]0;$pidValue=[uint32]0;if(-not [Save112]::IsWindow($w)){throw 'WINDOW_MISSING'};$null=[Save112]::GetWindowThreadProcessId($w,[ref]$pidValue);if($pidValue-ne0){throw 'WINDOW_OWNER_MISMATCH'}
 $app=[Save112]::Application();if([int64]$app.HWND-ne0 -or -not [bool]$app.GetAcadState().IsQuiescent){throw 'APPLICATION_MISMATCH_OR_BUSY'}
 $doc=$app.ActiveDocument;if([int]$app.Documents.Count-ne1 -or [string]$doc.FullName-ine$expected -or [bool]$doc.Saved -or [int]$doc.GetVariable('DBMOD')-ne(-1) -or [int]$doc.GetVariable('CMDACTIVE')-ne0 -or -not [string]::IsNullOrWhiteSpace([string]$doc.GetVariable('CMDNAMES'))){throw 'ACTIVE_DOCUMENT_STATE_CHANGED'}
 foreach($other in $app.Documents){if([string]$other.FullName-ine$expected -and (([string]$other.Name-cne'Drawing1.dwg') -or -not [string]::IsNullOrWhiteSpace([string]$other.FullName) -or -not [bool]$other.Saved -or [int]$other.GetVariable('DBMOD')-ne0)){throw 'OTHER_DOCUMENT_NOT_CLEAN'}}
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes((@{utc=[DateTime]::UtcNow.ToString('o');pid=0;source=$expected;target=$target;action='SAVEAS_NEW_ISOLATED_COPY'}|ConvertTo-Json));$f=[IO.File]::Open($intent,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
 $r.phase='SAVEAS';$r.save_attempted=$true;$doc.SaveAs($target)
 $r.phase='VERIFY';$item=Get-Item -LiteralPath $target -ErrorAction Stop;$r.length=$item.Length;$r.full_name=[string]$doc.FullName;$r.saved=[bool]$doc.Saved;$r.dbmod=[int]$doc.GetVariable('DBMOD')
 if($r.length-le0 -or $r.full_name-ine$target -or -not $r.saved -or $r.dbmod-ne0){throw 'SAVE_READBACK_MISMATCH'};$r.status='SAVE_RETURNED_VERIFY_INDEPENDENTLY'
}catch{$r.error=$_.Exception.ToString()}
$r|ConvertTo-Json -Depth 8 -Compress
