$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$script:FixedV3Prefix='reports/cad_multi_window_interface_research/independent_project_jobs_v3/'
function Resolve-FixedV3Root([string]$Root){$item=Get-Item -LiteralPath $Root;if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$item.ResolveLinkTarget($true).FullName}else{[IO.Path]::GetFullPath($Root)}}
function Resolve-FixedV3Path([string]$Root,[string]$Path){
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/');$full=if([IO.Path]::IsPathRooted($Path)){[IO.Path]::GetFullPath($Path)}else{[IO.Path]::GetFullPath((Join-Path $base $Path))}
 if(-not$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'FIXED_V3_PATH_ESCAPE'}
 for($cursor=$full;$cursor.Length-gt$base.Length;$cursor=Split-Path -Parent $cursor){if((Test-Path -LiteralPath $cursor)-and((Get-Item -LiteralPath $cursor).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'FIXED_V3_NESTED_REPARSE'}}
 $full
}
function Read-FixedV3Json([string]$Path,[string]$Hash){if((Get-FileHash -LiteralPath $Path).Hash-cne$Hash){throw 'FIXED_V3_BOUND_HASH'};Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}
function Write-FixedV3NewJson([string]$Path,$Value){
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 35 -Compress))
 $f=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()};[IO.File]::Move($temporary,$Path,$false)
}
function Get-FixedV3Profile([string]$Root){(Get-Content -LiteralPath (Join-Path $Root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json).routes.shared_annotation_interface_read.optional_command_profiles.'CAD-AB-INDEPENDENT-PROJECT-JOBS-V3'}
function Assert-CadIndependentProjectScopeV3($Scope,[string]$Root){
 $Root=Resolve-FixedV3Root $Root;$profile=Get-FixedV3Profile $Root;$run=Resolve-FixedV3Path $Root ('runs/'+$Scope.run_id)
 if($Scope.schema_version-ne3-or$Scope.implementation_version-ne3-or$Scope.validation_mode-cne'PARALLEL_NATIVE_WRITE_ONLY'-or$Scope.profile_id-cne$profile.profile_id-or$Scope.intent-cne$profile.intent-or$Scope.phase-cne$profile.phase-or$Scope.route-cne'shared_annotation_interface_read'-or$Scope.source_thread_id-cne'RECEIVER_SOURCE_A'-or$Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'CHANNEL_SCOPE_IDENTITY'}
 if(($Scope.capability_bounds|ConvertTo-Json -Depth 10 -Compress)-cne($profile.candidate_capability_bounds|ConvertTo-Json -Depth 10 -Compress)){throw 'CHANNEL_CAPS'}
 if((@($Scope.case_ids)-join',')-cne'AB'-or(@($Scope.hosts.id)-join',')-cne'A,B'-or@($Scope.hosts).Count-ne2){throw 'CHANNEL_AB_ONLY'}
 if(@($Scope.requests).Count-ne2-or(@($Scope.requests.owner)-join',')-cne'A,B'){throw 'CHANNEL_REQUEST_SLOTS'}
 foreach($r in $Scope.requests){$s=if($r.owner-ceq'A'){'RECEIVER_SOURCE_A'}else{'RECEIVER_SOURCE_B'};if($r.source_thread_id-cne$s-or$r.request_id-cne('AB_'+$r.owner+'_SEQUENCE_1')-or$r.sequence-ne1-or$r.nonce-cnotmatch'^[a-f0-9]{32}$'-or$r.operation-cne'KNOWN_WRITE_BATCH'){throw 'CHANNEL_REQUEST_SLOT_ROUTE'}}
 if((Get-FileHash -LiteralPath (Resolve-FixedV3Path $Root $Scope.source.path)).Hash-cne$Scope.source.sha256){throw 'CHANNEL_SOURCE_HASH'}
 foreach($h in $Scope.hosts){
  $session=Resolve-FixedV3Path $run $h.session_dir;$bootPath=Resolve-FixedV3Path $session $h.boot_path;$b=Read-FixedV3Json $bootPath $h.boot_sha256
  if($b.schema_version-ne10-or$b.validation_mode-cne$Scope.validation_mode-or$b.source_thread_id-cne$(if($h.id-ceq'A'){$Scope.source_thread_id}else{'RECEIVER_SOURCE_B'})-or$b.owner-cne$h.id-or$b.run_id-cne$Scope.run_id-or$b.root-ine$Root-or$b.session_dir-ine$session-or@($b.cases).Count-ne1-or$b.cases[0].id-cne'AB'-or$b.source_sha256-cne$Scope.source.sha256-or$b.source-ine(Resolve-FixedV3Path $Root $Scope.source.path)){throw 'CHANNEL_BOOT_IDENTITY'}
  $work=Resolve-FixedV3Path $session $b.cases[0].work
  if($work-ine(Join-Path $session 'AB/work.dwg')-or$b.cases[0].sha256-cne$Scope.source.sha256-or(Get-FileHash $work).Hash-cne$Scope.source.sha256){throw 'CHANNEL_CLEAN_COPY'}
  if($b.cases[0].checkpoint-ine(Join-Path $session 'AB/write_checkpoint.dwg')-or(Test-Path $b.cases[0].checkpoint)){throw 'CHANNEL_NEW_CHECKPOINT'}
  if((@($b.operations)-join',')-cne'KNOWN_WRITE_BATCH'){throw 'CHANNEL_FIXED_PLAN'}
  if($b.module_sha256-cne(Get-FileHash (Join-Path $Root ($script:FixedV3Prefix+'bin/CadChannelV11.dll'))).Hash-or@($b.machine_arx).Count-ne7){throw 'CHANNEL_MODULE'}
  $names=@('tch_kernal.arx','tch_utility.arx','tch_pipewire.arx','tch_pipebase.arx','tch_initstart.arx','tch_common.arx','tch3_kernal.arx')
  for($i=0;$i-lt7;$i++){$a=$b.machine_arx[$i];if($a.path-ine(Join-Path $b.machine_sys $names[$i])-or(Get-FileHash $a.path).Hash-cne$a.sha256){throw 'CHANNEL_ARX'}}
 }
 [pscustomobject]@{root=$Root;run=$run;profile=$profile;hosts=$Scope.hosts}
}
function Assert-CadIndependentProjectManifestV3($Manifest,[string]$Root){
 $Root=Resolve-FixedV3Root $Root;if($Manifest.profile_id-cne'CAD-AB-INDEPENDENT-PROJECT-JOBS-V3'){throw 'CHANNEL_MANIFEST_ID'}
 $seen=@{};foreach($f in $Manifest.files){$p=Resolve-FixedV3Path $Root $f.path;if($seen.ContainsKey($p)-or(Get-FileHash $p).Hash-cne$f.sha256){throw 'CHANNEL_MANIFEST_HASH'};$seen[$p]=$true}
 foreach($leaf in @('channel_contract_v11.ps1','invoke_channel_v11.ps1','launch_channel_v11.ps1','ChannelModuleV11.cs','ChannelProtocolV11.cs','FixedTaskProtocol.cs','bin/CadChannelV11.dll','OwnStartupJobV4.cs','bin/OwnStartupJobV4.dll','startup_tip_worker_v4.ps1','test_channel_v11.ps1','publish_channel_request_v11.ps1','receive_channel_result_v11.ps1')){
  if(-not$seen.ContainsKey((Join-Path $Root ($script:FixedV3Prefix+$leaf)))){throw ('CHANNEL_UNBOUND_CODE:'+$leaf)}
 }
 foreach($leaf in @('config/parallel_receiver.json','scripts/common/CadOperationGuard.psm1','scripts/restore_cad_manual_dialogs_after_exit.ps1','scripts/assert_cad_independent_project_jobs_v3.ps1','reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll')){if(-not$seen.ContainsKey((Join-Path $Root $leaf))){throw ('CHANNEL_UNBOUND_RUNTIME:'+$leaf)}}
}
function Assert-FixedV3Ready($Scope,$Ready,[string]$Root){
 $run=Join-Path $Root ('runs/'+$Scope.run_id);$h=Get-Content -LiteralPath (Join-Path $run 'execution_handoff.json') -Raw|ConvertFrom-Json
 $current=Get-Content -LiteralPath (Join-Path $Root 'config/current_execution_handoff.json') -Raw|ConvertFrom-Json
 $claim=Get-Content -LiteralPath (Join-Path $run 'execution_controller_claim.json') -Raw|ConvertFrom-Json
 if((Test-Path -LiteralPath (Join-Path $run 'execution_return.json'))-or$h.status-cne'READY'-or$current.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$current.run_id-cne$Scope.run_id-or$claim.run_id-cne$Scope.run_id-or-not$claim.controller_attempt_reserved-or$claim.handoff_id-cne$h.handoff_id-or$current.immutable_handoff_sha256-cne(Get-FileHash -LiteralPath (Join-Path $run 'execution_handoff.json')).Hash-or$h.program.scope_sha256-cne$Ready.program.scope_sha256-or$h.program.manifest_sha256-cne$Ready.program.manifest_sha256){throw 'FIXED_V3_READY_CLAIM'}
}




