. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/single_background_input_v1/background_contract_v1.ps1')
$script:BackgroundBaseScopeV1=${function:Assert-CadSingleBackgroundScopeV1}

function Get-CadBackgroundNativeReadCapsV1 {
    $caps=Get-CadSingleBackgroundCapsV1
    $caps.fixed_read_probe_only=$false
    $caps.plugin_load_allowed=$true
    $caps|Add-Member fixed_recipe 'V285_CXANNOTATIONCONTROLREADV1'
    $caps|Add-Member plugin_load_max_count 1
    $caps|Add-Member business_read_max_count 1
    $caps|Add-Member helper_max_count 2
    $caps|Add-Member exact_module_always_load_max_count 1
    $caps|Add-Member global_security_setting_changes_allowed $false
    $caps
}

function Assert-CadBackgroundNativeReadScopeV1($Scope,[string]$Root,[string]$RunDirectory) {
    if($Scope.profile_id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -or $Scope.intent -cne 'ReadVerifiedNativePropertiesAndGrips' -or $Scope.phase -cne 'SINGLE_BACKGROUND_NATIVE_READ'){throw 'NATIVE_READ_SCOPE_IDENTITY'}
    $caps=Get-CadBackgroundNativeReadCapsV1
    if(@($Scope.capability_bounds.PSObject.Properties).Count -ne @($caps.PSObject.Properties).Count){throw 'NATIVE_READ_CAPABILITY_COUNT'}
    foreach($item in $caps.PSObject.Properties){if(($Scope.capability_bounds.($item.Name)|ConvertTo-Json -Compress) -cne ($item.Value|ConvertTo-Json -Compress)){throw ('NATIVE_READ_CAPABILITY:'+ $item.Name)}}
    $projection=$Scope|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    $projection.profile_id='CAD-SINGLE-BACKGROUND-INPUT-V1';$projection.intent='ExecuteSingleBackgroundReadProbe';$projection.phase='SINGLE_BACKGROUND_READ_ONLY';$projection.capability_bounds=Get-CadSingleBackgroundCapsV1
    $v=& $script:BackgroundBaseScopeV1 $projection $Root $RunDirectory
    if($Scope.recipe_id -cne 'V285_CXANNOTATIONCONTROLREADV1' -or $Scope.module_path -cne 'reports/cad_annotation_read_interface_research/candidates/CodexAnnotationControlReadV1.dll' -or $Scope.module_sha256 -cne '249C5FF7B349D5F830B6E5EA30C021DB3C715A1668F097A22C5F839417F12C8B'){throw 'NATIVE_READ_RECIPE_NOT_FROZEN'}
    if((Get-FileHash (Join-Path $Root $Scope.module_path)).Hash -cne $Scope.module_sha256){throw 'NATIVE_READ_MODULE_CHANGED'}
    if((Assert-CadPreparationPathV1 $Scope.native_report $Root) -ine (Join-Path $v.run 'reports/annotation_control_read.tsv')){throw 'NATIVE_READ_REPORT_PATH'}
    if($Scope.recipe_success_return -cne 'runs/20261005_annotation_control_read_v285/execution_return.json' -or $Scope.recipe_success_sha256 -cne '12CCB45EFED9B853EBC564668F95340402EA3754D91888905FA7E857B5EBC912' -or (Get-FileHash (Join-Path $Root $Scope.recipe_success_return)).Hash -cne $Scope.recipe_success_sha256){throw 'NATIVE_READ_RECIPE_SUCCESS_PROOF'}
    $v
}
function Assert-CadSingleBackgroundScopeV1($Scope,[string]$Root,[string]$RunDirectory) {Assert-CadBackgroundNativeReadScopeV1 $Scope $Root $RunDirectory}

function Assert-CadSingleBackgroundDependenciesV1([string]$Root) {
    $m=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'candidate_manifest.json')
    if($m.id -cne 'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1'){throw 'NATIVE_READ_MANIFEST_IDENTITY'}
    foreach($file in $m.files){$p=Assert-CadPreparationPathV1 (Join-Path $Root $file.path) $Root;if((Get-FileHash $p).Hash -cne $file.sha256){throw ('NATIVE_READ_DEPENDENCY_CHANGED:'+ $file.path)}}
}

