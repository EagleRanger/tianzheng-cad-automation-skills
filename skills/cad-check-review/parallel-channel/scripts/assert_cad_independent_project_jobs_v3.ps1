param(
    [Parameter(Mandatory)]$Draft,
    [Parameter(Mandatory)]$Contract,
    [string]$Root=(Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$logicalRoot=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$rootInfo=Get-Item -LiteralPath $logicalRoot
$Root=if($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint){$rootInfo.ResolveLinkTarget($true).FullName}else{$logicalRoot}
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
function Resolve-FixedModuleAdmissionPathV3([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){throw 'FIXED_MODULE_ADMISSION_PATH_EMPTY'}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if($logicalRoot -ine $Root -and $path.StartsWith($logicalRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
        $path=Join-Path $Root $path.Substring($logicalRoot.Length+1)
    }
    if(-not $path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'FIXED_MODULE_ADMISSION_OUTSIDE_PROJECT'}
    for($part=$path;$part.Length -gt $Root.Length;$part=Split-Path -Parent $part){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part).Attributes -band [IO.FileAttributes]::ReparsePoint)){
            throw 'FIXED_MODULE_ADMISSION_NESTED_REPARSE'
        }
    }
    $path
}
$id='CAD-AB-INDEPENDENT-PROJECT-JOBS-V3'
$prefix='reports/cad_multi_window_interface_research/independent_project_jobs_v3/'
# The shared route is the sole current-entry authority. Do not duplicate its
# version filenames here: every entry still has to exist and be hash-bound.
$contractEntry=[string]$Contract.candidate_contract_entry
$controller=[string]$Contract.controller
$launcher=[string]$Contract.canonical_entrypoint
$nativeModule=[string]$Contract.candidate_native_module
$requestPublisher=[string]$Contract.request_submission.publisher
foreach($entry in @($contractEntry,$controller,$launcher,$nativeModule,$requestPublisher)){
    if([string]::IsNullOrWhiteSpace($entry) -or -not $entry.StartsWith($prefix,[StringComparison]::Ordinal)){
        throw 'FIXED_MODULE_ADMISSION_REGISTERED_ENTRY_OUTSIDE_CANDIDATE'
    }
    $null=Resolve-FixedModuleAdmissionPathV3 $entry
}
if($Contract.profile_id -cne $id -or $Contract.status -cne 'admitted_scoped_isolated_validation__live_evidence_required'){
    throw 'FIXED_MODULE_V3_PROFILE_NOT_ADMITTED'
}
$profile=$Draft.independent_project_jobs
if($profile.profile_id -cne $id -or $profile.intent -cne $Contract.intent -or
   $profile.implementation_version -ne 3 -or $Draft.governance.workflow_id -cne $id -or
   $Draft.command_routing.route_id -cne 'shared_annotation_interface_read' -or
   $Draft.issuer.thread_id -cne $Contract.candidate_source_thread_id){throw 'FIXED_MODULE_ADMISSION_AUTHORITY'}
if([string]::IsNullOrWhiteSpace([string]$Contract.validation_mode) -or
   $profile.validation_mode -cne $Contract.validation_mode){throw 'FIXED_MODULE_ADMISSION_VALIDATION_MODE'}
$registry=Get-Content -LiteralPath (Join-Path $Root 'config/cad_native_task_registry.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($Draft.target.thread_id -cne $registry.tasks.execution_run.thread_id -or
   $Draft.schema_version -lt 3 -or $Draft.status -cnotin @('DRAFT','READY')){throw 'FIXED_MODULE_ADMISSION_ACTIVE_DRAFT'}
