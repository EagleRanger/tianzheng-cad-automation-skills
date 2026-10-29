# Pure data policy only. No UIA assemblies, native calls, processes, or CAD.
# Bound to the admitted read-only profile; no control rights are inferred.
function Assert-CadCommandUiaMetadataV1($Node,$Root,[string]$ExpectedParentRuntimeId,[bool]$IsRoot){
 if($Node.process_id-ne$Root.process_id-or[string]::IsNullOrWhiteSpace($Node.runtime_id)){throw 'UIA_NODE_IDENTITY'}
 if($Node.is_password){throw 'UIA_PASSWORD_BOUNDARY'}
 if($IsRoot){
  if($Node.native_window_handle-ne$Root.surface_handle){throw 'UIA_ROOT_NATIVE_HANDLE'}
 }elseif($Node.parent_runtime_id-cne$ExpectedParentRuntimeId){throw 'UIA_PARENT_CHAIN'}
 if($Node.native_window_handle-ne0-and-not$Node.native_identity_verified){throw 'UIA_NATIVE_DESCENDANT_UNVERIFIED'}
 foreach($f in @('name','automation_id','class_name','framework_id','control_type')){
  if(([string]$Node.$f).Length-ge4096){throw ('UIA_METADATA_LIMIT:'+ $f)}
 }
}
function Assert-CadCommandUiaStableV1($Before,$After,$Root,[string]$ExpectedParentRuntimeId,[bool]$IsRoot){
 Assert-CadCommandUiaMetadataV1 $Before $Root $ExpectedParentRuntimeId $IsRoot
 Assert-CadCommandUiaMetadataV1 $After $Root $ExpectedParentRuntimeId $IsRoot
 foreach($f in @('runtime_id','parent_runtime_id','process_id','native_window_handle','class_name','automation_id','framework_id','control_type','is_password','enabled','offscreen')){
  if([string]$Before.$f-cne[string]$After.$f){throw ('UIA_IDENTITY_CHANGED:'+ $f)}
 }
}
function Test-CadCommandUiaEvidenceV1($Root,$Rows,[bool]$TraversalComplete,[bool]$ReadPhaseSettled){
 $accepted=[Collections.Generic.List[object]]::new();$seen=@{};$total=0;$problem=$null;$hints=[Collections.Generic.List[string]]::new()
 try{
  if($Root.process_id-le0-or$Root.surface_handle-le0-or-not$Root.native_chain_fresh_verified){throw 'UIA_FRESH_NATIVE_CHAIN_REQUIRED'}
  if(-not$ReadPhaseSettled){throw 'UIA_HELPER_UNSETTLED'}
  if(@($Rows).Count-gt32){throw 'UIA_NODE_LIMIT'}
  if(@($Rows).Count-eq0){throw 'UIA_EMPTY_RESULT'}
  foreach($r in $Rows){
   $isRoot=($accepted.Count-eq0)
   if($r.depth-lt0-or$r.depth-gt8){throw 'UIA_DEPTH_LIMIT'}
   if($isRoot){if($r.depth-ne0){throw 'UIA_ROOT_DEPTH'};$parent=''}
   else{
    $parent=[string]$r.before.parent_runtime_id
    if(-not$seen.ContainsKey($parent)-or$r.depth-ne($seen[$parent]+1)){throw 'UIA_PARENT_PREFIX'}
   }
   Assert-CadCommandUiaStableV1 $r.before $r.after $Root $parent $isRoot
   if($seen.ContainsKey([string]$r.before.runtime_id)){throw 'UIA_RUNTIME_ID_CYCLE'}
   if(-not$r.read_complete){throw 'UIA_TEXT_INCOMPLETE'}
   foreach($v in @($r.before.name,$r.value_text,$r.document_text)){
    if(([string]$v).Length-ge4096){throw 'UIA_TEXT_LIMIT_OR_TRUNCATION'}
    $total+=([string]$v).Length
    if($total-gt16384){throw 'UIA_TOTAL_TEXT_LIMIT'}
   }
   $seen[[string]$r.before.runtime_id]=[int]$r.depth;$accepted.Add($r)
   if($r.before.enabled-and-not$r.before.offscreen-and$r.before.control_type-ceq'ControlType.Edit'){$hints.Add([string]$r.before.runtime_id)}
  }
  if(-not$TraversalComplete){throw 'UIA_SUBTREE_INCOMPLETE'}
 }catch{$problem=$_.Exception.Message}
 [pscustomobject]@{status=$(if($null-eq$problem){'COMPLETE_SUBTREE_EVIDENCE_ONLY'}else{'INCOMPLETE_OR_REJECTED_EVIDENCE'});error=$problem;accepted_rows=$accepted.Count;total_text_chars=$total;edit_hints=$hints.ToArray();subtree_evidence_complete=($null-eq$problem);whole_cad_modal_verified=$false;native_idle_verified=$false;send_authorized=$false;live_verified=$false}
}
