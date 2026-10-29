param([Parameter(Mandatory=$true)][string]$DraftPath,[switch]$PassThru)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$draftFull=[IO.Path]::GetFullPath($DraftPath)
$draft=Get-Content -LiteralPath $draftFull -Raw -Encoding UTF8|ConvertFrom-Json
$index=Get-Content -LiteralPath (Join-Path $root 'config/project_execution_index.json') -Raw -Encoding UTF8|ConvertFrom-Json
$registry=Get-Content -LiteralPath (Join-Path $root ([string]$index.component_registry)) -Raw -Encoding UTF8|ConvertFrom-Json
$admission=$draft.reasoning.reuse_admission
if($null-eq$admission){throw 'READY_REUSE_ADMISSION_MISSING'}
$mode=[string]$admission.mode
if($mode-notin@('REUSE_ACTIVE_COMPONENT','EXTEND_ACTIVE_COMPONENT','NEW_AFTER_RECALL_GAP')){throw 'READY_REUSE_MODE_INVALID'}
$requiredRecall=@([string]$index.component_registry,[string]$index.command_registry,[string]$index.workflow_registry,[string]$index.rejected_legacy_entrypoints)
foreach($source in $requiredRecall){if($source-notin@($admission.recalled_authorities)){throw ('READY_REUSE_RECALL_SOURCE_MISSING:'+$source)}}
$activeIds=@($registry.component_selection_policy.active_reusable_component_ids)
$componentIds=@($admission.reused_component_ids)
if($mode-ne'NEW_AFTER_RECALL_GAP'){
  if($componentIds.Count-lt1){throw 'READY_REUSE_COMPONENT_IDS_EMPTY'}
  foreach($id in $componentIds){
    $rows=@($registry.components|Where-Object{[string]$_.id-ceq[string]$id})
    if($rows.Count-ne1-or[string]$id-notin$activeIds){throw ('READY_REUSE_COMPONENT_NOT_ACTIVE:'+$id)}
    if([string]$rows[0].status-in@('planned','blocked','rejected','superseded','validation_failed')){throw ('READY_REUSE_COMPONENT_NOT_CALLABLE:'+$id)}
  }
}
else{
  if(-not[string]::IsNullOrWhiteSpace([string]$admission.why_no_active_component_applies)-and$componentIds.Count-eq0){}else{throw 'READY_REUSE_NEW_CAPABILITY_GAP_INVALID'}
}
$interface=$admission.interface_contract
if($null-eq$interface-or[string]::IsNullOrWhiteSpace([string]$interface.producer_semantics)-or[string]::IsNullOrWhiteSpace([string]$interface.consumer_semantics)){throw 'READY_REUSE_INTERFACE_SEMANTICS_MISSING'}
$rule=[string]$interface.adapter_rule
if($rule-notin@('PASS_THROUGH_UNCHANGED','VERSIONED_EXPLICIT_ADAPTER','NO_ADAPTER')){throw 'READY_REUSE_ADAPTER_RULE_INVALID'}
if($rule-ceq'PASS_THROUGH_UNCHANGED'){
  if([string]$interface.producer_semantics-cne[string]$interface.consumer_semantics){throw 'READY_REUSE_PASS_THROUGH_SEMANTICS_MISMATCH'}
  if([int]$interface.controller_recalculation_count-ne0){throw 'READY_REUSE_PASS_THROUGH_RECALCULATION_FORBIDDEN'}
}
$regression=$admission.regression
if($null-eq$regression-or[string]::IsNullOrWhiteSpace([string]$regression.path)-or[string]::IsNullOrWhiteSpace([string]$regression.sha256)){throw 'READY_REUSE_REGRESSION_BINDING_MISSING'}
$regressionFull=[IO.Path]::GetFullPath((Join-Path $root ([string]$regression.path)))
if(-not$regressionFull.StartsWith(($root+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $regressionFull -PathType Leaf)){throw 'READY_REUSE_REGRESSION_PATH_INVALID'}
if((Get-FileHash -LiteralPath $regressionFull -Algorithm SHA256).Hash-cne[string]$regression.sha256){throw 'READY_REUSE_REGRESSION_HASH_MISMATCH'}
$bound=$false
foreach($property in @($draft.program.psobject.Properties)){
  if($property.Name-like'*_sha256'){continue}
  if([string]$property.Value-ceq[string]$regression.path){
    $shaProperty=$draft.program.psobject.Properties[$property.Name+'_sha256']
    if($null-ne$shaProperty-and[string]$shaProperty.Value-ceq[string]$regression.sha256){$bound=$true;break}
  }
}
if(-not$bound){throw 'READY_REUSE_REGRESSION_NOT_BOUND_IN_PROGRAM'}
if([string]::IsNullOrWhiteSpace([string]$admission.delta_scope)){throw 'READY_REUSE_DELTA_SCOPE_MISSING'}
$result=[pscustomobject]@{status='PASS';mode=$mode;reused_component_count=$componentIds.Count;interface_adapter_rule=$rule;recall_source_count=$requiredRecall.Count;regression_bound=$true}
if($PassThru){$result}else{$result|ConvertTo-Json -Compress}