function New-CadBackgroundNativeReadExpressionV1($Scope,$Operation,$Owner) {
    $base=New-CadProbeExpressionV2 $Scope $Operation $Owner
    $module=ConvertTo-CadProbeLispStringV1 (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) $Scope.module_path)
    $drawing=ConvertTo-CadProbeLispStringV1 $Owner.document_full_path
    $report=ConvertTo-CadProbeLispStringV1 $Scope.native_report
    $needle='(while (and (< elapsed'
    if(([regex]::Matches($base,[regex]::Escape($needle))).Count -ne 1){throw 'NATIVE_READ_INSERTION_NOT_UNIQUE'}
    # Fixed existing managed reader, with its original ordered arguments. No arbitrary payload.
    $probe=ConvertTo-CadProbeLispStringV1 (Join-Path (Split-Path $Scope.native_report) 'module_registration.log')
    $base=$base.Replace('loops stream emit)','loops stream emit registeredBefore moduleProofStream)')
    $body='(setq registeredBefore (if (getcname "CXANNOTATIONCONTROLREADV1") 1 0)) (command "_.NETLOAD" '+$module+') '+
        '(setq moduleProofStream (open '+$probe+' "w")) (if moduleProofStream (progn (write-line (strcat "'+$Operation.nonce+'|" (itoa registeredBefore) "|" (if (getcname "CXANNOTATIONCONTROLREADV1") "1" "0")) moduleProofStream) (close moduleProofStream))) '+
        '(if (getcname "CXANNOTATIONCONTROLREADV1") (command "CXANNOTATIONCONTROLREADV1" '+$drawing+' '+$report+') (princ "CX_NATIVE_READER_NOT_REGISTERED")) '
    $base.Replace($needle,$body+$needle)
}

function Read-CadNativeReaderRegistrationV1($Scope) {
    $p=Join-Path (Split-Path $Scope.native_report) 'module_registration.log'
    if(-not(Test-Path $p)){return [pscustomobject]@{status='UNKNOWN_NETLOAD_ENTER_OR_RETURN';netload_returned=$null;new_module_registration_count=$null;module_identity='NOT_READ'}}
    $raw=[IO.File]::ReadAllText($p).Trim();$f=$raw.Split('|')
    if($f.Count -ne 3 -or $f[0] -cne $Scope.operations[0].nonce -or $f[1] -cnotin @('0','1') -or $f[2] -cnotin @('0','1')){throw 'NATIVE_READ_REGISTRATION_PROOF'}
    if($f[2] -cne '1'){throw 'NATIVE_READ_COMMAND_NOT_REGISTERED'}
    [pscustomobject]@{status=if($f[1] -ceq '0'){'FIXED_NETLOAD_NEW_COMMAND_REGISTERED'}else{'COMMAND_ALREADY_REGISTERED__IMAGE_IDENTITY_NOT_INDEPENDENTLY_READ'};netload_returned=$true;new_module_registration_count=if($f[1] -ceq '0'){1}else{0};module_path=$Scope.module_path;module_sha256=$Scope.module_sha256;proof_sha256=(Get-FileHash $p).Hash;image_path_independently_read=$false}
}

