function Read-DimensionStageSignalV1($Scope,$Op) {
 $p=Join-Path $Scope.absolute_run ('signals/'+$Op.id+'.log')
 if(-not(Test-Path $p)){return $null}
 $raw=[IO.File]::ReadAllText($p)
 if(-not$raw.EndsWith("`n")){return $null}
 $lines=@($raw-split'\r?\n'|Where-Object{$_})
 $typed=@($lines|Where-Object {$_-like'CX_MULTI_OWNER_PROBE_V1|*'})
 if($typed.Count-lt2){return $null}
 if($typed.Count-ne2-or$lines.Count-ne4){throw 'DIM_NATIVE_SIGNAL_DUPLICATED'}
 $rows=@()
 foreach($line in $typed){$f=$line.Split('|');if($f.Count-ne10-or$f[1]-cne$Op.nonce-or$f[2]-cne$Scope.run_id-or$f[3]-cne$Op.id-or$f[4]-cne'B'-or$f[5]-cne[string]$Scope.owners[1].window_handle){throw 'DIM_NATIVE_SIGNAL_IDENTITY'};foreach($i in @(7,8,9)){if($f[$i]-cnotmatch'^\d+$'){throw 'DIM_NATIVE_SIGNAL_NUMERIC'}};$rows+=@([pscustomobject]@{stage=$f[6];tick=[long]$f[7];dbmod=[int]$f[8];model_count=[int]$f[9]})}
 if(($rows.stage-join',')-cne'ACK,COMPLETE'){throw 'DIM_NATIVE_SIGNAL_ORDER'}
 $duration=($rows[1].tick-$rows[0].tick+4294967296L)%4294967296L
 if($duration-gt15000-or($rows[1].model_count-$rows[0].model_count)-ne$Op.expected_model_delta){throw 'DIM_NATIVE_MODEL_DELTA_OR_DEADLINE'}
 foreach($row in $rows){if(@($lines|Where-Object {$_-ceq('CX_CAD_SIGNAL_V1|CAD_COMMAND_'+$row.stage+'|'+$row.tick)}).Count-ne1){throw 'DIM_NATIVE_OBSERVER_DISAGREES'}}
 [pscustomobject]@{status='PASS';native_ms=$duration;ack=$rows[0];complete=$rows[1]}
}
function Assert-DimensionWorkerReceiptV1($Data,$Scope,$Op) {
 if($null-eq$Data-or$Data.status-cne'PASS'-or$Data.run_id-cne$Scope.run_id-or$Data.operation_id-cne$Op.id-or$Data.nonce-cne$Op.nonce-or$Data.scope_sha256-cne$Scope.bound_scope_sha256-or$Data.post_call_count-ne1-or-not$Data.send_call_returned){throw 'DIM_WORKER_RECEIPT_IDENTITY_OR_STATE'}
}
function Get-DimensionStageVerdictV1([bool]$ReceiptValid,[bool]$NativeValid,[bool]$CleanExit,[string]$CleanupError='') {
 if($ReceiptValid-and$NativeValid-and$CleanExit-and-not$CleanupError){'PASS_STAGE_TRANSPORT_AND_NATIVE__BUSINESS_AUDIT_REQUIRED'}else{'PARTIAL_OR_UNKNOWN_STAGE__NO_RETRY'}
}
function Wait-DimensionLateNativeBoundaryV5($Scope,$Op,[int]$BudgetMilliseconds=3000,[scriptblock]$OnSample={}) {
 if($BudgetMilliseconds-lt1-or$BudgetMilliseconds-gt3000){throw 'DIM_LATE_BOUNDARY_BUDGET'}
 $watch=[Diagnostics.Stopwatch]::StartNew();$seenAt=$null;$native=$null
 while($watch.ElapsedMilliseconds-lt$BudgetMilliseconds){
  $null=&$OnSample
  $native=Read-DimensionStageSignalV1 $Scope $Op
  if($native){
   if($null-eq$seenAt){$seenAt=$watch.ElapsedMilliseconds}
   if($watch.ElapsedMilliseconds-$seenAt-ge100){return [pscustomobject]@{status='NATIVE_BOUNDARY_OBSERVED__HELPER_STATUS_UNCHANGED';native=$native;elapsed_ms=$watch.ElapsedMilliseconds;helper_pass_promoted=$false;new_send_count=0;cad_calls=0;quiescence='FILE_BOUNDARY_ONLY_NOT_COM_RETURN'}}
  }
  Start-Sleep -Milliseconds 20
 }
 [pscustomobject]@{status='NATIVE_BOUNDARY_UNRESOLVED_NO_RETRY';native=$native;elapsed_ms=$watch.ElapsedMilliseconds;helper_pass_promoted=$false;new_send_count=0;cad_calls=0}
}
function Assert-DimensionRuntimeDataV5([string]$Run,$Release) {
 if($Release.data_receipt_path){
  if((Get-FileHash $Release.data_receipt_path).Hash-cne$Release.data_receipt_sha256){throw 'DIM_RUNTIME_DATA_RECEIPT_CHANGED'}
  foreach($file in @(Get-Content $Release.data_receipt_path -Raw|ConvertFrom-Json)){
   if(-not([IO.Path]::GetFullPath($file.path)).StartsWith($Run+'\reports\',[StringComparison]::OrdinalIgnoreCase)-or(Get-FileHash $file.path).Hash-cne$file.sha256){throw 'DIM_RUNTIME_DATA_CHANGED'}
   if([IO.Path]::GetExtension($file.path)-ieq'.lsp'){$dataText=[IO.File]::ReadAllText($file.path,[Text.Encoding]::ASCII);if($dataText-match'(?i)\((load|command|command-s|vl-|vla-|startapp|shell|eval|read)\b'){throw 'DIM_GENERATED_TASK_NOT_DATA_ONLY'}}
  }
 }
}
function Assert-DimensionAdmissionArtifactsV4([string]$Run) {
 $r=Join-Path $Run 'reports'
 $metrics=@(Import-Csv (Join-Path $r 'reference_metrics.tsv') -Delimiter ([char]9))
 $candidate=[IO.File]::ReadAllText((Join-Path $r 'reference_candidate.txt')).Trim()
 if($candidate-cnotmatch'^[0-9A-F]+$'-or$metrics.Count-ne1){throw 'DIM_ADMISSION_REFERENCE_SCOPE'}
 $row=$metrics[0]
 if($row.STATUS-cne'PASS'-or$row.HANDLE-cne$candidate-or[int]$row.SEGMENT_COUNT-ne1-or$row.RXCLASS-cne'TDbText'-or[int]$row.CREATED_COUNT-ne1-or$row.DETACHED-cne'True'-or$row.DISPOSED-cne'True'-or$row.DBMOD_BEFORE-cne$row.DBMOD_AFTER-or[string]::IsNullOrWhiteSpace($row.TEXT)){throw 'DIM_ADMISSION_ACTUAL_REFERENCE_METRICS_FAILED'}
 foreach($name in @('HEIGHT_MODEL','HEIGHT_PAPER','SOURCE_SCALE','STYLE_DIMTXT')){
  [double]$value=0
  if(-not[double]::TryParse($row.$name,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value)-or[double]::IsNaN($value)-or[double]::IsInfinity($value)-or$value-le0){throw ('DIM_ADMISSION_REAL_POSITIVE_VALUE:'+ $name)}
 }
 if([math]::Abs([double]$row.HEIGHT_MODEL-[double]$row.HEIGHT_PAPER*[double]$row.SOURCE_SCALE)-gt0.000001-or[math]::Abs([double]$row.HEIGHT_PAPER-[double]$row.STYLE_DIMTXT)-gt0.000001){throw 'DIM_ADMISSION_HEIGHT_STYLE_SCALE_MISMATCH'}
 $empty=@([IO.File]::ReadAllText((Join-Path $r 'admission_empty_summary.tsv'),[Text.Encoding]::GetEncoding(936))|ConvertFrom-Csv -Delimiter ([char]9))
 if($empty.Count-ne1-or$empty[0].STATUS-cne'FAIL'-or$empty[0].DETAIL-cne'EMPTY_TASK_SET'-or[int]$empty[0].TARGET_SEGMENTS-ne0-or[int]$empty[0].SUCCESS_COUNT-ne0-or$empty[0].ADDED_HANDLES-or$empty[0].CLEANUP_DELETED-or$empty[0].CLEAN_SLATE_DELETED){throw 'DIM_ADMISSION_GENERATOR_NOT_EMPTY'}
 foreach($pair in @(@('model_before.tsv','model_admission_after.tsv'),@('grips_before.tsv','grips_admission_after.tsv'))){if((Get-FileHash (Join-Path $r $pair[0])).Hash-cne(Get-FileHash (Join-Path $r $pair[1])).Hash){throw ('DIM_ADMISSION_EXISTING_OBJECTS_CHANGED:'+ $pair[0])}}
 [pscustomobject]@{status='PASS_CODE_ADMISSION_AND_ACTUAL_SINGLE_REFERENCE';handle=$candidate;height_model=$row.HEIGHT_MODEL;segment_count=$row.SEGMENT_COUNT;native_metrics_pass=$true;generator_empty_guard_verified=$true;whole_model_and_grips_exactly_unchanged=$true;business_generation_pass=$false;business_background_acceptance=$false;next='New BUSINESS run on identical admitted code and current owner, no module/script re-admission.'}
}