if($Draft.owner.process_id -ne 0 -or $Draft.owner.window_handle -ne 0 -or
   $null -ne $Draft.owner.process_start_time_utc -or $Draft.owner.launch_permitted -ne $true -or
   $Draft.owner.binding_policy -cne 'NEW_PRIVATE_RESEARCH_HOST_NATIVE_READY_ONLY__ALL_PREEXISTING_EXCLUDED'){
    throw 'FIXED_MODULE_ADMISSION_FRESH_OWNER_DECLARATION'
}
foreach($policy in @($Draft.canonical_open,$Draft.launch_policy)){
    if($null -eq $policy -or $policy.launch_permitted_for_this_handoff -isnot [bool] -or
       -not $policy.launch_permitted_for_this_handoff -or
       $policy.open_result_semantics -cne 'new_native_PID_start_HWND_document_and_module_hash_or_fail__all_preexisting_hosts_excluded'){
        throw 'FIXED_MODULE_ADMISSION_LAUNCH_SEMANTICS'
    }
}
if($Draft.canonical_open.profile_id -cne $id -or
   $Draft.canonical_open.component_id -cne 'CAD-SCOPED-PRIVATE-LAUNCH-V3' -or
   $Draft.canonical_open.entrypoint -cne $launcher -or
   $Draft.canonical_open.transport -cne 'ISOLATED_PRIVATE_DESKTOP_CREATEPROCESS_FIXED_BOOT' -or
   $Draft.launch_policy.invocation -cne 'scoped_private_desktop_fixed_module_profile_only'){
    throw 'FIXED_MODULE_ADMISSION_LAUNCH_ENTRY'
}
foreach($flag in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')){
    $property=$Draft.launch_policy.PSObject.Properties[$flag]
    if($null -eq $property -or $property.Value -isnot [bool] -or $property.Value){throw "FIXED_MODULE_ADMISSION_LAUNCH_POLICY:$flag"}
}
$run=Resolve-FixedModuleAdmissionPathV3 ('runs/'+$Draft.run_id)
if(Test-Path -LiteralPath (Join-Path $run 'execution_return.json')){throw 'FIXED_MODULE_ADMISSION_TERMINAL_RUN'}
$bindings=@{}
foreach($property in $Draft.program.PSObject.Properties){
    if(-not $property.Name.EndsWith('_sha256')){continue}
    $name=$property.Name.Substring(0,$property.Name.Length-7)
    $pair=$Draft.program.PSObject.Properties[$name]
    if($null -eq $pair){throw 'FIXED_MODULE_ADMISSION_UNPAIRED_HASH'}
    $path=Resolve-FixedModuleAdmissionPathV3 ([string]$pair.Value)
    if([string]$property.Value -cnotmatch '^[A-F0-9]{64}$' -or
       (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $property.Value){throw "FIXED_MODULE_ADMISSION_HASH:$name"}
    if($bindings.ContainsKey($path) -and $bindings[$path] -cne $property.Value){throw 'FIXED_MODULE_ADMISSION_HASH_CONFLICT'}
    $bindings[$path]=[string]$property.Value
}
$scopePath=Resolve-FixedModuleAdmissionPathV3 $profile.scope_path
$manifestPath=Resolve-FixedModuleAdmissionPathV3 $profile.manifest_path
if($scopePath -ine (Join-Path $run 'scope.json') -or $manifestPath -ine (Join-Path $run 'manifest.json') -or
   $bindings[$scopePath] -cne $profile.scope_sha256 -or $bindings[$manifestPath] -cne $profile.manifest_sha256){throw 'FIXED_MODULE_ADMISSION_SCOPE_MANIFEST'}
$scope=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if($scope.profile_id -cne $id -or $scope.run_id -cne $Draft.run_id -or $scope.implementation_version -ne 3 -or
   $scope.intent -cne $Contract.intent -or $scope.phase -cne $Contract.phase -or $manifest.profile_id -cne $id){throw 'FIXED_MODULE_ADMISSION_SCOPE_IDENTITY'}
if($scope.validation_mode -cne $Contract.validation_mode){throw 'FIXED_MODULE_ADMISSION_SCOPE_MODE'}
if(($scope.capability_bounds|ConvertTo-Json -Depth 10 -Compress) -cne ($Contract.candidate_capability_bounds|ConvertTo-Json -Depth 10 -Compress)){
    throw 'FIXED_MODULE_ADMISSION_CAPS'
}
$closure=@{}
foreach($file in $manifest.files){
    $path=Resolve-FixedModuleAdmissionPathV3 $file.path
    if($closure.ContainsKey($path)){throw 'FIXED_MODULE_ADMISSION_DUPLICATE_DEPENDENCY'}
    if($bindings[$path] -cne $file.sha256){throw 'FIXED_MODULE_ADMISSION_UNBOUND_DEPENDENCY'}
    $closure[$path]=$file.sha256
}
foreach($entry in @($contractEntry,$controller,$launcher,$nativeModule,$requestPublisher)){
    if(-not $closure.ContainsKey((Resolve-FixedModuleAdmissionPathV3 $entry))){throw "FIXED_MODULE_ADMISSION_REQUIRED_CODE:$entry"}
}
$admissionPath=Join-Path $Root 'scripts/assert_cad_independent_project_jobs_v3.ps1'
if(-not $closure.ContainsKey($admissionPath) -or $closure[$admissionPath] -cne (Get-FileHash -LiteralPath $PSCommandPath).Hash){throw 'FIXED_MODULE_ADMISSION_VALIDATOR_UNBOUND'}
if($Draft.program.controller -cne $controller -or
   $Contract.candidate_contract_abi -cne 'Assert-CadIndependentProjectScopeV3($Scope,$Root)' -or
   $Contract.candidate_manifest_abi -cne 'Assert-CadIndependentProjectManifestV3($Manifest,$Root)' -or
   $Draft.action.controller_call_max -ne 1){throw 'FIXED_MODULE_ADMISSION_ENTRY_ABI'}
# Validate the actual envelope command shape, including argument identity. The
# envelope supplies '&'; a second operator, alias, expansion or statement is not
# another spelling of the same entrypoint.
$parseTokens=$null
$parseErrors=$null
$entryAst=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count -or $null -ne $entryAst.ParamBlock -or $null -ne $entryAst.BeginBlock -or
   $null -ne $entryAst.ProcessBlock -or $null -ne $entryAst.DynamicParamBlock -or
   $entryAst.UsingStatements.Count -ne 0 -or $null -eq $entryAst.EndBlock -or
   ($null -ne $entryAst.EndBlock.Traps -and $entryAst.EndBlock.Traps.Count -ne 0) -or
   $entryAst.EndBlock.Statements.Count -ne 1){throw 'FIXED_MODULE_ADMISSION_CONTROLLER_TEMPLATE'}
