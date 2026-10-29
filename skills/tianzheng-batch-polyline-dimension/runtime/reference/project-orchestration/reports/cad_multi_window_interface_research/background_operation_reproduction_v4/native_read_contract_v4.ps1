. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v1/native_read_contract_v1.ps1')
function Assert-CadBackgroundNativeReadScopeV4($Scope,[string]$Root,[string]$RunDirectory){
 if($Scope.schema_version -ne 1 -or $Scope.implementation_version -ne 4 -or $Scope.profile_id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -or $Scope.intent -cne 'ReadVerifiedNativePropertiesAndGrips' -or $Scope.phase -cne 'SINGLE_BACKGROUND_NATIVE_READ' -or $Scope.operation_stage -cne 'LOAD_FIXED_V285_ONLY' -or $Scope.run_id -cne '20261022_native_load_lisp_53'){throw 'NATIVE4_SCOPE'}
 if(($Scope.capability_bounds|ConvertTo-Json -Compress) -cne ((Get-CadBackgroundNativeReadCapsV1)|ConvertTo-Json -Compress)){throw 'NATIVE4_CAPS'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=$Scope.sequence}) $Root
 if($identity.owners.Count -ne 1 -or ($Scope.sequence -join ',') -cne 'A'){throw 'NATIVE4_ONE_A'}
 $priorPath=Join-Path $Root 'runs/20261022_native_load_52/execution_return.json'
 if((Get-FileHash $priorPath).Hash -cne 'E62A6242B643A18A0B7F7DCC975CDC524981E14586D40B6F5B91B70038D1570F'){throw 'NATIVE4_PRIOR_HASH'}
 $prior=Read-CadPreparationScopeV1 $priorPath;$cp=Join-Path $Root $prior.controller_report_path
 if((Get-FileHash $cp).Hash -cne $prior.controller_report_sha256){throw 'NATIVE4_PRIOR_CONTROLLER_HASH'}
 $c=Read-CadPreparationScopeV1 $cp
 if($c.status -cne 'UNKNOWN_OR_FAILED_AFTER_SEND' -or -not$c.worker_receipt.send_call_returned -or $c.worker_receipt.native_evidence.status -cne 'PASS' -or $c.worker_receipt.detail -notmatch 'NATIVE_READ_COMMAND_NOT_REGISTERED' -or $c.worker_receipt.after.dbmod -ne 0 -or $c.worker_receipt.after.model_count -ne 985 -or $c.helper_phase.job_active_after -ne 0 -or -not$c.helper_phase.output_complete -or $c.prompt_helper_phase.active -ne 0 -or -not$c.prompt_helper_phase.output_complete){throw 'NATIVE4_PRIOR_NOT_SETTLED'}
 $oldReg=[IO.File]::ReadAllText((Join-Path $Root 'runs/20261022_native_load_52/reports/module_registration.log')).Trim()
 if($oldReg -cne ($c.worker_receipt.native_evidence.nonce+'|0|0')){throw 'NATIVE4_PRIOR_REG_CHANGED'}
 foreach($f in @('process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$identity.owners[0].$f -cne [string]$c.bound_owner.$f){throw 'NATIVE4_OTHER_OWNER'}}
 $run=Assert-CadPreparationPathV1 $RunDirectory $Root
 if($run -ine (Join-Path $Root ('runs/'+$Scope.run_id)) -or $Scope.timeout_seconds -ne 15 -or $Scope.sample_interval_ms -ne 20 -or $Scope.observation_settle_ms -ne 200){throw 'NATIVE4_RUN_OR_BUDGET'}
 $ops=@($Scope.operations)
 if($ops.Count -ne 1 -or $ops[0].id -cne 'A1' -or $ops[0].owner -cne 'A' -or $ops[0].nonce -cnotmatch '^[a-f0-9]{32}$' -or $ops[0].duration_ms -ne 0 -or $ops[0].signal_path -ine (Join-Path $run 'signals/A1.log')){throw 'NATIVE4_OPERATION'}
 if($Scope.recipe_id -cne 'V285_CXANNOTATIONCONTROLREADV1' -or $Scope.module_path -cne 'reports/cad_annotation_read_interface_research/candidates/CodexAnnotationControlReadV1.dll' -or $Scope.module_sha256 -cne '249C5FF7B349D5F830B6E5EA30C021DB3C715A1668F097A22C5F839417F12C8B' -or (Get-FileHash (Join-Path $Root $Scope.module_path)).Hash -cne $Scope.module_sha256){throw 'NATIVE4_FIXED_MODULE'}
 if($Scope.recipe_success_return -cne 'runs/20261005_annotation_control_read_v285/execution_return.json' -or $Scope.recipe_success_sha256 -cne '12CCB45EFED9B853EBC564668F95340402EA3754D91888905FA7E857B5EBC912' -or (Get-FileHash (Join-Path $Root $Scope.recipe_success_return)).Hash -cne $Scope.recipe_success_sha256){throw 'NATIVE4_RECIPE_PROOF'}
 if($Scope.native_report -ine (Join-Path $run 'reports/annotation_control_read.tsv') -or $Scope.stage_signal_path -ine (Join-Path $run 'signals/native_phase.log') -or $Scope.load_context_path -ine (Join-Path $run 'signals/load_context.log')){throw 'NATIVE4_REPORT_PATH'}
 foreach($p in $Scope.PSObject.Properties){if($p.Name -match '^(command|source$|code$|lisp$|payload|expression|allow_)'){throw 'NATIVE4_ARBITRARY_PAYLOAD'}}
 $v=[pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;owner=$identity.owners[0];operation=$ops[0];timeout_seconds=15}
 Assert-CadSingleBackgroundProtectionV1 $Scope $v $Root
 $v
}
function Assert-CadBackgroundNativeReadScopeV1($Scope,[string]$Root,[string]$RunDirectory){Assert-CadBackgroundNativeReadScopeV4 $Scope $Root $RunDirectory}
function Assert-CadSingleBackgroundScopeV1($Scope,[string]$Root,[string]$RunDirectory){Assert-CadBackgroundNativeReadScopeV4 $Scope $Root $RunDirectory}
function Assert-CadSingleBackgroundDependenciesV1([string]$Root){
 $m=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'candidate_manifest.json')
 if($m.id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -or $m.implementation_version -ne 4){throw 'NATIVE4_MANIFEST'}
 foreach($f in $m.files){if((Get-FileHash (Join-Path $Root $f.path)).Hash -cne $f.sha256){throw ('NATIVE4_DEPENDENCY:'+ $f.path)}}
}
function New-CadLoadStageFileFormV4($Scope,[string]$Stage,[string]$Mode){
 $p=ConvertTo-CadProbeLispStringV1 $Scope.stage_signal_path
 '(progn ((lambda (/ f) (setq f (open '+$p+' "'+$Mode+'")) (if f (progn (write-line "CX_BG_LOAD_V4|'+$Scope.run_id+'|'+$Scope.operations[0].nonce+'|'+$Stage+'" f) (close f))))) (princ))'+"`r"
}
function New-CadBackgroundNativeReadExpressionV4($Scope,$Operation,$Owner){
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
 $symbol='cx_load53_'+$Operation.nonce
 $q=@{DOC=(ConvertTo-CadProbeLispStringV1 $Owner.document_full_path);SIG=(ConvertTo-CadProbeLispStringV1 $Operation.signal_path);REG=(ConvertTo-CadProbeLispStringV1 (Join-Path (Split-Path $Scope.native_report) 'module_registration.log'));CTX=(ConvertTo-CadProbeLispStringV1 $Scope.load_context_path);HWND=[string]$Owner.window_handle;NONCE=$Operation.nonce;RUN=$Scope.run_id;SYM=$symbol}
 # Temporary nonce-scoped LISP function, never a new managed plugin or DB entity.
 # ACK and COMPLETE keep the original raw signal/parser ABI and bracket NETLOAD.
 $template=@'
(progn (setq @SYM@ '(lambda (stage / app doc hwnd fullname stream stamp)
 (vl-load-com) (setq app (vlax-get-acad-object) doc (vla-get-ActiveDocument app)
 hwnd (rem (+ (vla-get-HWND app) 4294967296.0) 4294967296.0) fullname (vla-get-FullName doc))
 (if (and (= hwnd @HWND@) (= (strcase fullname) (strcase @DOC@)))
 (progn
 (setq stream (open @CTX@ (if (= stage "ACK") "w" "a")))
 (if stream (progn (write-line (strcat "@NONCE@|" stage "|" (itoa (getvar "FILEDIA")) "|" (itoa (getvar "SECURELOAD"))) stream) (close stream)))
 (setq stream (open @REG@ (if (= stage "ACK") "w" "a")))
 (if stream (progn (if (= stage "ACK")
 (princ (strcat "@NONCE@|" (if (getcname "CXANNOTATIONCONTROLREADV1") "1" "0") "|") stream)
 (write-line (if (getcname "CXANNOTATIONCONTROLREADV1") "1" "0") stream)) (close stream)))
 (setq stamp (rem (+ (getvar "MILLISECS") 4294967296.0) 4294967296.0) stream (open @SIG@ "a"))
 (if stream (progn
 (write-line (strcat "CX_CAD_SIGNAL_V1|CAD_COMMAND_" stage "|" (rtos stamp 2 0)) stream)
 (write-line (strcat "CX_MULTI_OWNER_PROBE_V1|@NONCE@|@RUN@|A1|A|" (rtos hwnd 2 0) "|" stage "|" (rtos stamp 2 0) "|" (itoa (getvar "DBMOD")) "|" (itoa (vla-get-Count (vla-get-ModelSpace doc)))) stream)
 (close stream)))) (princ)))) (princ))
