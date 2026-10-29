# This is the actual future controller's per-worker settlement loop, not a
# second scheduler or receipt format. Callbacks retain the admitted Wait ABI,
# native evidence validation and existing own-Job-only cleanup.
function Invoke-CadNativeReadIndependentSettlementV9 {
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,[Parameter(Mandatory)][scriptblock]$Settle,[Parameter(Mandatory)][scriptblock]$Cleanup,[Parameter(Mandatory)][scriptblock]$ReadReceipt,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][string]$ExpectedScopeSha256)
 $ledger=[Collections.Generic.List[object]]::new();$cleanupCalls=0
 foreach($row in $Rows){
  $success=$false;$errorText=$null;$cleanupError=$null;$data=$null;$observedState='NOT_READ'
  try{
   # Existing WaitWorker must finish its bounded Job wait, original receipt
   # consumer and native/business assertions before returning the receipt.
   $data=&$Settle $row
   if($null-eq$data-or$data.status-cne'PASS'-or$data.run_id-cne$ExpectedRunId-or$data.scope_sha256-cne$ExpectedScopeSha256-or$data.operation_id-cne$row.operation.id-or$data.nonce-cne$row.operation.nonce-or$data.post_call_count-ne1){throw 'NATIVE_SETTLEMENT_VALIDATED_RESULT_REQUIRED'}
   $success=$true;$observedState='VALIDATED_BY_EXISTING_WAITER'
  }catch{$errorText=$_.Exception.ToString()}
  finally{
   # A failed row never skips cleanup or the next already-issued owner.
   $cleanupCalls++
   try{$null=&$Cleanup $row}catch{$cleanupError=$_.Exception.ToString()}
  }
  if(-not$success){
   # Metadata only: a late receipt may show an attempted send, but cannot
   # upgrade a timed-out/native-unvalidated operation to business success.
   try{$observation=&$ReadReceipt $row;$observedState=$observation.state;$data=$observation.data}catch{$observedState='UNREADABLE';$data=$null}
  }
  $reportedSend=$null;$identityKnown=$false
  if($null-ne$data){
   try{
    $identityKnown=($data.run_id-ceq$ExpectedRunId-and$data.scope_sha256-ceq$ExpectedScopeSha256-and$data.operation_id-ceq$row.operation.id-and$data.nonce-ceq$row.operation.nonce)
    if($identityKnown-and$data.post_call_count.GetType()-in@([int],[long])-and$data.post_call_count-in@(0,1)){$reportedSend=[int]$data.post_call_count}
   }catch{$identityKnown=$false;$reportedSend=$null}
  }
  $ledger.Add([pscustomobject][ordered]@{operation_id=$row.operation.id;owner=$row.operation.owner;status=$(if($success){'SETTLED_SUCCESS'}else{'UNKNOWN_OR_FAILED'});business_success=$success;settlement_error=$errorText;receipt_state=$observedState;receipt_identity_verified=$identityKnown;reported_send_count=$reportedSend;send_effect=$(if($null-eq$reportedSend){'UNKNOWN_NEVER_ZERO_ASSUMED'}else{'COUNT_FROM_BOUND_RECEIPT'});cleanup_callback_invoked=$true;cleanup_error=$cleanupError})
 }
 $known=0;$unknown=0;$successCount=0;$cleanupErrors=0
 foreach($item in $ledger){if($null-eq$item.reported_send_count){$unknown++}else{$known+=$item.reported_send_count};if($item.business_success){$successCount++};if($item.cleanup_error){$cleanupErrors++}}
 [pscustomobject][ordered]@{status=$(if($Rows.Count-eq0){'NO_ISSUED_WORKERS'}elseif($successCount-eq$Rows.Count-and$cleanupErrors-eq0){'PASS_ALL_ISSUED_WORKERS_SETTLED'}else{'PARTIAL_OR_UNKNOWN_ISSUED_WORKERS'});operations=$ledger.ToArray();business_success_count=$successCount;unsettled_operation_count=($Rows.Count-$successCount);known_reported_send_count=$known;unknown_send_effect_count=$unknown;total_send_count=$(if($unknown-eq0){$known}else{$null});cleanup_callback_count=$cleanupCalls;cleanup_error_count=$cleanupErrors;unknown_business_is_not_zero=$true;native_stop_not_claimed=$true}
}

function Get-CadNativeReadFinalVerdictV9 {
 param([AllowEmptyCollection()][object[]]$Results,$Settlement,$Overlap,[string]$ProtectionStatus='UNCHANGED',[string]$ControllerError='')
 $reportsComplete=@($Results).Count-eq2
 $settled=($null-ne$Settlement-and$Settlement.operations.Count-eq2-and$Settlement.business_success_count-eq2-and$Settlement.unsettled_operation_count-eq0-and$Settlement.cleanup_error_count-eq0)
 $nativeOverlap=($null-ne$Overlap-and$Overlap.overlap_proven)
 $status=if($ProtectionStatus-cne'UNCHANGED'){'FAILED_PROTECTED_FILE_CHECK'}elseif(-not[string]::IsNullOrEmpty($ControllerError)){'BLOCKED_PARTIAL_OR_UNKNOWN_NATIVE_READ'}elseif(-not$settled){'PARTIAL_AB_NATIVE_READ_SETTLEMENT_OR_CLEANUP_UNRESOLVED'}elseif(-not$reportsComplete){'PARTIAL_AB_NATIVE_READ_NOT_BOTH_PROVEN'}elseif($nativeOverlap){'PASS_AB_NATIVE_PROPERTIES_GRIPS_WITH_MEASURED_OVERLAP'}else{'PASS_AB_NATIVE_PROPERTIES_GRIPS_NO_OVERLAP_PROVEN'}
 $complete=($status-cmatch'^PASS_')
 [pscustomobject][ordered]@{status=$status;validated_native_business_reports_complete=$reportsComplete;settlement_and_cleanup_complete=$settled;business_complete=$complete;native_interval_overlap_proven=$nativeOverlap;concurrency_proven=($complete-and$nativeOverlap);validated_results_retained=@($Results).Count}
}
