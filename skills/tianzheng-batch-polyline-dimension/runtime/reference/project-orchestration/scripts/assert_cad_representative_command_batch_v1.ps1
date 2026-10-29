param([Parameter(Mandatory=$true)]$Draft,[Parameter(Mandatory=$true)]$Contract,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Pure admission only: authenticate the sealed closure before importing its
# pure contracts. Native ownership and effect checks remain in the sole executor.
function Resolve-BatchAdmissionPath([string]$Value) {
 if([string]::IsNullOrWhiteSpace($Value)){throw 'BATCH_ADMISSION_EMPTY_PATH'}
 $path=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($Value)){$Value}else{Join-Path $Root $Value}))
 if(-not$path.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BATCH_ADMISSION_PATH_OUTSIDE_PROJECT'}
 $walk=Get-Item -LiteralPath $path
 while($walk.FullName-ine$Root){if($walk.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'BATCH_ADMISSION_REPARSE_PATH'};$parent=[IO.Path]::GetDirectoryName($walk.FullName);if([string]::IsNullOrEmpty($parent)){throw 'BATCH_ADMISSION_PATH_OUTSIDE_PROJECT'};$walk=Get-Item -LiteralPath $parent}
 $path
}
$profile=$Draft.representative_command_batch
$version=[int]$profile.implementation_version
if($profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne$Contract.intent-or$version-notin@(1,2,3)-or$version-notin@($Contract.admitted_implementation_versions)-or$Draft.command_routing.route_id-cne'shared_annotation_interface_read'){throw 'BATCH_ADMISSION_PROFILE'}
if($Draft.issuer.thread_id-cne$Contract.candidate_source_thread_id-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'BATCH_ADMISSION_LANE'}
if($Draft.status-cnotin@('DRAFT','READY')){throw 'BATCH_ADMISSION_NOT_ACTIVE'}
$run=Join-Path $Root ('runs/'+$Draft.run_id)
if(Test-Path -LiteralPath (Join-Path $run 'execution_return.json')){throw 'BATCH_ADMISSION_TERMINAL_RUN'}
$bound=@{}
foreach($property in $Draft.program.PSObject.Properties){
 if($property.Name.EndsWith('_sha256')){continue}
 $hashProperty=$Draft.program.PSObject.Properties[$property.Name+'_sha256']
 if($null-eq$hashProperty){continue}
 $path=Resolve-BatchAdmissionPath ([string]$property.Value)
 $hash=[string]$hashProperty.Value
 if($hash-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-cne$hash){throw ('BATCH_ADMISSION_PROGRAM_HASH:'+ $property.Name)}
 if($bound.ContainsKey($path)-and$bound[$path]-cne$hash){throw 'BATCH_ADMISSION_CONFLICTING_BINDING'}
 $bound[$path]=$hash
}
$scopePath=Resolve-BatchAdmissionPath $profile.scope_path
$manifestPath=Resolve-BatchAdmissionPath $profile.manifest_path
if($scopePath-ine(Join-Path $run 'scope.json')-or$manifestPath-ine(Join-Path $run 'manifest.json')){throw 'BATCH_ADMISSION_RUN_PATH'}
foreach($entry in @(@($scopePath,$profile.scope_sha256),@($manifestPath,$profile.manifest_sha256))){if(-not$bound.ContainsKey($entry[0])-or$bound[$entry[0]]-cne$entry[1]){throw 'BATCH_ADMISSION_SCOPE_MANIFEST_UNBOUND'}}
$scope=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if($scope.run_id-cne$Draft.run_id-or$scope.profile_id-cne$Contract.profile_id-or$scope.phase-cne$Contract.phase-or$manifest.profile_id-cne$Contract.profile_id){throw 'BATCH_ADMISSION_SCOPE_IDENTITY'}
if(($scope.capability_bounds|ConvertTo-Json -Compress)-cne($Contract.candidate_capability_bounds|ConvertTo-Json -Compress)){throw 'BATCH_ADMISSION_CAPS'}
$closure=@{}
foreach($file in $manifest.files){$path=Resolve-BatchAdmissionPath $file.path;if($closure.ContainsKey($path)){throw 'BATCH_ADMISSION_DUPLICATE_FILE'};if(-not$bound.ContainsKey($path)-or$bound[$path]-cne$file.sha256){throw ('BATCH_ADMISSION_MANIFEST_UNBOUND:'+ $file.path)};$closure[$path]=$file.sha256}
$candidate='reports/cad_multi_window_interface_research/representative_command_batch_v'+$version+'/'
foreach($name in @('batch_contract.ps1','command_worker_v1.ps1','invoke_batch.ps1','process_batch.py')){if(-not$closure.ContainsKey((Join-Path $Root ($candidate+$name)))){throw 'BATCH_ADMISSION_REQUIRED_CODE'}}
if((Resolve-BatchAdmissionPath $Draft.program.controller)-ine(Join-Path $Root ($candidate+'invoke_batch.ps1'))){throw 'BATCH_ADMISSION_CONTROLLER'}
# The exact producer/consumer ABI and caps are checked against shared authority;
# the existing lower-level frozen contracts are neither relabeled nor loosened.
. (Join-Path $Root ($candidate+'batch_contract.ps1'))
if($scope.implementation_version-ne$version){throw 'BATCH_ADMISSION_IMPLEMENTATION_MISMATCH'}
if($version-ge2){
 # This is evidence-bound continuation, not a generic resume or write permit.
 $prefix=Join-Path $Root 'runs/20261028_ab_representative_command_batch_v4'
 foreach($item in @(@('execution_return.json','6DCE7E8E1F60367AF51BD40C9594471AFF07A7EBCAE4F89799ACE746C3C915FF'),@('controller_receipt.json','AFB1F859A208E4335A2666BEBF606D593434BF95889637F6830D4416C4D20CB6'))){if((Get-FileHash -LiteralPath (Join-Path $prefix $item[0])).Hash-cne$item[1]){throw 'BATCH_SUFFIX_PREFIX_CHANGED'}}
 $prior=Get-Content (Join-Path $prefix 'controller_receipt.json') -Raw|ConvertFrom-Json -DateKind String
 if($prior.function_pass_count-ne2-or$prior.cleanup_errors.Count-ne0){throw 'BATCH_SUFFIX_PREFIX_NOT_SETTLED'}
 foreach($number in @(1,2)){if($prior.pairs[$number-1].status-cnotlike'PASS_FUNCTION*'){throw 'BATCH_SUFFIX_PREFIX_NOT_PASS'}}
 foreach($owner in @('A','B')){
  $id=$owner+'03';$receipt=Get-Content (Join-Path $prefix ('worker_'+$id+'.json')) -Raw|ConvertFrom-Json -DateKind String
  if($receipt.operation_id-cne$id-or$receipt.status-cne'BLOCKED_BEFORE_SEND'-or$receipt.post_call_count-ne0-or(Test-Path (Join-Path $prefix ('release_'+$id+'.json')))){throw 'BATCH_SUFFIX_PRIOR_SEND_UNSETTLED'}
 }
 if($version-eq2-and(@($scope.operations).Count-ne10-or(@($scope.operations|ForEach-Object id|Sort-Object)-join',')-cne'A03,A04,A05,A06,A07,B03,B04,B05,B06,B07'-or$Draft.action.send_max_count-ne10)){throw 'BATCH_SUFFIX_OPERATION_SET'}
 if(@($scope.operations|Where-Object {$_.owner-ceq'B'-and$_.stage-cin@('DISCOVER','GENERATE')}).Count){throw 'BATCH_SUFFIX_PREFIX_REPLAY'}
}
if($version-eq3){
 $second=Join-Path $Root 'runs/20261028_ab_representative_suffix_v2b'
 foreach($item in @(@('execution_return.json','06BB42694259E04931678E7F19B059A556260EA56465909A25E589D99F3425ED'),@('controller_receipt.json','9620B81BB2C099467DB4B46335F538D158E1104CC275420597B71926A4BA328E'))){if((Get-FileHash -LiteralPath (Join-Path $second $item[0])).Hash-cne$item[1]){throw 'BATCH_FINAL_PREFIX_CHANGED'}}
 $prior=Get-Content (Join-Path $second 'controller_receipt.json') -Raw|ConvertFrom-Json -DateKind String
 if($prior.cleanup_errors.Count-ne0){throw 'BATCH_FINAL_PREFIX_CLEANUP_UNKNOWN'}
 foreach($number in @(3,4)){
  $pair=@($prior.pairs|Where-Object pair -EQ $number)
  if($pair.Count-ne1-or$pair[0].settlement.status-cne'PASS_ALL_ISSUED_WORKERS_SETTLED'-or$pair[0].settlement.total_send_count-ne2){throw 'BATCH_FINAL_NATIVE_PREFIX_UNSETTLED'}
  foreach($owner in @('A','B')){$id=$owner+('{0:00}'-f$number);$w=Get-Content (Join-Path $second ('worker_'+$id+'.json')) -Raw|ConvertFrom-Json -DateKind String;if($w.operation_id-cne$id-or$w.status-cne'PASS'-or$w.post_call_count-ne1-or-not$w.send_call_returned-or$w.native_evidence.status-cne'PASS'){throw 'BATCH_FINAL_WORKER_UNSETTLED'}}
 }
 foreach($number in @(5,6,7)){
  $pair=@($prior.pairs|Where-Object pair -EQ $number)
  if($pair.Count-ne1-or$pair[0].status-cne'SKIPPED_DEPENDENCY_OR_UNKNOWN__NO_SEND'){throw 'BATCH_FINAL_PRIOR_TAIL_SENT'}
  foreach($owner in @('A','B')){$id=$owner+('{0:00}'-f$number);foreach($prefixName in @('release_','send_reservation_','exact_b_send_')){if(Test-Path (Join-Path $second ($prefixName+$id+'.json'))){throw 'BATCH_FINAL_PRIOR_TAIL_SENT'}}}
 }
 if(@($scope.operations).Count-ne6-or(@($scope.operations|ForEach-Object id|Sort-Object)-join',')-cne'A05,A06,A07,B05,B06,B07'-or$Draft.action.send_max_count-ne6){throw 'BATCH_FINAL_OPERATION_SET'}
 if(@($scope.operations|Where-Object {$_.owner-ceq'B'-and$_.stage-cnotin@('FINAL_METRICS','VISUAL','CHECKPOINT')}).Count){throw 'BATCH_FINAL_WRITE_OR_PREFIX_REPLAY'}
}
& ('Assert-CadRepresentativeBatchAdmissionV'+$version) $Root
$null=& ('Assert-CadRepresentativeCommandBatchScopeV'+$version) $scope $Root
& ('Assert-CadRepresentativeBatchManifestV'+$version) $manifest $Root
& ('Assert-CadRepresentativeBatchDraftV'+$version) $Draft $scope $Root
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;operations=@($scope.operations).Count;manifest_files=$closure.Count;cad_calls=0;live_result='UNVERIFIED'}