$pipeline=$entryAst.EndBlock.Statements[0]
if($pipeline -isnot [Management.Automation.Language.PipelineAst] -or $pipeline.PipelineElements.Count -ne 1){throw 'FIXED_MODULE_ADMISSION_CONTROLLER_TEMPLATE'}
$command=$pipeline.PipelineElements[0]
if($command -isnot [Management.Automation.Language.CommandAst] -or $command.CommandElements.Count -ne 3 -or
   $command.Redirections.Count -ne 0 -or $command.InvocationOperator -ne [Management.Automation.Language.TokenKind]::Unknown){throw 'FIXED_MODULE_ADMISSION_CONTROLLER_TEMPLATE'}
$elements=$command.CommandElements
if($elements[0] -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $elements[0].Value -cne $controller -or
   $elements[1] -isnot [Management.Automation.Language.CommandParameterAst] -or $elements[1].ParameterName -ine 'ReadyHandoffPath' -or $null -ne $elements[1].Argument -or
   $elements[2] -isnot [Management.Automation.Language.StringConstantExpressionAst]){throw 'FIXED_MODULE_ADMISSION_CONTROLLER_TEMPLATE'}
if((Resolve-FixedModuleAdmissionPathV3 $elements[2].Value) -ine (Join-Path $Root 'config/current_execution_handoff.json')){throw 'FIXED_MODULE_ADMISSION_HANDOFF_ARGUMENT'}
$caps=$Contract.candidate_capability_bounds
if($caps.known_startup_tip_close_per_owner_max_count -ne 1 -or
   $caps.known_startup_tip_close_max_count -ne 2){throw 'FIXED_MODULE_ADMISSION_STARTUP_TIP_BOUND'}
$actionBounds=@{
    send_max_count=$caps.external_com_business_send_max_count
    native_task_max_count=$caps.native_task_max_count
    plugin_load_max=$caps.fixed_plugin_load_max_count
    save_copy_max=$caps.save_copy_max_count
    startup_tip_close_max=$caps.known_startup_tip_close_max_count
    foreground_input_max=0
}
foreach($field in $actionBounds.Keys){
    $value=$Draft.action.PSObject.Properties[$field]
    if($null -eq $value -or $value.Value -isnot [ValueType] -or $value.Value -is [bool] -or
       $value.Value -ne $actionBounds[$field]){throw "FIXED_MODULE_ADMISSION_ACTION_BOUND:$field"}
}
if($Draft.acceptance.retry_count -ne 0 -or $Draft.acceptance.aesthetic_gate){throw 'FIXED_MODULE_ADMISSION_ACCEPTANCE_SCOPE'}
& {
    param($Scope,$Manifest,$Root,$Entry)
    . $Entry
    $null=Assert-CadIndependentProjectScopeV3 $Scope $Root
    $null=Assert-CadIndependentProjectManifestV3 $Manifest $Root
} $scope $manifest $Root (Join-Path $Root $Contract.candidate_contract_entry)
[pscustomobject]@{status='PASS';profile_id=$id;CAD_calls=0;live_verified=$false}