function Read-CadBackgroundNativeReportV1($Scope,$Validated,[string]$ReportPath=$Scope.native_report) {
    $body=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($ReportPath))
    $lines=@($body -split '\r?\n'|Where-Object {$_ -ne ''})
    $header="ROW_TYPE`tSPACE`tOWNER_HANDLE`tHANDLE`tINSTANCE_PATH`tRXCLASS`tLAYER`tFIELD`tVALUE`tSTATUS`tUNITS`tDETAIL"
    if($lines.Count -lt 3 -or $lines[0] -cne $header){throw 'NATIVE_READ_REPORT_HEADER'}
    $rows=@(foreach($line in $lines|Select-Object -Skip 1){
        $f=$line.Split([char]9);if($f.Count -ne 12){throw 'NATIVE_READ_REPORT_WIDTH'}
        [pscustomobject]@{kind=$f[0];type=$f[5];field=$f[7];value=$f[8];status=$f[9]}
    })
    foreach($pair in @(@('document',$Validated.owner.document_full_path),@('report_run',$Validated.run))){
        $matches=@($rows|Where-Object {$_.kind -ceq 'META' -and $_.field -ceq $pair[0]})
        if($matches.Count -ne 1 -or $matches[0].status -cne 'READ' -or $matches[0].value -ine $pair[1]){throw ('NATIVE_READ_REPORT_META:'+ $pair[0])}
    }
    $summaries=@($rows|Where-Object {$_.kind -ceq 'SUMMARY' -and $_.field -ceq 'read_summary'})
    if($summaries.Count -ne 1 -or $summaries[0].status -cne 'READ_ONLY_DIAGNOSTICS_MATCH'){throw 'NATIVE_READ_REPORT_SUMMARY'}
    $values=@{};foreach($item in $summaries[0].value.Split(';')){$p=$item.Split('=');if($p.Count -ne 2 -or $p[1] -cnotmatch '^[0-9]+$' -or $values.ContainsKey($p[0])){throw 'NATIVE_READ_REPORT_SUMMARY_NUMBER'};$values[$p[0]]=[long]$p[1]}
    foreach($key in @('model_before','model_after','dbmod_before','dbmod_after','native_instances','native_classes','legacy_points','advanced_points','warnings')){if(-not $values.ContainsKey($key)){throw ('NATIVE_READ_REPORT_MISSING:'+ $key)}}
    if($values.model_before -ne $values.model_after -or $values.dbmod_before -ne $values.dbmod_after){throw 'NATIVE_READ_REPORT_DATABASE_DRIFT'}
    $grips=@($rows|Where-Object {$_.kind -ceq 'NATIVE_CONTROL' -and $_.field -cmatch '^legacy_point_[0-9]+$' -and $_.status -ceq 'READ'})
    $properties=@($rows|Where-Object {$_.kind -ceq 'NATIVE_CONTROL' -and $_.field -cin @('Scale','TPScale','Text','TextString','TextHeight','Height','Rotation') -and $_.status -ceq 'READ'})
    if($values.native_instances -le 0 -or $values.legacy_points -le 0 -or $grips.Count -ne $values.legacy_points -or $properties.Count -le 0){throw 'NATIVE_READ_REPORT_NO_REAL_PROPERTIES_OR_GRIPS'}
    [pscustomobject]@{status='PASS_NATIVE_PROPERTIES_GRIPS_REPORT';report_sha256=(Get-FileHash $ReportPath).Hash;summary=$values;legacy_point_rows=$grips.Count;public_property_rows=$properties.Count;types=@($rows|Where-Object kind -CEQ 'TYPE_COUNT'|Select-Object -ExpandProperty type -Unique);full_geometry_unchanged_proven=$false;all_types_supported_proven=$false;control_roles_proven=$false;coordinate_quality_requires_original_adapter=$true}
}

function Assert-CadSingleBackgroundWorkerReceiptV1($Worker,$Scope,[string]$ScopeSha256) {
    if($Worker.run_id -cne $Scope.run_id -or $Worker.profile_id -cne $Scope.profile_id -or $Worker.scope_sha256 -cne $ScopeSha256){throw 'NATIVE_READ_WORKER_IDENTITY'}
    if($Worker.send_boundary_entered -isnot [bool] -or $Worker.send_call_returned -isnot [bool] -or $Worker.command_send_count -ne $(if($Worker.send_boundary_entered){1}else{0}) -or $Worker.plugin_load_attempt_submitted_max -ne $Worker.command_send_count){throw 'NATIVE_READ_WORKER_COUNTS'}
    foreach($field in @('foreground_activation_count','focus_count','cad_launch_save_close_kill_count','retry_count','database_write_count')){if($Worker.$field -ne 0){throw 'NATIVE_READ_FORBIDDEN_EFFECT'}}
}
function Get-CadSingleBackgroundVerdictV1($Worker,[bool]$HelperComplete,[bool]$TargetObserved,[int]$Samples) {
    if(-not $HelperComplete){return 'UNKNOWN_HELPER_EFFECT_NOT_SETTLED'}
    if($null -eq $Worker){return 'UNKNOWN_MISSING_WORKER_RECEIPT'}
    if(-not $Worker.send_boundary_entered){return 'BLOCKED_BEFORE_SEND'}
    if($Worker.status -cne 'PASS_NATIVE_PROPERTIES_GRIPS_REPORT'){return 'UNKNOWN_OR_FAILED_AFTER_SEND'}
    if($TargetObserved){return 'PASS_NATIVE_READ__BACKGROUND_NOT_MET'}
    if($Samples -lt 2){return 'PASS_NATIVE_READ__BACKGROUND_UNVERIFIED'}
    'PASS_BACKGROUND_NATIVE_PROPERTIES_GRIPS_SAMPLED'
}
