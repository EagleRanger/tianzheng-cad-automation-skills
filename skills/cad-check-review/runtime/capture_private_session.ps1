param([Parameter(Mandatory=$true)][string]$Manifest)
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules'
$m=Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8|ConvertFrom-Json
try{
 Add-Type @'
using System;using System.Runtime.InteropServices;
public static class CaptureHostIdentity {
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 public static uint Pid(long h){uint p;GetWindowThreadProcessId(new IntPtr(h),out p);return p;}
}
'@
 $progid=if($m.com_progid){[string]$m.com_progid}else{'AutoCAD.Application.24'}
 $c=[Runtime.InteropServices.Marshal]::GetActiveObject($progid)
 if([CaptureHostIdentity]::Pid([long]$c.HWND) -ne [uint32]$m.pid -or -not $c.GetAcadState().IsQuiescent){throw 'CAPTURE_HOST_BUSY_OR_CHANGED'}
 $d=$c.ActiveDocument
 if($d.FullName -ne $m.live_document -or $d.GetVariable('CTAB') -ne $m.layout -or [int]$d.GetVariable('CMDACTIVE') -ne 0){throw 'CAPTURE_DOCUMENT_OR_LAYOUT_CHANGED'}
 if($m.layout -ne 'Model' -and [int]$d.GetVariable('CVPORT') -ne 1){throw 'CAPTURE_NOT_PAPER_SPACE'}
 $ctr=$d.GetVariable('VIEWCTR')
 if([math]::Abs([double]$ctr[0]-[double]$m.x) -gt 0.001 -or [math]::Abs([double]$ctr[1]-[double]$m.y) -gt 0.001){throw ('CAPTURE_VIEW_CHANGED '+($ctr -join ','))}
 $captureScript=[string]$m.capture_script
 if(-not $captureScript){$codexRoot=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'};$captureScript=Join-Path $codexRoot 'skills/cad-check-review/scripts/cad_capture_compat.ps1'}
 & $captureScript -OutputPath $m.image -MetadataPath $m.metadata -WindowHandle ([long]$c.HWND) -ProcessId ([int]$m.pid) -Backend PrintWindow | Out-Null
 @{status='ACTUAL_CAD_VIEW_CAPTURED';document=$d.FullName;pid=$m.pid;layout=$m.layout;view_center=$ctr;source_sha256=$m.source_sha256;image=$m.image;metadata=$m.metadata}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $m.receipt -Encoding UTF8
}catch{@{status='CAPTURE_FAILED';error=$_.ToString()}|ConvertTo-Json|Set-Content -LiteralPath $m.receipt -Encoding UTF8;exit 1}
