param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
# One assertion is read-only: reuse resolved path checks within it, never across runs.
$script:backgroundResolvedPaths=@{}
function ResolveBackgroundPath([string]$Value){
    if([string]::IsNullOrWhiteSpace($Value)){throw 'BACKGROUND_PATH_EMPTY'}
    if($script:backgroundResolvedPaths.ContainsKey($Value)){return $script:backgroundResolvedPaths[$Value]}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BACKGROUND_PATH_OUTSIDE_PROJECT'}
    for($ancestor=$path;$ancestor.Length-gt$Root.Length;$ancestor=Split-Path -Parent $ancestor){
        if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'BACKGROUND_REPARSE'}
    }
    $script:backgroundResolvedPaths[$Value]=$path
    $path
}
function AssertBackgroundCaps($Actual,$Expected){
    if(@($Actual.PSObject.Properties).Count-ne@($Expected.PSObject.Properties).Count){throw 'BACKGROUND_CAPABILITY_FIELDS'}
    foreach($p in $Expected.PSObject.Properties){
        $a=$Actual.PSObject.Properties[$p.Name]
        if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Depth 8 -Compress)-cne($p.Value|ConvertTo-Json -Depth 8 -Compress)){throw ('BACKGROUND_CAPABILITY:'+ $p.Name)}
    }
}
function AssertBackgroundAcceptanceCounts($Acceptance,$Caps,$OwnerCount,$OwnerIds=$null){
    # Pure cross-check of maxima, not a requirement to load an already registered DLL.
    # Keep independent of the private producer so stale cloned acceptance cannot pass.
    if($null-eq$Caps-or$null-eq$Acceptance){throw 'BACKGROUND_ACCEPTANCE_INPUT_MISSING'}
    if($OwnerCount-isnot[int]-and$OwnerCount-isnot[long]){throw 'BACKGROUND_ACCEPTANCE_OWNER_TYPE'}
    foreach($name in @('owner_max_count','prepare_send_max_per_owner','business_read_send_max_per_owner','plugin_load_max_per_owner','exact_module_always_load_max_per_owner')){
        $p=$Caps.PSObject.Properties[$name]
        if($null-eq$p-or($p.Value-isnot[int]-and$p.Value-isnot[long])-or$p.Value-lt0-or$p.Value-gt[int]::MaxValue){throw ('BACKGROUND_ACCEPTANCE_CAP:'+ $name)}
    }
    if($OwnerCount-lt1-or$OwnerCount-gt$Caps.owner_max_count){throw 'BACKGROUND_ACCEPTANCE_OWNER_COUNT'}
    $expected=[ordered]@{
        send_max_count=[long]$OwnerCount*([long]$Caps.prepare_send_max_per_owner+[long]$Caps.business_read_send_max_per_owner)
        fixed_netload_max=[long]$OwnerCount*[long]$Caps.plugin_load_max_per_owner
        fixed_read_command_max=[long]$OwnerCount*[long]$Caps.business_read_send_max_per_owner
        exact_module_always_load_attempt_max=[long]$OwnerCount*[long]$Caps.exact_module_always_load_max_per_owner
    }
    foreach($name in $expected.Keys){
        $p=$Acceptance.PSObject.Properties[$name]
        if($null-eq$p-or($p.Value-isnot[int]-and$p.Value-isnot[long])-or[long]$p.Value-ne$expected[$name]){throw ('BACKGROUND_ACCEPTANCE_COUNT:'+ $name)}
    }
    # New producers also expose the per-owner breakdown. If present, it must
    # agree with exact scope owners and the same caps; it grants no extra rights.
    if($null-ne$Acceptance.PSObject.Properties['owner_count']-or$null-ne$Acceptance.PSObject.Properties['per_owner_limits']){
        $countProperty=$Acceptance.PSObject.Properties['owner_count'];$rowsProperty=$Acceptance.PSObject.Properties['per_owner_limits']
        if($null-eq$countProperty-or($countProperty.Value-isnot[int]-and$countProperty.Value-isnot[long])-or$countProperty.Value-ne$OwnerCount-or$null-eq$rowsProperty){throw 'BACKGROUND_ACCEPTANCE_OWNER_PROJECTION'}
        if(@($OwnerIds).Count-ne$OwnerCount-or@($OwnerIds|Select-Object -Unique).Count-ne$OwnerCount){throw 'BACKGROUND_ACCEPTANCE_OWNER_IDS'}
        $rows=@($rowsProperty.Value)
        if($rows.Count-ne$OwnerCount){throw 'BACKGROUND_ACCEPTANCE_OWNER_PROJECTION'}
        $perOwner=[ordered]@{preparation_send_max_count=[long]$Caps.prepare_send_max_per_owner;fixed_read_command_max=[long]$Caps.business_read_send_max_per_owner;fixed_netload_max=[long]$Caps.plugin_load_max_per_owner;exact_module_always_load_attempt_max=[long]$Caps.exact_module_always_load_max_per_owner;send_max_count=([long]$Caps.prepare_send_max_per_owner+[long]$Caps.business_read_send_max_per_owner)}
        for($i=0;$i-lt$rows.Count;$i++){
            $id=$rows[$i].PSObject.Properties['owner_id']
            if($null-eq$id-or$id.Value-isnot[string]-or$id.Value-cne$OwnerIds[$i]){throw 'BACKGROUND_ACCEPTANCE_OWNER_IDS'}
            foreach($name in $perOwner.Keys){
                $p=$rows[$i].PSObject.Properties[$name]
                if($null-eq$p-or($p.Value-isnot[int]-and$p.Value-isnot[long])-or[long]$p.Value-ne$perOwner[$name]){throw ('BACKGROUND_ACCEPTANCE_PER_OWNER:'+ $name)}
            }
        }
    }
    [pscustomobject]$expected
}
$profile=$Draft.background_native_read
if($Contract.profile_id-cne'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1'-or$profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne$Contract.intent-or$Draft.governance.workflow_id-cne$Contract.profile_id){throw 'BACKGROUND_PROFILE_IDENTITY'}
$abRead=$null-ne$profile.PSObject.Properties['lookup_intent']
$caps=$Contract.candidate_capability_bounds
$phase=$Contract.phase
if($abRead){
    if($profile.lookup_intent-cne'KnownAHeldApplicationAndBFileDocumentNativeRead'-or$null-eq$Contract.PSObject.Properties['candidate_lookup_variants']){throw 'BACKGROUND_VARIANT_UNKNOWN'}
    $variant=$Contract.candidate_lookup_variants.PSObject.Properties[[string]$profile.lookup_intent]
    if($null-eq$variant-or$variant.Value.implementation_version-ne8){throw 'BACKGROUND_VARIANT_NOT_ADMITTED'}
    $caps=$variant.Value.capability_bounds;$phase=$variant.Value.phase
}
$manifestPath=ResolveBackgroundPath $profile.manifest_path
$relative=[IO.Path]::GetRelativePath($Root,$manifestPath).Replace('\','/')
if($relative-cnotmatch('^'+[regex]::Escape($Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$')){throw 'BACKGROUND_CANDIDATE_DIRECTORY'}
$version=[long]$Matches[1]
if($abRead-and($version-ne8-or$relative-cne($variant.Value.candidate_directory+'/candidate_manifest.json'))){throw 'BACKGROUND_VARIANT_DIRECTORY'}
if($profile.manifest_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash $manifestPath).Hash-cne$profile.manifest_sha256){throw 'BACKGROUND_MANIFEST_HASH'}
$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json -DateKind String
if($manifest.id-cne$Contract.profile_id-or$manifest.source_thread_id-cne$Contract.candidate_source_thread_id-or$manifest.status-cne'SEALED_PRIVATE_VALIDATION_ONLY__SHARED_ADMISSION_REQUIRED'-or$manifest.scope_field-cne'background_native_read'-or$manifest.intent-cne$Contract.intent-or$manifest.implementation_version-ne$version-or$manifest.package_version-ne$version){throw 'BACKGROUND_MANIFEST_IDENTITY'}
if($abRead-and$manifest.lookup_intent-cne$profile.lookup_intent){throw 'BACKGROUND_VARIANT_MANIFEST'}
AssertBackgroundCaps $manifest.capability_bounds $caps
$bindings=@{}
foreach($p in $Draft.program.PSObject.Properties){
    if($p.Name.EndsWith('_sha256')){
        $key=$p.Name.Substring(0,$p.Name.Length-7);$pair=$Draft.program.PSObject.Properties[$key]
        if($null-eq$pair){throw 'BACKGROUND_PROGRAM_PAIR'}
        $path=ResolveBackgroundPath ([string]$pair.Value)
        if($bindings.ContainsKey($path)-and$bindings[$path]-cne$p.Value){throw 'BACKGROUND_PROGRAM_CONFLICT'}
        $bindings[$path]=[string]$p.Value
    }
}
function AssertBackgroundBound([string]$Value,[string]$Hash){
    $path=ResolveBackgroundPath $Value
    if($Hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash $path).Hash-cne$Hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$Hash){throw ('BACKGROUND_BINDING:'+ $Value)}
}
foreach($f in @($manifest.files)+@([pscustomobject]@{path=$manifestPath;sha256=$profile.manifest_sha256})){AssertBackgroundBound $f.path $f.sha256}
if($abRead-and$null-ne$manifest.PSObject.Properties['validation_dependencies']){foreach($f in $manifest.validation_dependencies){AssertBackgroundBound $f.path $f.sha256}}
$controller=ResolveBackgroundPath $manifest.controller
$scopeContract=ResolveBackgroundPath $manifest.scope_contract
foreach($path in @($controller,$scopeContract)){
    if(-not$path.StartsWith((Split-Path $manifestPath)+'\',[StringComparison]::OrdinalIgnoreCase)-or@($manifest.files|Where-Object{(ResolveBackgroundPath $_.path)-ieq$path}).Count-ne1){throw 'BACKGROUND_CODE_NOT_BOUND'}
}
if((ResolveBackgroundPath $Draft.program.controller)-ine$controller){throw 'BACKGROUND_CONTROLLER_MISMATCH'}
$scopePath=ResolveBackgroundPath $profile.scope_path
AssertBackgroundBound $scopePath $profile.scope_sha256
$scope=Get-Content $scopePath -Raw|ConvertFrom-Json -DateKind String
$sequence=if($abRead){'A,B'}else{'A'}
if($scope.schema_version-ne1-or$scope.profile_id-cne$Contract.profile_id-or$scope.intent-cne$Contract.intent-or$scope.phase-cne$phase-or(@($scope.sequence)-join',')-cne$sequence-or$scope.run_id-cne$Draft.run_id-or$scope.run_id-cnotmatch'\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z'){throw 'BACKGROUND_SCOPE_IDENTITY'}
if($abRead-and($scope.implementation_version-ne8-or$scope.lookup_intent-cne$profile.lookup_intent-or$scope.operation_stage-cne'SERIAL_ENSURE_FIXED_READER_THEN_READ_FIXED_V285_AB'-or(@($scope.workflow_steps)-join',')-cne'SERIAL_ENSURE_FIXED_READER,READ_FIXED_V285_AB_ONLY')){throw 'BACKGROUND_VARIANT_STAGES'}
AssertBackgroundCaps $scope.capability_bounds $caps
# Frozen pure identity and expression implementations are independent of private checks.
foreach($f in $Contract.frozen_dependencies){
    AssertBackgroundBound $f.path $f.sha256
    if(@($manifest.files|Where-Object{(ResolveBackgroundPath $_.path)-ieq(ResolveBackgroundPath $f.path)-and$_.sha256-ceq$f.sha256}).Count-ne1){throw 'BACKGROUND_FROZEN_DEPENDENCY'}
}
$identity=& {
    param($Entry,$Scope,$Root)
    . $Entry
    # The frozen identity-only validator names its two-owner projection ABA;
    # this does not dispatch reads or change the actual preparation/read plan.
    $identitySequence=if(@($Scope.owners).Count-eq2){@('A','B','A')}else{@('A')}
    Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=$identitySequence}) $Root
} (ResolveBackgroundPath $Contract.identity_contract) $scope $Root
if((@($identity.owners.id)-join',')-cne$sequence-or@($identity.owners|Where-Object{[long]$_.window_handle-gt[uint32]::MaxValue}).Count){throw 'BACKGROUND_OWNER_PLAN'}
if($abRead){
    $acceptanceProperty=$Draft.PSObject.Properties['acceptance']
    if($null-eq$acceptanceProperty){throw 'BACKGROUND_ACCEPTANCE_INPUT_MISSING'}
    $acceptanceCounts=AssertBackgroundAcceptanceCounts $acceptanceProperty.Value $caps @($identity.owners).Count @($identity.owners.id)
}
$operations=@($scope.operations)
$run=Join-Path $Root ('runs/'+$scope.run_id)
if($abRead){
    $prepare=@($scope.preparation_operations)
    if($operations.Count-ne2-or($operations.owner-join',')-cne'A,B'-or($operations.id-join',')-cne'A1,B1'-or($operations.kind-join',')-cne'READ,READ'-or$prepare.Count-ne2-or($prepare.owner-join',')-cne'A,B'-or($prepare.id-join',')-cne'A9,B9'-or($prepare.kind-join',')-cne'PREPARE,PREPARE'){throw 'BACKGROUND_AB_OPERATIONS'}
    $allOps=@($prepare)+@($operations)
    if(@($allOps.nonce|Select-Object -Unique).Count-ne4){throw 'BACKGROUND_AB_NONCE_REUSE'}
}else{
    if($operations.Count-ne1-or$operations[0].owner-cne'A'-or$operations[0].id-cnotmatch'\AA[1-9][0-9]{0,2}\z'){throw 'BACKGROUND_ONE_OPERATION'}
    $allOps=$operations
}
foreach($op in $allOps){
    if($op.nonce-cnotmatch'\A[a-f0-9]{32}\z'-or$op.duration_ms.GetType()-notin@([int],[long])-or$op.duration_ms-ne0){throw 'BACKGROUND_FIXED_OPERATION'}
    if((ResolveBackgroundPath $op.signal_path)-ine(Join-Path $run ('signals/'+$op.id+'.log'))){throw 'BACKGROUND_SIGNAL_PATH'}
}
if($abRead){
    foreach($prefix in @('prior_AB_return','prior_AB_scope','prior_AB_controller')){AssertBackgroundBound $scope.($prefix+'_path') $scope.($prefix+'_sha256')}
    $prior=Get-Content (ResolveBackgroundPath $scope.prior_AB_return_path) -Raw|ConvertFrom-Json -DateKind String
    $priorController=Get-Content (ResolveBackgroundPath $scope.prior_AB_controller_path) -Raw|ConvertFrom-Json -DateKind String
    $priorScope=Get-Content (ResolveBackgroundPath $scope.prior_AB_scope_path) -Raw|ConvertFrom-Json -DateKind String
    if((ResolveBackgroundPath $scope.prior_AB_return_path)-ine(Join-Path $Root ('runs/'+$prior.run_id+'/execution_return.json'))-or$prior.status-cne'REPORTED'-or$prior.execution_control_released-isnot[bool]-or-not$prior.execution_control_released-or$prior.retry_count-ne0){throw 'BACKGROUND_AB_PRIOR_TERMINAL'}
    if((ResolveBackgroundPath $prior.controller_report_path)-ine(ResolveBackgroundPath $scope.prior_AB_controller_path)-or$prior.controller_report_sha256-cne$scope.prior_AB_controller_sha256-or$priorController.status-cne'PASS_OVERLAPPING_NONDB_PROBE'-or$priorController.scope_sha256-cne$scope.prior_AB_scope_sha256-or$priorController.run_id-cne$prior.run_id-or$priorScope.run_id-cne$prior.run_id){throw 'BACKGROUND_AB_PRIOR_CHAIN'}
    foreach($set in @($priorController.scope_owners,$priorScope.owners)){
        if((@($set.id)-join',')-cne'A,B'){throw 'BACKGROUND_AB_PRIOR_OWNER_SET'}
        for($i=0;$i-lt2;$i++){foreach($field in @('id','process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$set[$i].$field-cne[string]$identity.owners[$i].$field){throw ('BACKGROUND_AB_PRIOR_OWNER:'+ $field)}}}
    }
}
foreach($leaf in @('reports/annotation_control_read.tsv','reports/module_registration.log','prompt_request.json','prompt_watcher_ready.json','prompt_watcher_result.json','prompt_stages.jsonl','foreground_samples.jsonl','controller_receipt.json','controller_once_claim.json','worker_receipt.json','worker_stages.jsonl','execution_return.json','signals')){if(Test-Path -LiteralPath (Join-Path $run $leaf)){throw 'BACKGROUND_RUN_REPLAY'}}
foreach($p in $scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_)'){throw 'BACKGROUND_ARBITRARY_PAYLOAD_OR_RIGHT'}}
foreach($name in @('canonical_open','launch_policy')){if($Draft.$name.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$name.launch_permitted_for_this_handoff){throw 'BACKGROUND_LAUNCH_FORBIDDEN'}}
foreach($name in @('standalone_close_allowed','inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open')){if($Draft.launch_policy.$name-isnot[bool]-or$Draft.launch_policy.$name){throw 'BACKGROUND_LIFECYCLE_FORBIDDEN'}}
if((ResolveBackgroundPath $Draft.reporting.run_directory)-ine$run-or(ResolveBackgroundPath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'BACKGROUND_REPORT_PATH'}
# The registered recipe pins the tested DLL and success proof independently of private checks.
if($scope.recipe_id-cne$Contract.recipe_id-or$scope.module_path-cne$Contract.module_path-or$scope.module_sha256-cne$Contract.module_sha256){throw 'NATIVE_READ_REGISTERED_RECIPE'}
if($scope.recipe_success_return-cne$Contract.recipe_success_return-or$scope.recipe_success_sha256-cne$Contract.recipe_success_sha256){throw 'NATIVE_READ_REGISTERED_EVIDENCE'}
AssertBackgroundBound $scope.module_path $scope.module_sha256
AssertBackgroundBound $scope.recipe_success_return $scope.recipe_success_sha256
if(-not$abRead-and(ResolveBackgroundPath $scope.native_report)-ine(Join-Path $run 'reports/annotation_control_read.tsv')){throw 'NATIVE_READ_REGISTERED_REPORT'}
# Extra private checks cannot replace the frozen shared functions or the call parser.
& {param($Path,$Name,$Scope,$Root,$Run) . $Path; & $Name $Scope $Root $Run | Out-Null} $scopeContract ('Assert-CadBackgroundNativeReadScopeV'+$version) $scope $Root $run
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'BACKGROUND_TEMPLATE_NOT_LITERAL'}
$command=$commands[0]
if((ResolveBackgroundPath $command.GetCommandName())-ine$controller){throw 'BACKGROUND_TEMPLATE_CONTROLLER'}
$argsMap=@{};$elements=$command.CommandElements
for($i=1;$i-lt$elements.Count;$i+=2){
    if($elements[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$elements[$i].Argument-or$i+1-ge$elements.Count){throw 'BACKGROUND_TEMPLATE_PARAMETER'}
    $name=$elements[$i].ParameterName;$value=$elements[$i+1]
    if($argsMap.ContainsKey($name)-or$value-isnot[Management.Automation.Language.ConstantExpressionAst]){throw 'BACKGROUND_TEMPLATE_NONLITERAL_OR_DUPLICATE'}
    $argsMap[$name]=$value.Value
}
if($argsMap.Count-ne4-or@('RunDirectory','ScopePath','ScopeSha256','TimeoutSeconds'|Where-Object{-not$argsMap.ContainsKey($_)}).Count){throw 'BACKGROUND_TEMPLATE_PARAMETERS'}
if((ResolveBackgroundPath $argsMap.RunDirectory)-ine$run-or(ResolveBackgroundPath $argsMap.ScopePath)-ine$scopePath-or$argsMap.ScopeSha256-cne$profile.scope_sha256-or$argsMap.TimeoutSeconds.GetType()-notin@([int],[long])-or$argsMap.TimeoutSeconds-ne15){throw 'BACKGROUND_TEMPLATE_BINDING'}
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;owner_count=@($identity.owners).Count;send_max_count=$(if($abRead){$acceptanceCounts.send_max_count}else{1});cad_calls=0;live_verified=$false}
