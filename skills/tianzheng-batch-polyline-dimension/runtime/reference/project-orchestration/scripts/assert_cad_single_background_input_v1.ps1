param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function ResolveBackgroundPath([string]$Value){
    if([string]::IsNullOrWhiteSpace($Value)){throw 'BACKGROUND_PATH_EMPTY'}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BACKGROUND_PATH_OUTSIDE_PROJECT'}
    for($ancestor=$path;$ancestor.Length-gt$Root.Length;$ancestor=Split-Path -Parent $ancestor){
        if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'BACKGROUND_REPARSE'}
    }
    $path
}
function AssertBackgroundCaps($Actual,$Expected){
    if(@($Actual.PSObject.Properties).Count-ne@($Expected.PSObject.Properties).Count){throw 'BACKGROUND_CAPABILITY_FIELDS'}
    foreach($p in $Expected.PSObject.Properties){
        $a=$Actual.PSObject.Properties[$p.Name]
        if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Depth 8 -Compress)-cne($p.Value|ConvertTo-Json -Depth 8 -Compress)){throw ('BACKGROUND_CAPABILITY:'+ $p.Name)}
    }
}
$profile=$Draft.single_background_input
if($Contract.profile_id-cne'CAD-SINGLE-BACKGROUND-INPUT-V1'-or$profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne$Contract.intent-or$Draft.governance.workflow_id-cne$Contract.profile_id){throw 'BACKGROUND_PROFILE_IDENTITY'}
$lookupIntent=$null;$targetOwner='A';$fileDocumentB=$false
$capabilityBounds=$Contract.candidate_capability_bounds|ConvertTo-Json -Depth 10|ConvertFrom-Json -DateKind String
if($null-ne$profile.PSObject.Properties['lookup_intent']){
    $lookupIntent=[string]$profile.lookup_intent
    if($lookupIntent-cne'ReadExistingBFileDocumentAndSendFixedBackgroundRead'-or$null-eq$Contract.PSObject.Properties['candidate_lookup_variants']){throw 'BACKGROUND_LOOKUP_VARIANT_UNKNOWN'}
    $variant=$Contract.candidate_lookup_variants.PSObject.Properties[$lookupIntent]
    if($null-eq$variant){throw 'BACKGROUND_LOOKUP_VARIANT_NOT_ADMITTED'}
    foreach($field in $variant.Value.capability_overlay.PSObject.Properties){$capabilityBounds|Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value -Force}
    $targetOwner='B';$fileDocumentB=$true
}
$manifestPath=ResolveBackgroundPath $profile.manifest_path
$relative=[IO.Path]::GetRelativePath($Root,$manifestPath).Replace('\','/')
if($relative-cnotmatch('^'+[regex]::Escape($Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$')){throw 'BACKGROUND_CANDIDATE_DIRECTORY'}
$version=[long]$Matches[1]
if($profile.manifest_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash $manifestPath).Hash-cne$profile.manifest_sha256){throw 'BACKGROUND_MANIFEST_HASH'}
$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json -DateKind String
if($manifest.id-cne$Contract.profile_id-or$manifest.source_thread_id-cne$Contract.candidate_source_thread_id-or$manifest.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'-or$manifest.scope_field-cne'single_background_input'-or$manifest.intent-cne$Contract.intent-or$manifest.implementation_version-ne$version-or$manifest.package_version-ne$version){throw 'BACKGROUND_MANIFEST_IDENTITY'}
AssertBackgroundCaps $manifest.capability_bounds $capabilityBounds
if($fileDocumentB-and($null-eq$manifest.PSObject.Properties['lookup_intent']-or$manifest.lookup_intent-cne$lookupIntent)){throw 'BACKGROUND_MANIFEST_LOOKUP_VARIANT'}
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
function ConvertBackgroundCanonicalEvidence($Value,[string]$FieldName=''){
    if($null-eq$Value){return 'null'}
    if($Value-is[pscustomobject]){
        $parts=foreach($name in @($Value.PSObject.Properties.Name|Sort-Object -CaseSensitive)){
            ($name|ConvertTo-Json -Compress)+':'+(ConvertBackgroundCanonicalEvidence $Value.$name $name)
        }
        return '{'+($parts-join',')+'}'
    }
    if($Value-is[Array]){
        $parts=foreach($item in $Value){ConvertBackgroundCanonicalEvidence $item}
        return '['+($parts-join',')+']'
    }
    # The formal JSON writer drops a trailing fractional zero on at_utc.
    # Compare the same UTC instant, not serializer precision; other text stays literal.
    if($FieldName-ceq'at_utc'-and$Value-is[string]-and$Value-cmatch'\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,7})?(?:Z|[+-]\d\d:\d\d)\z'){
        $stamp=[DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
        return ('UTC_TICKS:'+ $stamp.UtcTicks)|ConvertTo-Json -Compress
    }
    $Value|ConvertTo-Json -Compress
}
function AssertBackgroundPriorBRead($Scope){
    if($null-eq$Scope.PSObject.Properties['prior_B_read']){throw 'BACKGROUND_PRIOR_B_READ_REQUIRED'}
    $prior=$Scope.prior_B_read;$facts=@{};$paths=@{}
    if(@($prior.PSObject.Properties).Count-ne8){throw 'BACKGROUND_PRIOR_B_READ_FIELDS'}
    foreach($kind in @('return','scope','controller','worker')){
        AssertBackgroundBound $prior.($kind+'_path') $prior.($kind+'_sha256')
        $paths[$kind]=ResolveBackgroundPath $prior.($kind+'_path')
        $facts[$kind]=Get-Content -LiteralPath $paths[$kind] -Raw|ConvertFrom-Json -DateKind String
    }
    $r=$facts.return;$s=$facts.scope;$c=$facts.controller;$w=$facts.worker
    if($r.schema_version-lt3-or$r.status-cne'REPORTED'-or$r.writer.thread_id-cne'RECEIVER_ID_REQUIRED'-or
        $r.reader.thread_id-cne$Contract.candidate_source_thread_id-or$r.run_scope_complete-isnot[bool]-or-not$r.run_scope_complete-or
        $r.execution_control_released-isnot[bool]-or-not$r.execution_control_released-or$r.retry_count-ne0){throw 'BACKGROUND_PRIOR_B_FORMAL_RETURN'}
    if($r.run_id-cnotmatch'\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z'){throw 'BACKGROUND_PRIOR_B_RUN_ID'}
    $priorRun=Join-Path $Root ('runs/'+$r.run_id)
    if($paths.return-ine(Join-Path $priorRun 'execution_return.json')-or$paths.controller-ine(Join-Path $priorRun 'controller_receipt.json')-or
        $paths.worker-ine(Join-Path $priorRun 'read_session_worker_receipt.json')-or
        (ResolveBackgroundPath $r.controller_report_path)-ine$paths.controller-or$r.controller_report_sha256-cne$prior.controller_sha256){throw 'BACKGROUND_PRIOR_B_PROVENANCE'}
    # JSON object member order is not evidence; retain all values/types and
    # array order while comparing the independently hashed embedded reports.
    if((ConvertBackgroundCanonicalEvidence $r.controller_report)-cne(ConvertBackgroundCanonicalEvidence $c)-or
        (ConvertBackgroundCanonicalEvidence $c.worker_receipt)-cne(ConvertBackgroundCanonicalEvidence $w)){throw 'BACKGROUND_PRIOR_B_EMBEDDED_EVIDENCE'}
    foreach($e in @($s,$c,$w)){
        if($e.run_id-cne$r.run_id-or$e.profile_id-cne'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1'-or(@($e.sequence)-join',')-cne'B'){throw 'BACKGROUND_PRIOR_B_IDENTITY'}
    }
    if($s.lookup_intent-cne'ReadExistingBFileRotNonActivating'-or$w.lookup_intent-cne$s.lookup_intent-or
        $c.scope_sha256-cne$prior.scope_sha256-or$w.scope_sha256-cne$prior.scope_sha256-or
        ($s.owners|ConvertTo-Json -Depth 12 -Compress)-cne($Scope.owners|ConvertTo-Json -Depth 12 -Compress)-or
        $s.lookup_target_path-cne$Scope.lookup_target_path){throw 'BACKGROUND_PRIOR_B_SCOPE_OWNER'}
    if($c.status-cne'PASS_B_READ_PROBE_ONLY'-or$w.status-cne'PASS_B_READ_PROBE_ONLY'-or$c.protected_hashes_after-cne'UNCHANGED'-or$w.protected_hashes_after-cne'UNCHANGED'){throw 'BACKGROUND_PRIOR_B_NOT_PASS'}
    $helper=$c.helper_phase
    if($helper.root_exit_code-ne0-or$helper.job_active_after-ne0-or$helper.output_complete-isnot[bool]-or-not$helper.output_complete-or
        $helper.job_bound_before_resume-isnot[bool]-or-not$helper.job_bound_before_resume-or$helper.own_job_stop_attempted-isnot[bool]-or$helper.own_job_stop_attempted){throw 'BACKGROUND_PRIOR_B_HELPER_UNSETTLED'}
    foreach($name in @('cad_launch_count','cad_close_count','cad_kill_count','cad_save_count','cad_load_count','cad_send_count','click_count','foreground_activation_count','register_count','revoke_count','retry_count')){
        if($c.$name.GetType()-notin@([int],[long])-or$c.$name-ne0){throw ('BACKGROUND_PRIOR_B_CONTROLLER_EFFECT:'+ $name)}
    }
    foreach($name in @('cad_launch_count','cad_close_count','cad_kill_count','cad_save_count','cad_load_count','cad_send_count','click_count','input_injection_count','register_count','revoke_count','retry_count')){
        if($w.$name.GetType()-notin@([int],[long])-or$w.$name-ne0){throw ('BACKGROUND_PRIOR_B_WORKER_EFFECT:'+ $name)}
    }
    if(@($w.rows).Count-ne1-or$w.rows[0].owner-cne'B'){throw 'BACKGROUND_PRIOR_B_ROW'}
    $values=$w.rows[0].values
    if($values.FullName-cne$Scope.lookup_target_path-or$values.Name-cne[IO.Path]::GetFileName($Scope.lookup_target_path)-or
        $values.CMDNAMES-isnot[string]-or-not[string]::IsNullOrWhiteSpace($values.CMDNAMES)-or
        $values.CMDACTIVE.GetType()-notin@([int],[long])-or$values.CMDACTIVE-ne0-or
        $values.DBMOD.GetType()-notin@([int],[long])-or$values.DBMOD-ne0-or
        $values.'ModelSpace.Count'.GetType()-notin@([int],[long])-or$values.'ModelSpace.Count'-lt0){throw 'BACKGROUND_PRIOR_B_READ_VALUES'}
    $wanted=@('FullName','Name','CMDNAMES','CMDACTIVE','DBMOD','ModelSpace.Count')
    if(@($w.getter_events).Count-ne6-or@($w.binding_events).Count-ne12){throw 'BACKGROUND_PRIOR_B_READ_COUNT'}
    for($i=0;$i-lt6;$i++){
        $g=$w.getter_events[$i]
        if($g.owner-cne'B'-or$g.getter-cne$wanted[$i]-or$g.status-cne'RETURNED'-or
            ($g.value|ConvertTo-Json -Compress)-cne($values.($wanted[$i])|ConvertTo-Json -Compress)){throw 'BACKGROUND_PRIOR_B_GETTER'}
        foreach($offset in @(0,1)){
            $b=$w.binding_events[2*$i+$offset];$side=if($offset-eq0){'BEFORE_GETTER'}else{'AFTER_GETTER'}
            if($b.index-ne(2*$i+$offset+1)-or$b.owner-cne'B'-or$b.getter-cne$wanted[$i]-or$b.side-cne$side-or
                $b.status-cne'RETURNED'-or$b.code-cne'EXACT_REGISTERED_DOCUMENT_ADMITTED'-or
                $b.observed.moniker-cne$Scope.lookup_target_path-or$b.observed.hwnd-ne$Scope.owners[1].window_handle-or
                $b.observed.target-isnot[bool]-or-not$b.observed.target){throw 'BACKGROUND_PRIOR_B_BINDING'}
            $native=@($b.trace|Where-Object stage -CEQ 'REGISTERED_DOCUMENT_COM_IDENTITY')
            if($native.Count-ne1){throw 'BACKGROUND_PRIOR_B_IUNKNOWN_COUNT'}
            $n=$native[0].result
            if($n.kind-cne'COM_IUNKNOWN'-or$n.same-isnot[bool]-or-not$n.same-or$n.verified-isnot[bool]-or-not$n.verified-or
                $n.runtime_COM_evidence-isnot[bool]-or-not$n.runtime_COM_evidence-or$n.acquired-ne2-or$n.release_attempts-ne2-or
                @($n.release_errors).Count-ne0-or$null-ne$n.error){throw 'BACKGROUND_PRIOR_B_IUNKNOWN'}
        }
    }
    $lookup=$w.lookup_facts
    if($lookup.status-cne'REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED'-or$lookup.owned_name_and_table_released-isnot[bool]-or-not$lookup.owned_name_and_table_released){throw 'BACKGROUND_PRIOR_B_LOOKUP'}
    foreach($name in @('table','create','is_running','get_object')){if($lookup.counts.$name-ne1){throw 'BACKGROUND_PRIOR_B_LOOKUP_COUNT'}}
    foreach($name in @('activation_count','enumeration_count','fallback_count')){if($lookup.$name-ne0){throw 'BACKGROUND_PRIOR_B_LOOKUP_EFFECT'}}
    foreach($name in @('CreateTable','CreateName','IsRunning','GetObject')){
        $entry=@($w.lookup_events|Where-Object stage -CEQ $name)
        if($entry.Count-ne1-or$entry[0].status-cne'RETURNED'-or$null-eq$entry[0].raw_hresult-or$entry[0].raw_hresult-ne0){throw 'BACKGROUND_PRIOR_B_LOOKUP_RAW_HRESULT'}
    }
}
foreach($f in @($manifest.files)+@([pscustomobject]@{path=$manifestPath;sha256=$profile.manifest_sha256})){AssertBackgroundBound $f.path $f.sha256}
$controller=ResolveBackgroundPath $manifest.controller
$scopeContract=ResolveBackgroundPath $manifest.scope_contract
foreach($path in @($controller,$scopeContract)){
    if(-not$path.StartsWith((Split-Path $manifestPath)+'\',[StringComparison]::OrdinalIgnoreCase)-or@($manifest.files|Where-Object{(ResolveBackgroundPath $_.path)-ieq$path}).Count-ne1){throw 'BACKGROUND_CODE_NOT_BOUND'}
}
if((ResolveBackgroundPath $Draft.program.controller)-ine$controller){throw 'BACKGROUND_CONTROLLER_MISMATCH'}
$scopePath=ResolveBackgroundPath $profile.scope_path
AssertBackgroundBound $scopePath $profile.scope_sha256
$scope=Get-Content $scopePath -Raw|ConvertFrom-Json -DateKind String
if($scope.schema_version-ne1-or$scope.profile_id-cne$Contract.profile_id-or$scope.intent-cne$Contract.intent-or$scope.phase-cne$Contract.phase-or(@($scope.sequence)-join',')-cne$targetOwner-or$scope.run_id-cne$Draft.run_id-or$scope.run_id-cnotmatch'\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z'){throw 'BACKGROUND_SCOPE_IDENTITY'}
AssertBackgroundCaps $scope.capability_bounds $capabilityBounds
# Frozen pure identity and expression implementations are independent of private checks.
foreach($f in $Contract.frozen_dependencies){
    AssertBackgroundBound $f.path $f.sha256
    if(@($manifest.files|Where-Object{(ResolveBackgroundPath $_.path)-ieq(ResolveBackgroundPath $f.path)-and$_.sha256-ceq$f.sha256}).Count-ne1){throw 'BACKGROUND_FROZEN_DEPENDENCY'}
}
$identity=& {
    param($Entry,$Scope,$Root,$FileDocumentB)
    . $Entry
    # ABA is only the frozen identity validator's metadata shape. No GET or send
    # occurs here; the independently checked actual sequence remains B only.
    $metadataSequence=if($FileDocumentB){@('A','B','A')}else{@('A')}
    Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=$metadataSequence}) $Root
} (ResolveBackgroundPath $Contract.identity_contract) $scope $Root $fileDocumentB
if($fileDocumentB){
    if(@($identity.owners).Count-ne2-or(@($identity.owners.id)-join',')-cne'A,B'-or
        $scope.lookup_intent-cne$lookupIntent-or$scope.lookup_target_path-cne$identity.owners[1].document_full_path-or
        @($identity.owners|Where-Object{[long]$_.window_handle-gt[uint32]::MaxValue}).Count-ne0){throw 'BACKGROUND_EXACT_B_LOOKUP_SCOPE'}
    AssertBackgroundPriorBRead $scope
}elseif(@($identity.owners).Count-ne1-or$identity.owners[0].id-cne'A'-or[long]$identity.owners[0].window_handle-gt[uint32]::MaxValue){throw 'BACKGROUND_SINGLE_OWNER_ONLY'}
$operations=@($scope.operations)
if($operations.Count-ne1){throw 'BACKGROUND_ONE_OPERATION'}
$op=$operations[0]
if($op.owner-cne$targetOwner-or$op.id-cnotmatch('\A'+$targetOwner+'[1-9][0-9]{0,2}\z')-or($fileDocumentB-and$op.id-cne'B1')-or$op.nonce-cnotmatch'\A[a-f0-9]{32}\z'-or$op.duration_ms.GetType()-notin@([int],[long])-or$op.duration_ms-ne0){throw 'BACKGROUND_FIXED_OPERATION'}
$run=Join-Path $Root ('runs/'+$scope.run_id)
if((ResolveBackgroundPath $op.signal_path)-ine(Join-Path $run ('signals/'+$op.id+'.log'))){throw 'BACKGROUND_SIGNAL_PATH'}
foreach($leaf in @('controller_receipt.json','controller_once_claim.json','worker_receipt.json','worker_stages.jsonl','execution_return.json','signals')){if(Test-Path -LiteralPath (Join-Path $run $leaf)){throw 'BACKGROUND_RUN_REPLAY'}}
foreach($p in $scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_)'){throw 'BACKGROUND_ARBITRARY_PAYLOAD_OR_RIGHT'}}
foreach($name in @('canonical_open','launch_policy')){if($Draft.$name.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$name.launch_permitted_for_this_handoff){throw 'BACKGROUND_LAUNCH_FORBIDDEN'}}
foreach($name in @('standalone_close_allowed','inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open')){if($Draft.launch_policy.$name-isnot[bool]-or$Draft.launch_policy.$name){throw 'BACKGROUND_LIFECYCLE_FORBIDDEN'}}
if((ResolveBackgroundPath $Draft.reporting.run_directory)-ine$run-or(ResolveBackgroundPath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'BACKGROUND_REPORT_PATH'}
# Extra private checks cannot replace the frozen shared functions or the call parser.
& {param($Path,$Name,$Scope,$Root,$Run) . $Path; & $Name $Scope $Root $Run | Out-Null} $scopeContract ('Assert-CadSingleBackgroundScopeV'+$version) $scope $Root $run
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
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;owner_count=@($identity.owners).Count;send_max_count=1;cad_calls=0;live_verified=$false}