'@
 foreach($key in $q.Keys){$template=$template.Replace('@'+$key+'@',[string]$q[$key])}
 $template=$template.Replace("`r",'').Replace("`n",' ')+"`r"
 $load='(progn (command "_.NETLOAD" '+(ConvertTo-CadProbeLispStringV1 (Join-Path $root $Scope.module_path))+') (princ))'+"`r"
 $forms=@((New-CadLoadStageFileFormV4 $Scope 'LISP_ENTER_UNBOUND' 'w'),$template,('(apply '+$symbol+' (list "ACK"))'+"`r"),$load,(New-CadLoadStageFileFormV4 $Scope 'LOAD_FORM_RETURN_UNBOUND' 'a'),('(apply '+$symbol+' (list "COMPLETE"))'+"`r"),('(progn (setq '+$symbol+' nil) (princ))'+"`r"))
 foreach($form in $forms){if($form.Length -gt 2048){throw 'NATIVE4_PER_FORM_ENGINEERING_CAP_NOT_CAD_SPEC'}}
 $source=$forms -join ''
 if($source.Length -gt 6144 -or $source -match '@[A-Z]+@'){throw 'NATIVE4_TOTAL_OR_UNBOUND'}
 $source
}
function Read-CadModuleLoadStagesV4($Scope){
 if(-not(Test-Path $Scope.stage_signal_path)){return [pscustomobject]@{complete=$false;stages=@();native_identity_proven=$false}}
 $lines=@(Get-Content $Scope.stage_signal_path)
 if($lines.Count -gt 2){throw 'NATIVE4_STAGE_DUPLICATE'}
 $expected=@('LISP_ENTER_UNBOUND','LOAD_FORM_RETURN_UNBOUND')
 for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -cne ('CX_BG_LOAD_V4|'+$Scope.run_id+'|'+$Scope.operations[0].nonce+'|'+$expected[$i])){throw 'NATIVE4_STAGE_IDENTITY_OR_ORDER'}}
 [pscustomobject]@{complete=($lines.Count -eq 2);stages=@($expected|Select-Object -First $lines.Count);native_identity_proven=$false;meaning='file_stage_only__native_signal_and_registration_separately_required'}
}
function Get-CadSingleBackgroundVerdictV1($Worker,[bool]$HelperComplete,[bool]$TargetObserved,[int]$Samples){
 if(-not$HelperComplete){return 'UNKNOWN_HELPER_EFFECT_NOT_SETTLED'}
 if($null -eq $Worker){return 'UNKNOWN_MISSING_WORKER_RECEIPT'}
 if(-not$Worker.send_boundary_entered){return 'BLOCKED_BEFORE_SEND'}
 if($Worker.status -cne 'PASS_FIXED_MODULE_REGISTERED_READ_PENDING'){return 'UNKNOWN_OR_FAILED_AFTER_SEND'}
 if($TargetObserved){return 'MODULE_REGISTERED__BACKGROUND_NOT_MET__BUSINESS_PENDING'}
 if($Samples -lt 2){return 'MODULE_REGISTERED__BACKGROUND_UNVERIFIED__BUSINESS_PENDING'}
 'PASS_FIXED_MODULE_REGISTERED_SAMPLED__BUSINESS_PENDING'
}
function Read-CadModuleLoadContextV4($Scope){
 if(-not(Test-Path $Scope.load_context_path)){return [pscustomobject]@{complete=$false;settings_unchanged=$false}}
 $lines=@(Get-Content $Scope.load_context_path);if($lines.Count -ne 2){throw 'NATIVE4_CONTEXT_COUNT'}
 $rows=@()
 for($i=0;$i -lt 2;$i++){
  $p=$lines[$i].Split('|');$stage=@('ACK','COMPLETE')[$i]
  if($p.Count -ne 4 -or $p[0] -cne $Scope.operations[0].nonce -or $p[1] -cne $stage -or $p[2] -cnotmatch '^[01]$' -or $p[3] -cnotmatch '^[012]$'){throw 'NATIVE4_CONTEXT_IDENTITY'}
  $rows+=,[pscustomobject]@{stage=$stage;filedia=[int]$p[2];secureload=[int]$p[3]}
 }
 if($rows[0].filedia -ne $rows[1].filedia -or $rows[0].secureload -ne $rows[1].secureload){throw 'NATIVE4_SETTINGS_CHANGED'}
 [pscustomobject]@{complete=$true;settings_unchanged=$true;before=$rows[0];after=$rows[1];sha256=(Get-FileHash $Scope.load_context_path).Hash}
}
