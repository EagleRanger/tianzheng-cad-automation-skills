param([Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,[Parameter(Mandatory)][int]$LeaseControllerPid,[Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
# Exact own-job proof must precede UIA assembly loading or any CAD observation.
$library=Join-Path $PSScriptRoot 'bin/CadCommandOwnHelperJobV2.dll'
if((Get-FileHash $library).Hash-cne'FABE627922D36DBF3329A97F5B95F71B841D14B0767474D44A6A8E065AC532F3'){throw 'OWN_JOB_LIBRARY_HASH'}
$null=[Reflection.Assembly]::LoadFrom($library)
[CadCommandUiaV2.OwnHelperJob]::VerifyOwnMembership($JobName)
if([Threading.Thread]::CurrentThread.GetApartmentState()-ne'MTA'){throw 'UIA_MTA_REQUIRED'}
. (Join-Path $PSScriptRoot 'command_contract_v1.ps1')
. (Join-Path $PSScriptRoot 'evidence_policy_v1.ps1')
. (Join-Path $PSScriptRoot 'uia_walk_kernel_v1.ps1')
. (Join-Path $PSScriptRoot 'uia_adapter_v1.ps1')
$projectRootUiaV1=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scopeFull=Assert-CadPreparationPathV1 $ScopePath $projectRootUiaV1
if((Get-FileHash $scopeFull).Hash-cne$ScopeSha256){throw 'UIA_SCOPE_HASH'}
$scope=Read-CadPreparationScopeV1 $scopeFull
$v=Assert-CadCommandUiaInspectionScopeV1 $scope $projectRootUiaV1
Assert-CadCommandUiaInspectionDependenciesV1 $projectRootUiaV1
Assert-CadCommandUiaExternalRuntimeV1
# In-memory definitions only. No native calls during ValidateOnly.
Add-Type -Path (Join-Path $PSScriptRoot 'CommandNative.cs')
foreach($assembly in @('WindowsBase','UIAutomationTypes','UIAutomationClient')){
 $null=[Reflection.Assembly]::LoadFrom(('C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF\'+$assembly+'.dll'))
}
$null=[System.Windows.Automation.AutomationElement]
$null=[System.Windows.Automation.ValuePattern]
$null=[System.Windows.Automation.TextPattern]
if($ValidateOnly){@{status='PASS_ACTUAL_WORKER_ABI_NO_CAD_UIA';scope_sha256=$ScopeSha256;exact_own_job_verified=$true;apartment='MTA';cad_calls=0;uia_calls=0;cad_native_calls=0;lease_taken=$false}|ConvertTo-Json -Compress;return}
function AssertInspectionLeaseV1 {
 $controller=Get-Process -Id $LeaseControllerPid -ErrorAction Stop
 if($controller.StartTime.ToUniversalTime().Ticks-ne(ConvertTo-CadTargetV1StartTicks $LeaseControllerStartUtc)){throw 'INSPECTION_LEASE_PROCESS_CHANGED'}
 $lease=Read-CadPreparationScopeV1 (Join-Path $projectRootUiaV1 '.cad-operation-owner.json')
 if($lease.process_id-ne$LeaseControllerPid-or$lease.operation_id-cne$scope.run_id){throw 'INSPECTION_LEASE_RECORD'}
 $mutex=[Threading.Mutex]::OpenExisting('Local\Codex.TianzhengCad.Exclusive.v1');$acquired=$false
 try{try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true};if($acquired){throw 'INSPECTION_SERIAL_LEASE_NOT_HELD'}}finally{if($acquired){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function GetInspectionOwnerV1($Expected){
 AssertInspectionLeaseV1
 $p=Get-Process -Id $Expected.process_id -ErrorAction Stop
 $node=[CadCommandUiaNativeV1.Native]::Describe($Expected.window_handle,$Expected.window_handle)
 if($p.StartTime.ToUniversalTime().Ticks-ne(ConvertTo-CadTargetV1StartTicks $Expected.process_start_time_utc)-or$p.Path-ine$Expected.process_image_path-or-not$node.valid-or$node.pid-ne$Expected.process_id-or$node.thread-le0){throw 'INSPECTION_OS_OWNER_CHANGED'}
 [pscustomobject]@{id=$Expected.id;process_id=$p.Id;process_start_time_utc=$p.StartTime.ToUniversalTime().ToString('o');process_image_path=$p.Path;window_handle=$node.hwnd;window_process_id=$node.pid;window_valid=$node.valid;window_enabled=$node.enabled;window_visible=$node.visible;thread=$node.thread;responding=[bool]$p.Responding;serial_lease_held=$true}
}
function GetInspectionOwnersV1 {
 AssertInspectionLeaseV1
 $actual=@(Get-Process -Name acad -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id|Sort-Object)
 $expected=@($v.owners.process_id|Sort-Object)
 if(($actual-join',')-cne($expected-join',')){throw 'INSPECTION_TWO_CAD_SET_CHANGED'}
 foreach($o in $v.owners){GetInspectionOwnerV1 $o}
}

function AssertFreshAnchorV1([bool]$ReadTitles){
 $null=GetInspectionOwnerV1 $v.owners[1]
 foreach($part in $scope.native_anchor.chain){
  $fresh=[CadCommandUiaNativeV1.Native]::Describe($part.native.hwnd,$scope.native_anchor.main_window_handle)
  foreach($property in $part.native.PSObject.Properties){
   if([string]$fresh.($property.Name)-cne[string]$property.Value){throw ('UIA_NATIVE_ANCHOR_CHANGED:'+ $property.Name)}
  }
  if($ReadTitles){
   $read=[CadCommandUiaNativeV1.Native]::ReadText($fresh.hwnd,4096)
   if(-not$read.complete-or$read.timeout-or$read.truncated-or$read.text-cne$part.text){throw 'UIA_NATIVE_ANCHOR_TITLE_CHANGED'}
   $again=[CadCommandUiaNativeV1.Native]::Describe($fresh.hwnd,$scope.native_anchor.main_window_handle)
   foreach($property in $part.native.PSObject.Properties){if([string]$again.($property.Name)-cne[string]$property.Value){throw 'UIA_NATIVE_ANCHOR_POSTTITLE_CHANGED'}}
  }
 }
}
function TestUiaNativeDescendantV1([long]$Handle){
 AssertFreshAnchorV1 $false
 $node=[CadCommandUiaNativeV1.Native]::Describe($Handle,$scope.native_anchor.main_window_handle)
 if(-not$node.valid-or$node.pid-ne$scope.native_anchor.process_id-or$node.thread-ne$scope.native_anchor.chain[3].native.thread-or$node.root-ne$scope.native_anchor.main_window_handle-or$node.root_owner-ne$scope.native_anchor.main_window_handle-or-not$node.style_child-or$node.style_popup-or-not$node.child_of_main){return $false}
 if($Handle-eq$scope.native_anchor.surface_handle){return $true}
 return [CadCommandUiaNativeV1.Native]::Descends($scope.native_anchor.surface_handle,$Handle)
}
$watch=[Diagnostics.Stopwatch]::StartNew();$initial=@();$final=@();$collection=$null;$evidence=$null;$status='UIA_INSPECTION_FAILED';$errorText=$null;$protection='NOT_CHECKED';$called=$false;$freshVerified=$false
$rawPath=Join-Path $v.run 'command_uia_raw.jsonl';$script:rawBytes=0L;$rawStream=$null
function WriteUiaStageV1($Value){
 $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 16 -Compress)+"`n")
 if($script:rawBytes+$bytes.Length-gt1048576){throw 'UIA_RAW_STAGE_LIMIT'}
 $rawStream.Write($bytes,0,$bytes.Length);$rawStream.Flush($true);$script:rawBytes+=$bytes.Length
}
try{
 AssertInspectionLeaseV1
 $rawStream=[IO.FileStream]::new($rawPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $initial=@(GetInspectionOwnersV1)
 WriteUiaStageV1 @{kind='INITIAL_OWNERS';owners=$initial;exact_own_job_verified=$true}
 AssertFreshAnchorV1 $true;$freshVerified=$true
 $uiaRoot=[pscustomobject]@{process_id=$scope.native_anchor.process_id;surface_handle=$scope.native_anchor.surface_handle;native_chain_fresh_verified=$true}
 WriteUiaStageV1 @{kind='BEFORE_UIA';native_anchor=$scope.native_anchor;fresh_native_chain_verified=$true;job_bounds_external_provider=$false}
 $called=$true
 $collection=Read-CadCommandUiaSubtreeV1 $uiaRoot {AssertFreshAnchorV1 $false} {param($handle) TestUiaNativeDescendantV1 $handle} {param($event) WriteUiaStageV1 $event}
 AssertFreshAnchorV1 $true
 $final=@(GetInspectionOwnersV1)
 $evidence=Test-CadCommandUiaEvidenceV1 $uiaRoot $collection.rows $collection.subtree_complete $true
 if((Get-FileHash $scopeFull).Hash-cne$ScopeSha256){throw 'UIA_SCOPE_CHANGED'}
 $status=if($evidence.subtree_evidence_complete){'COMPLETE_UIA_SUBTREE_READ_ONLY'}else{'INCOMPLETE_UIA_SUBTREE_READ_ONLY'}
 WriteUiaStageV1 @{kind='FINAL_OWNERS';owners=$final;status=$status;evidence=$evidence}
}catch{$errorText=$_.Exception.ToString();$status='UIA_INSPECTION_FAILED'}
finally{
 if($null-ne$rawStream){$rawStream.Dispose()}
 try{Assert-CadCommandUiaInspectionProtectionV1 $scope $v $projectRootUiaV1;$protection='UNCHANGED'}catch{$protection=$_.Exception.ToString();$status='FAILED_PROTECTION_CHECK'}
 $rawHash=if(Test-Path -LiteralPath $rawPath){(Get-FileHash $rawPath).Hash}else{$null}
 $receipt=[ordered]@{schema_version=1;profile_id=$scope.profile_id;intent=$scope.intent;run_id=$scope.run_id;scope_sha256=$ScopeSha256;status=$status;error=$errorText;initial_owners=$initial;final_owners=$final;fresh_native_chain_verified=$freshVerified;uia_entry_attempted=$called;collection=$collection;evidence=$evidence;raw_evidence_path=$rawPath;raw_evidence_sha256=$rawHash;raw_evidence_bytes=$script:rawBytes;elapsed_ms=$watch.ElapsedMilliseconds;protected_hashes_after=$protection;modal_state='UNKNOWN';native_idle_verified=$false;send_authorized=$false;cad_com_count=0;cad_rot_count=0;cad_command_count=0;input_count=0;click_count=0;activate_count=0;focus_change_count=0;load_count=0;launch_count=0;save_count=0;close_count=0;kill_cad_count=0;register_count=0;retry_count=0;multi_dialog_control_proven=$false;own_job_verified_before_uia=$true;external_cad_memory_bounded=$false}
 Write-CadPreparationJsonV1 (Join-Path $v.run 'command_uia_worker_receipt.json') $receipt
}
if($status-cnotin@('COMPLETE_UIA_SUBTREE_READ_ONLY','INCOMPLETE_UIA_SUBTREE_READ_ONLY')){exit 1}
