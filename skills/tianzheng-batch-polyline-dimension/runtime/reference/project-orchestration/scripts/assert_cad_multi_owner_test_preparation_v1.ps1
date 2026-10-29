param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function PreparationPath([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){throw 'MULTI_OWNER_PREPARATION_PATH_EMPTY'}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'MULTI_OWNER_PREPARATION_PATH_OUTSIDE_PROJECT'}
    $path
}
function PreparationHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function PreparationInteger($Value,[int]$Minimum,[int]$Maximum){
    if($Value-isnot[int]-and$Value-isnot[long]){throw 'MULTI_OWNER_PREPARATION_INTEGER_REQUIRED'}
    if($Value-lt$Minimum-or$Value-gt$Maximum){throw 'MULTI_OWNER_PREPARATION_INTEGER_RANGE'}
}
$aOnly=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-A-ONLY-PREPARATION-V2'
$scopeField=if($aOnly){'multi_owner_a_only_preparation'}else{'multi_owner_test_preparation'}
$profile=$Draft.$scopeField
$expectedProfile=if($aOnly){'CAD-MULTI-OWNER-A-ONLY-PREPARATION-V2'}else{'CAD-MULTI-OWNER-TEST-PREPARATION-V1'}
if([string]$profile.profile_id-cne$expectedProfile-or[string]$Contract.profile_id-cne[string]$profile.profile_id){throw 'MULTI_OWNER_PREPARATION_PROFILE_UNKNOWN'}
$mode=if($null-ne$profile.PSObject.Properties['mode']){[string]$profile.mode}else{'FRESH'}
$resumeExistingA=$aOnly-and$mode-ceq'RESUME_EXISTING_A'
if($aOnly){
    $expectedIntent=if($resumeExistingA){'SettleExistingAWindowAndStrictRead'}else{'PrepareFreshSingleAAndStrictRead'}
    if([string]$Contract.scope_field-cne$scopeField-or[string]$profile.intent-cne$expectedIntent){throw 'A_ONLY_PREPARATION_INTENT'}
    foreach($other in @('multi_owner_test_preparation','multi_owner_read_preflight','multi_owner_non_db_probe','multi_owner_binding_diagnostic','multi_owner_focus_registration','multi_owner_nativeom_diagnostic','multi_owner_a_expression_validation','multi_owner_b_startup_bridge','multi_owner_b_startup_bridge_resume','multi_owner_b_startup_bridge_replacement')){if($null-ne$Draft.PSObject.Properties[$other]){throw 'MULTI_OWNER_PREPARATION_SCOPES_MIXED'}}
}elseif($null-ne$Draft.PSObject.Properties['multi_owner_a_only_preparation']){throw 'MULTI_OWNER_PREPARATION_SCOPES_MIXED'}
if($mode-cnotin@('FRESH','RESUME_PREPARED_A','RESUME_EXISTING_A')-or($mode-ceq'RESUME_EXISTING_A'-and-not$aOnly)){throw 'MULTI_OWNER_PREPARATION_MODE_UNKNOWN'}
if($aOnly-and$mode-cnotin@('FRESH','RESUME_EXISTING_A')){throw 'A_ONLY_PREPARATION_FRESH_REQUIRED'}
$candidate=$Contract
if($resumeExistingA){
    if($null-eq$Contract.PSObject.Properties['resume_existing_a']){throw 'A_ONLY_EXISTING_RESUME_NOT_ADMITTED'}
    $candidate=$Contract.resume_existing_a
    if([string]$candidate.mode-cne$mode-or[string]$candidate.profile_id-cne$expectedProfile-or[string]$candidate.intent-cne$expectedIntent){throw 'A_ONLY_EXISTING_RESUME_CONTRACT_IDENTITY'}
}
if($mode-ceq'RESUME_PREPARED_A'){
    if($null-eq$Contract.PSObject.Properties['resume_prepared_a']){throw 'MULTI_OWNER_PREPARATION_RESUME_NOT_ADMITTED'}
    $candidate=$Contract.resume_prepared_a
    if([string]$candidate.mode-cne$mode){throw 'MULTI_OWNER_PREPARATION_RESUME_CONTRACT_MODE'}
}
if($null-ne$Draft.PSObject.Properties['multi_owner_read_preflight']){throw 'MULTI_OWNER_PREPARATION_AND_READ_SCOPE_MIXED'}
$manifestPath=PreparationPath $candidate.manifest_path
if((PreparationHash $manifestPath)-cne[string]$candidate.manifest_sha256){throw 'MULTI_OWNER_PREPARATION_MANIFEST_CHANGED'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$manifest.id-cne[string]$profile.profile_id){throw 'MULTI_OWNER_PREPARATION_MANIFEST_IDENTITY'}
$bindings=@{}
foreach($property in $Draft.program.PSObject.Properties){
    if($property.Name.EndsWith('_sha256')){
        $key=$property.Name.Substring(0,$property.Name.Length-7)
        $pathProperty=$Draft.program.PSObject.Properties[$key]
        if($null-eq$pathProperty){throw 'MULTI_OWNER_PREPARATION_PROGRAM_PAIR_MISSING'}
        $bindings[(PreparationPath ([string]$pathProperty.Value))]=[string]$property.Value
    }
}
foreach($file in @($manifest.files)+@([pscustomobject]@{path=$candidate.manifest_path;sha256=$candidate.manifest_sha256})){
    $path=PreparationPath $file.path
    if((PreparationHash $path)-cne[string]$file.sha256-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne[string]$file.sha256){throw ('MULTI_OWNER_PREPARATION_CANDIDATE_BINDING:'+ $file.path)}
}
$controller=PreparationPath $candidate.controller
if((PreparationPath $Draft.program.controller)-ine$controller){throw 'MULTI_OWNER_PREPARATION_CONTROLLER_NOT_ADMITTED'}
$scopePath=PreparationPath $profile.scope_path
if([string]$profile.scope_sha256-cnotmatch'^[A-F0-9]{64}$'-or(PreparationHash $scopePath)-cne[string]$profile.scope_sha256-or-not$bindings.ContainsKey($scopePath)-or$bindings[$scopePath]-cne[string]$profile.scope_sha256){throw 'MULTI_OWNER_PREPARATION_SCOPE_HASH_BINDING'}
$scope=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if($scope.schema_version-ne1-or[string]$scope.profile_id-cne[string]$profile.profile_id-or[string]$scope.run_id-cnotmatch'^[A-Za-z0-9_-]{1,80}$'-or[string]$scope.run_id-cne[string]$Draft.run_id){throw 'MULTI_OWNER_PREPARATION_SCOPE_IDENTITY'}
$scopeMode=if($null-ne$scope.PSObject.Properties['preparation_mode']){[string]$scope.preparation_mode}else{'FRESH'}
if($scopeMode-cne$mode){throw 'MULTI_OWNER_PREPARATION_SCOPE_MODE_MISMATCH'}
# Resume admission stays closed until the versioned, exact-evidence validator is
# bound by the project contract. This cannot fall through to fresh-copy rules.
if($mode-ceq'RESUME_PREPARED_A'){
    $resumeValidator=PreparationPath $candidate.scope_validator
    if((PreparationHash $resumeValidator)-cne[string]$candidate.scope_validator_sha256){throw 'MULTI_OWNER_PREPARATION_RESUME_VALIDATOR_CHANGED'}
    & $resumeValidator -Scope $scope -Contract $candidate -Root $Root -Draft $Draft | Out-Null
}
foreach($field in $(if($aOnly){@('source_path','working_copy_a')}else{@('source_path','working_copy_a','working_copy_b')})){if(-not[IO.Path]::IsPathRooted([string]$scope.$field)){throw 'MULTI_OWNER_PREPARATION_SCOPE_ABSOLUTE_PATH_REQUIRED'}}
$run=Join-Path (Join-Path $Root 'runs') $scope.run_id
# The bound terminal envelope resolves reporting metadata with Join-Path(root,p).
# Keep reporting and the command token project-relative; path arguments stay absolute.
foreach($field in @('run_directory','controller_receipt')){
    if([IO.Path]::IsPathRooted([string]$Draft.reporting.$field)){throw 'MULTI_OWNER_PREPARATION_REPORT_PROJECT_RELATIVE_REQUIRED'}
}
if((PreparationPath $Draft.reporting.run_directory)-ine$run-or(PreparationPath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'MULTI_OWNER_PREPARATION_REPORT_PATH'}
$source=PreparationPath $scope.source_path
if($source-ine(PreparationPath $Contract.source_path)-or[string]$scope.source_sha256-cne[string]$Contract.source_sha256-or(PreparationHash $source)-cne[string]$Contract.source_sha256){throw 'MULTI_OWNER_PREPARATION_SOURCE_NOT_ADMITTED'}
if($aOnly){
    $scopeContract=PreparationPath $candidate.scope_contract
    if(-not$bindings.ContainsKey($scopeContract)){throw 'A_ONLY_PREPARATION_CONTRACT_NOT_BOUND'}
    if($resumeExistingA-and(PreparationHash $scopeContract)-cne[string]$candidate.scope_contract_sha256){throw 'A_ONLY_PREPARATION_CONTRACT_CHANGED'}
    . $scopeContract
    if($resumeExistingA){
        # A continuation of the admitted A-only preparation, never a second
        # launch or a silent relaxation of the original fresh-copy contract.
        if([string]$candidate.phase-cne'EXISTING_A_WINDOW_SETTLEMENT_AND_STRICT_READ'){throw 'A_ONLY_EXISTING_RESUME_PHASE'}
        if(($scope.capability_bounds|ConvertTo-Json -Compress)-cne($candidate.capability_bounds|ConvertTo-Json -Compress)){throw 'A_ONLY_EXISTING_RESUME_CAPABILITY_BOUNDS'}
        $null=Assert-CadExistingASettlementScopeV1 $scope $Root $run
        if(Test-Path -LiteralPath $run){
            $entries=@(Get-ChildItem -LiteralPath $run -Force)
            foreach($entry in $entries){
                if($entry.PSIsContainer-or($entry.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or$entry.Name-cnotin@('execution_handoff.json','execution_controller_claim.json')){throw 'A_ONLY_EXISTING_RESUME_ALREADY_ENTERED'}
            }
            if([string]$Draft.status-ceq'DRAFT'-and$entries.Count-ne0){throw 'A_ONLY_EXISTING_RESUME_ALREADY_PUBLISHED'}
        }
    }else{
        $null=AssertCadAOnlyScopeV2 $scope $Root $run
        AssertCadAOnlyDependenciesV2 (Split-Path -Parent $scopeContract) $Root
    }
    if($scope.phase-cne$candidate.phase-or$profile.phase-cne$candidate.phase){throw 'A_ONLY_PREPARATION_PHASE'}
    if($profile.manifest_sha256-cne$candidate.manifest_sha256-or$Draft.program.manifest_sha256-cne$candidate.manifest_sha256-or$Draft.program.scope_sha256-cne$profile.scope_sha256-or(PreparationPath $Draft.program.scope)-ine$scopePath-or(PreparationPath $Draft.program.manifest)-ine$manifestPath){throw 'A_ONLY_PREPARATION_NAMED_BINDINGS'}
    if([string]$Draft.status-cnotin@('DRAFT','READY')){throw 'A_ONLY_PREPARATION_ADMISSION_STAGE'}
    if(-not$resumeExistingA){
        $runStage=if([string]$Draft.status-ceq'READY'){'Ready'}else{'Candidate'}
        AssertCadAOnlyRunStageV2 $scope $Root $run $profile.scope_sha256 $runStage
    }
}else{
$copies=@(PreparationPath $scope.working_copy_a;PreparationPath $scope.working_copy_b)
if($copies[0]-ieq$copies[1]){throw 'MULTI_OWNER_PREPARATION_COPY_PATHS_NOT_UNIQUE'}
foreach($copy in $(if($mode-ceq'RESUME_PREPARED_A'){@($copies[1])}else{$copies})){
    if((Split-Path -Parent $copy)-ine(Join-Path $run 'drawings')-or[IO.Path]::GetExtension($copy)-ine'.dwg'-or$copy-ieq$source-or(Test-Path -LiteralPath $copy)){throw 'MULTI_OWNER_PREPARATION_COPY_UNSAFE_OR_EXISTS'}
    # FullPath is lexical; reject junction/symlink ancestors before write admission.
    $ancestor=Split-Path -Parent $copy
    while($ancestor.Length-ge$Root.Length){
        if(Test-Path -LiteralPath $ancestor){if(((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'MULTI_OWNER_PREPARATION_REPARSE_PARENT'}}
        if($ancestor-ieq$Root){break};$ancestor=Split-Path -Parent $ancestor
    }
}
if($scope.request_second_instance-isnot[bool]-or-not$scope.request_second_instance){throw 'MULTI_OWNER_PREPARATION_SECOND_INSTANCE_INTENT'}
if($scope.allow_canonical_a_owned_failure_cleanup-isnot[bool]-or$scope.allow_canonical_a_owned_failure_cleanup-ne($mode-ceq'FRESH')){throw 'MULTI_OWNER_PREPARATION_CANONICAL_A_RECOVERY_SCOPE_REQUIRED'}
if($mode-ceq'RESUME_PREPARED_A'){PreparationInteger $scope.startup_timeout_seconds 0 0}else{PreparationInteger $scope.startup_timeout_seconds 30 180}
PreparationInteger $scope.second_instance_timeout_seconds 5 90
}
# The action must call the admitted controller exactly once with literal bindings.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($a)$a-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_NOT_LITERAL'}
$command=$commands[0]
if($aOnly){
    # The frozen terminal envelope prefixes '& ' and resolves its command token
    # using Join-Path(root, token). Check that actual consumer ABI, not merely
    # PreparationPath's more permissive absolute-path normalization.
    if($command.InvocationOperator-ne[Management.Automation.Language.TokenKind]::Unknown-or[IO.Path]::IsPathRooted([string]$command.GetCommandName())-or[IO.Path]::IsPathRooted([string]$Draft.program.controller)){throw 'A_ONLY_PREPARATION_ENVELOPE_COMMAND_ABI'}
    if([IO.Path]::GetFullPath((Join-Path $Root $command.GetCommandName()))-ine$controller){throw 'A_ONLY_PREPARATION_ENVELOPE_COMMAND_ABI'}
}
if((PreparationPath $command.GetCommandName())-ine$controller){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_CONTROLLER'}
$callParameters=@{};$elements=$command.CommandElements
for($i=1;$i-lt$elements.Count;$i+=2){
    if($elements[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$elements[$i].Argument-or$i+1-ge$elements.Count){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_PARAMETER'}
    $name=$elements[$i].ParameterName
    if($callParameters.ContainsKey($name)){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_DUPLICATE_PARAMETER'}
    $value=$elements[$i+1]
    if($value-is[Management.Automation.Language.StringConstantExpressionAst]){$callParameters[$name]=$value.Value}
    elseif($value-is[Management.Automation.Language.ConstantExpressionAst]){$callParameters[$name]=$value.Value}
    else{throw 'MULTI_OWNER_PREPARATION_TEMPLATE_NOT_LITERAL'}
}
if($callParameters.Count-ne3-or@('RunDirectory','ScopePath','ScopeSha256'|Where-Object{-not$callParameters.ContainsKey($_)}).Count-ne0){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_PARAMETER_SET'}
if($aOnly-and(-not[IO.Path]::IsPathRooted([string]$callParameters.RunDirectory)-or-not[IO.Path]::IsPathRooted([string]$callParameters.ScopePath))){throw 'A_ONLY_PREPARATION_ENVELOPE_ARGUMENT_ABSOLUTE_REQUIRED'}
if((PreparationPath $callParameters.RunDirectory)-ine$run-or(PreparationPath $callParameters.ScopePath)-ine$scopePath-or[string]$callParameters.ScopeSha256-cne[string]$profile.scope_sha256){throw 'MULTI_OWNER_PREPARATION_TEMPLATE_SCOPE_MISMATCH'}
[pscustomobject]@{status='PASS';profile_id=$profile.profile_id;cad_calls=0;live_verified=$false;intent=$(if($aOnly){$expectedIntent}else{'LifecyclePreparation'});business_commands_allowed=$false;concurrency_allowed=$false}
