# Reuse the now-verified V4 native boundary/context generator; never reload its DLL.
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v4/native_read_contract_v4.ps1')
function Assert-CadBackgroundNativeReadScopeV7($Scope,[string]$Root,[string]$RunDirectory){
 if($Scope.schema_version -ne 1 -or $Scope.implementation_version -ne 7 -or $Scope.profile_id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -or $Scope.intent -cne 'ReadVerifiedNativePropertiesAndGrips' -or $Scope.phase -cne 'SINGLE_BACKGROUND_NATIVE_READ' -or $Scope.operation_stage -cne 'READ_FIXED_V285_ONLY' -or $Scope.run_id -cne '20261023_rich_fixture_native_read_59'){throw 'NATIVE5_SCOPE'}
 if(($Scope.capability_bounds|ConvertTo-Json -Compress) -cne ((Get-CadBackgroundNativeReadCapsV1)|ConvertTo-Json -Compress)){throw 'NATIVE5_CAPS'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=$Scope.sequence}) $Root
 if($identity.owners.Count -ne 1 -or ($Scope.sequence -join ',') -cne 'A'){throw 'NATIVE5_ONE_A'}
 $priorPath=Join-Path $Root 'runs/20261023_rich_fixture_native_load_58/execution_return.json'
 if((Get-FileHash $priorPath).Hash -cne '2AC204BE7767A891DEDFB9051E63E9340DF71696620EDD86D5B1B9C42498FF92'){throw 'NATIVE5_PRIOR_HASH'}
 $prior=Read-CadPreparationScopeV1 $priorPath;$cp=Join-Path $Root $prior.controller_report_path
 if((Get-FileHash $cp).Hash -cne $prior.controller_report_sha256){throw 'NATIVE5_CONTROLLER_HASH'}
 $c=Read-CadPreparationScopeV1 $cp
 if($c.status -cne 'PASS_FIXED_MODULE_REGISTERED_SAMPLED__BUSINESS_PENDING' -or $c.worker_receipt.status -cne 'PASS_FIXED_MODULE_REGISTERED_READ_PENDING' -or $c.worker_receipt.module_registration.new_module_registration_count -ne 1 -or $c.helper_phase.job_active_after -ne 0 -or -not$c.helper_phase.output_complete -or $c.prompt_helper_phase.active -ne 0 -or -not$c.prompt_helper_phase.output_complete){throw 'NATIVE5_PRIOR_NOT_ACCEPTED'}
 $regPath=Join-Path $Root 'runs/20261023_rich_fixture_native_load_58/reports/module_registration.log'
 if((Get-FileHash $regPath).Hash -cne $c.worker_receipt.module_registration.proof_sha256 -or [IO.File]::ReadAllText($regPath).Trim() -cne ($c.worker_receipt.native_evidence.nonce+'|0|1')){throw 'NATIVE5_PRIOR_REGISTRATION'}
 foreach($f in @('process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$identity.owners[0].$f -cne [string]$c.bound_owner.$f){throw 'NATIVE5_OTHER_OWNER'}}
 $run=Assert-CadPreparationPathV1 $RunDirectory $Root
 if($run -ine (Join-Path $Root ('runs/'+$Scope.run_id)) -or $Scope.timeout_seconds -ne 15 -or $Scope.sample_interval_ms -ne 20 -or $Scope.observation_settle_ms -ne 200){throw 'NATIVE5_RUN_OR_BUDGET'}
 $ops=@($Scope.operations)
 if($ops.Count -ne 1 -or $ops[0].id -cne 'A1' -or $ops[0].owner -cne 'A' -or $ops[0].nonce -cnotmatch '^[a-f0-9]{32}$' -or $ops[0].duration_ms -ne 0 -or $ops[0].signal_path -ine (Join-Path $run 'signals/A1.log')){throw 'NATIVE5_OPERATION'}
 if($Scope.recipe_id -cne 'V285_CXANNOTATIONCONTROLREADV1' -or $Scope.module_path -cne 'reports/cad_annotation_read_interface_research/candidates/CodexAnnotationControlReadV1.dll' -or $Scope.module_sha256 -cne '249C5FF7B349D5F830B6E5EA30C021DB3C715A1668F097A22C5F839417F12C8B' -or (Get-FileHash (Join-Path $Root $Scope.module_path)).Hash -cne $Scope.module_sha256){throw 'NATIVE5_FIXED_MODULE'}
 if($Scope.recipe_success_return -cne 'runs/20261005_annotation_control_read_v285/execution_return.json' -or $Scope.recipe_success_sha256 -cne '12CCB45EFED9B853EBC564668F95340402EA3754D91888905FA7E857B5EBC912' -or (Get-FileHash (Join-Path $Root $Scope.recipe_success_return)).Hash -cne $Scope.recipe_success_sha256){throw 'NATIVE5_RECIPE_PROOF'}
 if($Scope.native_report -ine (Join-Path $run 'reports/annotation_control_read.tsv') -or $Scope.stage_signal_path -ine (Join-Path $run 'signals/native_phase.log') -or $Scope.load_context_path -ine (Join-Path $run 'signals/read_context.log')){throw 'NATIVE5_REPORT_PATH'}
 foreach($p in $Scope.PSObject.Properties){if($p.Name -match '^(command|source$|code$|lisp$|payload|expression|allow_)'){throw 'NATIVE5_ARBITRARY_PAYLOAD'}}
 $v=[pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;owner=$identity.owners[0];operation=$ops[0];timeout_seconds=15}
 Assert-CadSingleBackgroundProtectionV1 $Scope $v $Root
 $v
}
function Assert-CadSingleBackgroundScopeV1($Scope,[string]$Root,[string]$RunDirectory){Assert-CadBackgroundNativeReadScopeV7 $Scope $Root $RunDirectory}
function Assert-CadSingleBackgroundDependenciesV1([string]$Root){
 $m=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'candidate_manifest.json')
 if($m.id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -or $m.implementation_version -ne 7){throw 'NATIVE5_MANIFEST'}
 foreach($f in $m.files){if((Get-FileHash (Join-Path $Root $f.path)).Hash -cne $f.sha256){throw ('NATIVE5_DEPENDENCY:'+ $f.path)}}
}
function New-CadBackgroundNativeReadExpressionV5($Scope,$Operation,$Owner){
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
 $source=New-CadBackgroundNativeReadExpressionV4 $Scope $Operation $Owner
 $load='(progn (command "_.NETLOAD" '+(ConvertTo-CadProbeLispStringV1 (Join-Path $root $Scope.module_path))+') (princ))'+"`r"
 if(([regex]::Matches($source,[regex]::Escape($load))).Count -ne 1){throw 'NATIVE5_LOAD_REMOVAL_NOT_UNIQUE'}
 $ready=(New-CadLoadStageFileFormV4 $Scope 'READER_REGISTERED_CALL_READY' 'a').TrimEnd("`r")
 $command='(command "CXANNOTATIONCONTROLREADV1" '+(ConvertTo-CadProbeLispStringV1 ([IO.Path]::GetFullPath($Owner.document_full_path).Replace('\','/')))+' '+(ConvertTo-CadProbeLispStringV1 ([IO.Path]::GetFullPath($Scope.native_report).Replace('\','/')))+')'
 $read='(progn (if (getcname "CXANNOTATIONCONTROLREADV1") (progn '+$ready+' '+$command+') (princ "CX_READER_NOT_REGISTERED_NO_BUSINESS")) (princ))'+"`r"
 $source=$source.Replace($load,$read).Replace('CX_BG_LOAD_V4','CX_BG_READ_V5').Replace('LOAD_FORM_RETURN_UNBOUND','READER_FORM_RETURN_UNBOUND').Replace('cx_load53_','cx_read54_')
 $oldReg=ConvertTo-CadProbeLispStringV1 (Join-Path (Split-Path $Scope.native_report) 'module_registration.log')
 $newReg=ConvertTo-CadProbeLispStringV1 (Join-Path (Split-Path $Scope.native_report) 'reader_availability.log')
 if(([regex]::Matches($source,[regex]::Escape($oldReg))).Count -ne 1){throw 'NATIVE5_AVAILABILITY_PATH_NOT_UNIQUE'}
 $source=$source.Replace($oldReg,$newReg)
 if($source -match '(?i)NETLOAD|\(setvar|\(entmod|\(entmake|vla-Save|vla-Close' -or $source.Length -gt 6144){throw 'NATIVE5_FORBIDDEN_PAYLOAD'}
 foreach($form in @($source -split "`r")){if($form.Length -gt 2048){throw 'NATIVE5_LOCAL_FORM_BUDGET_NOT_CAD_SPEC'}}
 $source
}
function Read-CadReaderStagesV5($Scope){
 if(-not(Test-Path $Scope.stage_signal_path)){return [pscustomobject]@{complete=$false;stages=@();native_identity_proven=$false}}
 $lines=@(Get-Content $Scope.stage_signal_path);$expected=@('LISP_ENTER_UNBOUND','READER_REGISTERED_CALL_READY','READER_FORM_RETURN_UNBOUND')
 if($lines.Count -gt 3){throw 'NATIVE5_STAGE_DUPLICATE'}
 for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -cne ('CX_BG_READ_V5|'+$Scope.run_id+'|'+$Scope.operations[0].nonce+'|'+$expected[$i])){throw 'NATIVE5_STAGE_IDENTITY_OR_ORDER'}}
 [pscustomobject]@{complete=($lines.Count -eq 3);stages=@($expected|Select-Object -First $lines.Count);native_identity_proven=$false}
}
function Read-CadReaderAvailabilityV5($Scope){
 $p=Join-Path (Split-Path $Scope.native_report) 'reader_availability.log'
 if(-not(Test-Path $p)){return [pscustomobject]@{available=$false;module_load_performed=$false}}
 $f=[IO.File]::ReadAllText($p).Trim().Split('|')
 if($f.Count -ne 3 -or $f[0] -cne $Scope.operations[0].nonce -or $f[1] -cne '1' -or $f[2] -cne '1'){throw 'NATIVE5_EXISTING_READER_NOT_AVAILABLE_BOTH_BOUNDARIES'}
 [pscustomobject]@{available=$true;registered_before=$true;registered_after=$true;module_load_performed=$false;module_image_identity_independently_read=$false;proof_sha256=(Get-FileHash $p).Hash}
}
function Get-CadSingleBackgroundVerdictV1($Worker,[bool]$HelperComplete,[bool]$TargetObserved,[int]$Samples){
 if(-not$HelperComplete){return 'UNKNOWN_HELPER_EFFECT_NOT_SETTLED'}
 if($null -eq $Worker){return 'UNKNOWN_MISSING_WORKER_RECEIPT'}
 if(-not$Worker.send_boundary_entered){return 'BLOCKED_BEFORE_SEND'}
 if($Worker.status -cne 'PASS_NATIVE_PROPERTIES_GRIPS_REPORT'){return 'UNKNOWN_OR_FAILED_AFTER_SEND'}
 if($TargetObserved){return 'PASS_NATIVE_READ__BACKGROUND_NOT_MET'}
 if($Samples -lt 2){return 'PASS_NATIVE_READ__BACKGROUND_UNVERIFIED'}
 'PASS_BACKGROUND_NATIVE_PROPERTIES_GRIPS_SAMPLED'
}
function Assert-CadSingleBackgroundWorkerReceiptV1($Worker,$Scope,[string]$ScopeSha256){
 if($Worker.run_id -cne $Scope.run_id -or $Worker.profile_id -cne $Scope.profile_id -or $Worker.scope_sha256 -cne $ScopeSha256){throw 'NATIVE5_WORKER_IDENTITY'}
 if($Worker.send_boundary_entered -isnot [bool] -or $Worker.send_call_returned -isnot [bool] -or $Worker.command_send_count -ne $(if($Worker.send_boundary_entered){1}else{0}) -or $Worker.business_read_attempt_submitted_max -ne $Worker.command_send_count -or $Worker.plugin_load_attempt_submitted_max -ne 0 -or $Worker.plugin_load_count -ne 0){throw 'NATIVE5_WORKER_COUNTS'}
 foreach($f in @('foreground_activation_count','focus_count','cad_launch_save_close_kill_count','retry_count','database_write_count')){if($Worker.$f -ne 0){throw 'NATIVE5_FORBIDDEN_EFFECT'}}
 if($Worker.status -ceq 'PASS_NATIVE_PROPERTIES_GRIPS_REPORT' -and $Worker.business_read_count -ne 1){throw 'NATIVE5_BUSINESS_COUNT'}
}
