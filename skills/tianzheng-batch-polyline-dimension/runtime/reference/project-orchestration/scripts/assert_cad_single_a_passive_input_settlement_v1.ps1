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
$profile=$Draft.single_a_passive_input_settlement
if($Contract.profile_id-cne'CAD-SINGLE-A-PASSIVE-INPUT-SETTLEMENT-V1'-or$profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne$Contract.intent-or$Draft.governance.workflow_id-cne$Contract.profile_id){throw 'BACKGROUND_PROFILE_IDENTITY'}
$manifestPath=ResolveBackgroundPath $profile.manifest_path
$relative=[IO.Path]::GetRelativePath($Root,$manifestPath).Replace('\','/')
if($relative-cnotmatch('^'+[regex]::Escape($Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$')){throw 'BACKGROUND_CANDIDATE_DIRECTORY'}
$version=[long]$Matches[1]
if($profile.manifest_sha256-cne$Contract.manifest_sha256-or$profile.manifest_path-cne$Contract.manifest_path-or$profile.manifest_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash $manifestPath).Hash-cne$profile.manifest_sha256){throw 'BACKGROUND_MANIFEST_HASH'}
$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json -DateKind String
if($manifest.id-cne$Contract.profile_id-or$manifest.source_thread_id-cne$Contract.candidate_source_thread_id-or$manifest.status-cne'SEALED_PRIVATE_CANDIDATE_NEEDS_SHARED_ADMISSION'-or$manifest.scope_field-cne'single_a_passive_input_settlement'-or$manifest.intent-cne$Contract.intent-or$manifest.implementation_version-ne$version-or$manifest.package_version-ne$version){throw 'BACKGROUND_MANIFEST_IDENTITY'}
AssertBackgroundCaps $manifest.capability_bounds $Contract.candidate_capability_bounds
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
foreach($f in @($manifest.files)+@($manifest.validation_dependencies)+@([pscustomobject]@{path=$manifestPath;sha256=$profile.manifest_sha256})){AssertBackgroundBound $f.path $f.sha256}
$controller=ResolveBackgroundPath $manifest.controller
$scopeContract=ResolveBackgroundPath $manifest.scope_contract
foreach($path in @($controller,$scopeContract)){
    if(-not$path.StartsWith((Split-Path $manifestPath)+'\',[StringComparison]::OrdinalIgnoreCase)-or@($manifest.files|Where-Object{(ResolveBackgroundPath $_.path)-ieq$path}).Count-ne1){throw 'BACKGROUND_CODE_NOT_BOUND'}
}
if((ResolveBackgroundPath $Draft.program.controller)-ine$controller){throw 'BACKGROUND_CONTROLLER_MISMATCH'}
$scopePath=ResolveBackgroundPath $profile.scope_path
AssertBackgroundBound $scopePath $profile.scope_sha256
$scope=Get-Content $scopePath -Raw|ConvertFrom-Json -DateKind String
if($scope.schema_version-ne1-or$scope.profile_id-cne$Contract.profile_id-or$scope.intent-cne$Contract.intent-or$scope.phase-cne$Contract.phase-or$scope.run_id-cne$Draft.run_id-or$scope.run_id-cnotmatch'\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z'){throw 'BACKGROUND_SCOPE_IDENTITY'}
AssertBackgroundCaps $scope.capability_bounds $Contract.candidate_capability_bounds
# Exact reviewed manifest pins runtime, validation and external dependencies; no general external path exception.
foreach($f in $manifest.external_dependencies){
    if($f.sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash -LiteralPath $f.path).Hash-cne$f.sha256){throw 'PASSIVE_EXTERNAL_RUNTIME_HASH'}
}
$fields=@('schema_version','candidate_version','profile_id','intent','phase','run_id','owner','protected_files','predecessor_return','predecessor_return_sha256','predecessor_evidence','capability_bounds')
if(@($scope.PSObject.Properties).Count-ne$fields.Count-or@($scope.PSObject.Properties|Where-Object{$_.Name-cnotin$fields}).Count){throw 'PASSIVE_SCOPE_FIELDS'}
if($scope.candidate_version-ne$version){throw 'PASSIVE_SCOPE_VERSION'}
$identity=& {
    param($Entry,$Scope,$Root)
    . $Entry
    Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=@($Scope.owner);sequence=@('A')}) $Root
} (ResolveBackgroundPath $Contract.identity_contract) $scope $Root
if(@($identity.owners).Count-ne1-or$identity.owners[0].id-cne'A'-or[long]$identity.owners[0].window_handle-gt[uint32]::MaxValue){throw 'BACKGROUND_SINGLE_OWNER_ONLY'}
$run=ResolveBackgroundPath ('runs/'+$scope.run_id)
foreach($leaf in @('controller_receipt.json','controller_once_claim.json','passive_worker_receipt.json','passive_stages.jsonl','native_text_rows.json','command_outline.json','execution_return.json')){if(Test-Path -LiteralPath (Join-Path $run $leaf)){throw 'BACKGROUND_RUN_REPLAY'}}
foreach($p in $scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_)'){throw 'BACKGROUND_ARBITRARY_PAYLOAD_OR_RIGHT'}}
foreach($name in @('canonical_open','launch_policy')){if($Draft.$name.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$name.launch_permitted_for_this_handoff){throw 'BACKGROUND_LAUNCH_FORBIDDEN'}}
foreach($name in @('standalone_close_allowed','inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open')){if($Draft.launch_policy.$name-isnot[bool]-or$Draft.launch_policy.$name){throw 'BACKGROUND_LIFECYCLE_FORBIDDEN'}}
if((ResolveBackgroundPath $Draft.reporting.run_directory)-ine$run-or(ResolveBackgroundPath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'BACKGROUND_REPORT_PATH'}
# Extra private checks cannot replace the frozen shared functions or the call parser.
& {param($Path,$Name,$Scope,$Root,$Run) . $Path; & $Name $Scope $Root $Run | Out-Null} $scopeContract ('Assert-CadPassiveInputSettlementScopeV'+$version) $scope $Root $run
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
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;owner_count=1;send_max_count=0;cad_calls=0;live_verified=$false}
