param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
$resolved=@{}
function ResolveFixturePath([string]$Value){
 if([string]::IsNullOrWhiteSpace($Value)){throw 'FIXTURE_ADMIT_PATH_EMPTY'}
 if($resolved.ContainsKey($Value)){return $resolved[$Value]}
 $p=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
 if(-not$p.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_ADMIT_PATH_ESCAPE'}
 for($a=$p;$a.Length-ge$Root.Length;$a=Split-Path -Parent $a){
  if((Test-Path -LiteralPath $a)-and((Get-Item -LiteralPath $a -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'FIXTURE_ADMIT_REPARSE'}
  if($a-ieq$Root){break}
 }
 $resolved[$Value]=$p;return $p
}
function AssertFixtureCaps($Actual){
 $expected=$Contract.candidate_capability_bounds
 if(@($Actual.PSObject.Properties).Count-ne@($expected.PSObject.Properties).Count){throw 'FIXTURE_ADMIT_CAPABILITY_FIELDS'}
 foreach($p in $expected.PSObject.Properties){$a=$Actual.PSObject.Properties[$p.Name];if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Compress)-cne($p.Value|ConvertTo-Json -Compress)){throw ('FIXTURE_ADMIT_CAPABILITY:'+ $p.Name)}}
}
$profile=$Draft.existing_a_fixture_open
if($Contract.profile_id-cne'CAD-EXISTING-A-READONLY-FIXTURE-OPEN-V1'-or$profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne$Contract.intent-or$profile.phase-cne$Contract.phase-or$Draft.governance.workflow_id-cne$Contract.profile_id){throw 'FIXTURE_ADMIT_PROFILE'}
$mp=ResolveFixturePath $profile.manifest_path
$rel=[IO.Path]::GetRelativePath($Root,$mp).Replace('\','/')
if($rel-cnotmatch('^'+[regex]::Escape($Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$')){throw 'FIXTURE_ADMIT_DIRECTORY'}
$version=[long]$Matches[1]
if($profile.manifest_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash -LiteralPath $mp).Hash-cne$profile.manifest_sha256){throw 'FIXTURE_ADMIT_MANIFEST_HASH'}
$m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json -DateKind String
if($m.id-cne$Contract.profile_id-or$m.source_thread_id-cne$Contract.candidate_source_thread_id-or$m.implementation_version-ne$version-or$m.package_version-ne$version-or$m.scope_field-cne'existing_a_fixture_open'-or$m.intent-cne$Contract.intent-or$m.phase-cne$Contract.phase-or$m.status-cne'SEALED_PRIVATE_VALIDATION_ONLY__SHARED_ADMISSION_REQUIRED'){throw 'FIXTURE_ADMIT_MANIFEST_IDENTITY'}
AssertFixtureCaps $m.capability_bounds
$bindings=@{}
foreach($p in $Draft.program.PSObject.Properties){if($p.Name.EndsWith('_sha256')){
 $pair=$Draft.program.PSObject.Properties[$p.Name.Substring(0,$p.Name.Length-7)]
 if($null-eq$pair){throw 'FIXTURE_ADMIT_PROGRAM_PAIR'}
 $path=ResolveFixturePath ([string]$pair.Value)
 if($bindings.ContainsKey($path)-and$bindings[$path]-cne$p.Value){throw 'FIXTURE_ADMIT_PROGRAM_CONFLICT'}
 $bindings[$path]=[string]$p.Value
}}
function AssertFixtureBound([string]$Path,[string]$Hash){
 $p=ResolveFixturePath $Path
 if($Hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash -LiteralPath $p).Hash-cne$Hash-or-not$bindings.ContainsKey($p)-or$bindings[$p]-cne$Hash){throw ('FIXTURE_ADMIT_BINDING:'+ $Path)}
}
foreach($f in @($m.files)+@([pscustomobject]@{path=$mp;sha256=$profile.manifest_sha256})){AssertFixtureBound $f.path $f.sha256}
foreach($f in $Contract.frozen_dependencies){
 AssertFixtureBound $f.path $f.sha256
 if(@($m.files|Where-Object{(ResolveFixturePath $_.path)-ieq(ResolveFixturePath $f.path)-and$_.sha256-ceq$f.sha256}).Count-ne1){throw 'FIXTURE_ADMIT_FROZEN_DEPENDENCY'}
}
$controller=ResolveFixturePath $m.controller;$sc=ResolveFixturePath $m.scope_contract;$sp=ResolveFixturePath $profile.scope_path
foreach($p in @($controller,$sc,$sp)){if(-not$p.StartsWith((Split-Path $mp)+'\',[StringComparison]::OrdinalIgnoreCase)-or@($m.files|Where-Object{(ResolveFixturePath $_.path)-ieq$p}).Count-ne1){throw 'FIXTURE_ADMIT_PRIVATE_MEMBER'}}
if((ResolveFixturePath $Draft.program.controller)-ine$controller){throw 'FIXTURE_ADMIT_CONTROLLER'}
AssertFixtureBound $sp $profile.scope_sha256
$s=Get-Content -LiteralPath $sp -Raw|ConvertFrom-Json -DateKind String
if($s.profile_id-cne$Contract.profile_id-or$s.implementation_version-ne$version-or$s.intent-cne$Contract.intent-or$s.phase-cne$Contract.phase-or$s.run_id-cne$Draft.run_id-or$s.run_id-cnotmatch'\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z'){throw 'FIXTURE_ADMIT_SCOPE_IDENTITY'}
AssertFixtureCaps $s.capability_bounds
foreach($n in @('open_read_only','foreground_effect_authorized','restore_original_foreground_allowed','execution_requires_matching_READY')){if($s.$n-isnot[bool]-or-not$s.$n){throw 'FIXTURE_ADMIT_RIGHTS'}}
if($s.live_admitted-isnot[bool]-or$s.live_admitted-or$s.new_process_max-ne0-or$s.document_open_max-ne1-or$s.helper_timeout_seconds-ne15-or$s.drain_timeout_seconds-ne3){throw 'FIXTURE_ADMIT_LIMITS'}
if($s.authority.policy_path-cne$Contract.authority_policy-or$s.authority.source_thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'FIXTURE_ADMIT_AUTHORITY'}
$run=Join-Path $Root ('runs/'+$s.run_id)
$copy=ResolveFixturePath $s.new_copy_path;$source=ResolveFixturePath $s.fixture_source
if((Split-Path $copy)-ine(Join-Path $run 'drawings')-or[IO.Path]::GetExtension($copy)-ine'.dwg'-or$copy-ieq$source-or(Test-Path -LiteralPath $copy)){throw 'FIXTURE_ADMIT_COPY'}
if($s.fixture_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-FileHash -LiteralPath $source).Hash-cne$s.fixture_sha256){throw 'FIXTURE_ADMIT_SOURCE_HASH'}
foreach($leaf in @('controller_once_claim.json','controller_receipt.json','worker_receipt.json','worker_stages.jsonl','foreground_samples.jsonl','resource_samples.jsonl','execution_return.json')){if(Test-Path -LiteralPath (Join-Path $run $leaf)){throw 'FIXTURE_ADMIT_REPLAY'}}
$identity=& {param($Entry,$Scope,$Root) . $Entry; Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=@($Scope.old_owner);sequence=@('A')}) $Root} (ResolveFixturePath $Contract.identity_contract) $s $Root
if(@($identity.owners).Count-ne1-or$identity.owners[0].id-cne'A'){throw 'FIXTURE_ADMIT_OWNER'}
foreach($n in @('canonical_open','launch_policy')){if($Draft.$n.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$n.launch_permitted_for_this_handoff){throw 'FIXTURE_ADMIT_LAUNCH'}}
foreach($n in @('standalone_close_allowed','inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open')){if($Draft.launch_policy.$n-isnot[bool]-or$Draft.launch_policy.$n){throw 'FIXTURE_ADMIT_LIFECYCLE'}}
foreach($n in @('run_directory','controller_receipt')){if([IO.Path]::IsPathRooted([string]$Draft.reporting.$n)){throw 'FIXTURE_ADMIT_REPORT_ABI'}}
if((ResolveFixturePath $Draft.reporting.run_directory)-ine$run-or(ResolveFixturePath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'FIXTURE_ADMIT_REPORT'}
# Validate the actual terminal-envelope command ABI, not just equivalent paths.
$tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'FIXTURE_ADMIT_TEMPLATE'}
$c=$commands[0]
if($c.InvocationOperator-ne[Management.Automation.Language.TokenKind]::Unknown-or[IO.Path]::IsPathRooted([string]$c.GetCommandName())-or[IO.Path]::IsPathRooted([string]$Draft.program.controller)-or(ResolveFixturePath $c.GetCommandName())-ine$controller){throw 'FIXTURE_ADMIT_COMMAND_ABI'}
$argsMap=@{};$els=$c.CommandElements
for($i=1;$i-lt$els.Count;$i+=2){
 if($els[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$els[$i].Argument-or$i+1-ge$els.Count){throw 'FIXTURE_ADMIT_PARAMETER'}
 $n=$els[$i].ParameterName;$v=$els[$i+1]
 if($argsMap.ContainsKey($n)-or$v-isnot[Management.Automation.Language.ConstantExpressionAst]){throw 'FIXTURE_ADMIT_LITERAL'}
 $argsMap[$n]=$v.Value
}
if($argsMap.Count-ne4-or@('RunDirectory','ScopePath','ScopeSha256','TimeoutSeconds'|Where-Object{-not$argsMap.ContainsKey($_)}).Count){throw 'FIXTURE_ADMIT_PARAMETER_SET'}
if(-not[IO.Path]::IsPathRooted([string]$argsMap.RunDirectory)-or-not[IO.Path]::IsPathRooted([string]$argsMap.ScopePath)-or(ResolveFixturePath $argsMap.RunDirectory)-ine$run-or(ResolveFixturePath $argsMap.ScopePath)-ine$sp-or$argsMap.ScopeSha256-cne$profile.scope_sha256-or$argsMap.TimeoutSeconds.GetType()-notin@([int],[long])-or$argsMap.TimeoutSeconds-ne15){throw 'FIXTURE_ADMIT_ARGUMENT_BINDING'}
# Private checks add source-specific constraints; they cannot replace shared bounds.
& {param($Path,$Name,$Scope,$Root,$Run) . $Path; & $Name $Scope $Root $Run | Out-Null} $sc ('Assert-CadExistingAOpenScopeV'+$version) $s $Root $run
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;owner_count=1;document_open_max=1;readonly=$true;cad_calls=0;live_verified=$false}
