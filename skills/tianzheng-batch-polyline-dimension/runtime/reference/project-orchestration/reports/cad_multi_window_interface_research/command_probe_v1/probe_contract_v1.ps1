. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/lifecycle_v1/preparation_contract_v1.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/v3/cad_multi_owner_preflight_contract_v3.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'scripts/cad_command_signal_parser_v3.ps1')
function Assert-CadProbeAlternatingPredecessorV1($Return,$Receipt,$Owners) {
    if($Return.workflow_id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$Return.terminal_state-cne'CONTROLLER_REPORTED_PASS_ALTERNATING_NONDB_PROBE__EVIDENCE_REVIEW_REQUIRED'){throw 'PROBE_PRIOR_ALTERNATING_RETURN_NOT_PASS'}
    if($Receipt.run_id-cne$Return.run_id-or$Receipt.profile_id-cne$Return.workflow_id-or$Receipt.status-cne'PASS_ALTERNATING_NONDB_PROBE'-or$Receipt.phase-cne'ALTERNATING'){throw 'PROBE_PRIOR_ALTERNATING_NOT_PASS'}
    if(($Receipt.scope_owners|ConvertTo-Json -Depth 8 -Compress)-cne($Owners|ConvertTo-Json -Depth 8 -Compress)){throw 'PROBE_PRIOR_ALTERNATING_OWNER_CHANGED'}
}
function Assert-CadProbeScopeV1($Scope,[string]$Root,[string]$RunDirectory,[switch]$AllowStartedSiblingSignals) {
    if($Scope.schema_version-ne1-or$Scope.profile_id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$Scope.intent-cne'ExecuteNonDbProbe'){throw 'PROBE_SCOPE_IDENTITY'}
    if($Scope.phase-cnotin@('ALTERNATING','OVERLAP')){throw 'PROBE_PHASE'}
    $run=Assert-CadPreparationPathV1 $RunDirectory $Root
    if($Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'-or$run-ine(Join-Path (Join-Path $Root 'runs') $Scope.run_id)){throw 'PROBE_RUN_PATH'}
    $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
    if($identity.owners.Count-ne2){throw 'PROBE_TWO_OWNERS_REQUIRED'}
    foreach($owner in $identity.owners){if([long]$owner.window_handle-gt[uint32]::MaxValue){throw 'PROBE_HWND_OUTSIDE_NATIVE_UINT32'}}
    if(($Scope.worker_timeout_seconds-isnot[int]-and$Scope.worker_timeout_seconds-isnot[long])-or$Scope.worker_timeout_seconds-lt10-or$Scope.worker_timeout_seconds-gt30){throw 'PROBE_WORKER_DEADLINE'}
    $prior=Assert-CadPreparationPathV1 ([string]$Scope.prior_read_return_path) $Root
    if($Scope.prior_read_return_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $prior).Hash-cne$Scope.prior_read_return_sha256){throw 'PROBE_PRIOR_READ_HASH'}
    $priorData=Read-CadPreparationScopeV1 $prior
    if($priorData.workflow_id-cne'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1'-or$priorData.terminal_state-cne'CONTROLLER_REPORTED_PASS_READ_PROBE_ONLY__EVIDENCE_REVIEW_REQUIRED'){throw 'PROBE_PRIOR_READ_NOT_PASS'}
    $priorScopePath=Assert-CadPreparationPathV1 ([string]$Scope.prior_read_scope_path) $Root
    if($Scope.prior_read_scope_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $priorScopePath).Hash-cne$Scope.prior_read_scope_sha256-or$priorData.controller_report.scope_sha256-cne$Scope.prior_read_scope_sha256){throw 'PROBE_PRIOR_READ_SCOPE_HASH'}
    $priorScope=Read-CadPreparationScopeV1 $priorScopePath
    if($priorScope.run_id-cne$priorData.run_id){throw 'PROBE_PRIOR_READ_SCOPE_RUN'}
    foreach($owner in $identity.owners){
        $priorOwner=@($priorScope.owners|Where-Object {$_.id-ceq$owner.id})
        if($priorOwner.Count-ne1){throw 'PROBE_PRIOR_READ_OWNER_MISSING'}
        foreach($field in @('id','scope_kind','process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$owner.$field-cne[string]$priorOwner[0].$field){throw ('PROBE_PRIOR_READ_OWNER_CHANGED:'+ $field)}}
    }
    $wanted=if($Scope.phase-ceq'ALTERNATING'){'A,B,A'}else{'A,B'}
    $ops=@($Scope.operations)
    if(($ops.owner-join',')-cne$wanted){throw 'PROBE_OPERATION_ORDER'}
    $ids=@{};$nonces=@{}
    foreach($op in $ops){
        if($op.id-cnotmatch'^[AB][1-9][0-9]{0,2}$'-or-not$op.id.StartsWith($op.owner,[StringComparison]::Ordinal)-or$ids.ContainsKey($op.id)-or$op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$nonces.ContainsKey($op.nonce)){throw 'PROBE_OPERATION_ID_NONCE'}
        $ids[$op.id]=$true;$nonces[$op.nonce]=$true
        if(($op.duration_ms-isnot[int]-and$op.duration_ms-isnot[long])-or($Scope.phase-ceq'ALTERNATING'-and$op.duration_ms-ne0)-or($Scope.phase-ceq'OVERLAP'-and($op.duration_ms-lt3000-or$op.duration_ms-gt8000))){throw 'PROBE_DURATION'}
        $path=Assert-CadPreparationPathV1 ([string]$op.signal_path) $Root
        if($path-ine(Join-Path $run ('signals/'+$op.id+'.log'))-or(-not$AllowStartedSiblingSignals-and(Test-Path -LiteralPath $path))){throw 'PROBE_SIGNAL_PATH_EXISTS_OR_UNSAFE'}
    }
    if($Scope.phase-ceq'OVERLAP'){
        $altReturnPath=Assert-CadPreparationPathV1 ([string]$Scope.prior_alternating_return_path) $Root
        if($Scope.prior_alternating_return_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $altReturnPath).Hash-cne$Scope.prior_alternating_return_sha256){throw 'PROBE_PRIOR_ALTERNATING_RETURN_HASH'}
        $altReturn=Read-CadPreparationScopeV1 $altReturnPath
        if($altReturnPath-ine(Join-Path $Root ('runs/'+$altReturn.run_id+'/execution_return.json'))){throw 'PROBE_PRIOR_ALTERNATING_RETURN_PATH'}
        $alt=Assert-CadPreparationPathV1 ([string]$Scope.prior_alternating_receipt_path) $Root
        if($Scope.prior_alternating_receipt_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $alt).Hash-cne$Scope.prior_alternating_receipt_sha256-or$altReturn.controller_report_sha256-cne$Scope.prior_alternating_receipt_sha256-or$alt-ine(Join-Path $Root ('runs/'+$altReturn.run_id+'/controller_receipt.json'))){throw 'PROBE_PRIOR_ALTERNATING_HASH'}
        $a=Read-CadPreparationScopeV1 $alt
        Assert-CadProbeAlternatingPredecessorV1 $altReturn $a $Scope.owners
    }
    [pscustomobject]@{run=$run;run_id=$Scope.run_id;phase=$Scope.phase;identity=$identity;operations=$ops;worker_timeout_seconds=$Scope.worker_timeout_seconds}
}
function Assert-CadProbeDependenciesV1([string]$Directory,[string]$Root) {
    $manifest=Read-CadPreparationScopeV1 (Join-Path $Directory 'candidate_manifest.json')
    if($manifest.id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'){throw 'PROBE_MANIFEST_IDENTITY'}
    foreach($file in $manifest.files){$path=Assert-CadPreparationPathV1 (Join-Path $Root $file.path) $Root;if((Get-FileHash -LiteralPath $path).Hash-cne$file.sha256){throw ('PROBE_DEPENDENCY_CHANGED:'+ $file.path)}}
}
function ConvertTo-CadProbeLispStringV1([string]$Value) {'"'+$Value.Replace('\','\\').Replace('"','\"')+'"'}
function Read-CadProbeControlFileV1([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    try{$raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop;if([string]::IsNullOrWhiteSpace($raw)){return $null};$raw|ConvertFrom-Json -DateKind String -ErrorAction Stop}catch{return $null}
}
function New-CadProbeExpressionV1($Scope,$Operation,$Owner) {
    $text=@'
(progn (vl-load-com) ((lambda (/ app doc hwnd fullname before count0 start now elapsed loops stream emit)
 (setq app (vlax-get-acad-object) doc (vla-get-ActiveDocument app)
       hwnd (rem (+ (vla-get-HWND app) 4294967296.0) 4294967296.0)
       fullname (vla-get-FullName doc))
 (if (and (= hwnd @HWND@) (= (strcase fullname) (strcase @DRAWING@)))
  (progn
   (setq before (getvar "DBMOD") count0 (vla-get-Count (vla-get-ModelSpace doc)))
   (setq emit (lambda (stage tick / stream)
    (setq stream (open @SIGNAL@ "a"))
    (if stream (progn
     (write-line (strcat "CX_CAD_SIGNAL_V1|CAD_COMMAND_" stage "|" (rtos tick 2 0)) stream)
     (write-line (strcat "CX_MULTI_OWNER_PROBE_V1|@NONCE@|@RUN@|@OP@|@OWNER@|" (rtos hwnd 2 0) "|" stage "|" (rtos tick 2 0) "|" (itoa (getvar "DBMOD")) "|" (itoa (vla-get-Count (vla-get-ModelSpace doc)))) stream)
     (close stream)))))
   (setq start (rem (+ (getvar "MILLISECS") 4294967296.0) 4294967296.0) elapsed 0 loops 0)
   (apply emit (list "ACK" start))
   (while (and (< elapsed @DURATION@) (< loops 20000000))
    (setq now (rem (+ (getvar "MILLISECS") 4294967296.0) 4294967296.0)
          elapsed (rem (+ (- now start) 4294967296.0) 4294967296.0) loops (1+ loops)))
   (if (and (= before (getvar "DBMOD")) (= count0 (vla-get-Count (vla-get-ModelSpace doc))) (>= elapsed @DURATION@)
            (= hwnd (rem (+ (vla-get-HWND app) 4294967296.0) 4294967296.0)) (= (strcase fullname) (strcase (vla-get-FullName doc))))
    (apply emit (list "COMPLETE" (rem (+ (getvar "MILLISECS") 4294967296.0) 4294967296.0)))
    (princ "CX_MULTI_OWNER_PROBE_FAILED_AFTER_ACK")))
  (princ "CX_MULTI_OWNER_PROBE_WRONG_NATIVE_OWNER")))) (princ))
'@
    $replacements=@{HWND=[string]$Owner.window_handle;DRAWING=(ConvertTo-CadProbeLispStringV1 $Owner.document_full_path);SIGNAL=(ConvertTo-CadProbeLispStringV1 $Operation.signal_path);NONCE=$Operation.nonce;RUN=$Scope.run_id;OP=$Operation.id;OWNER=$Operation.owner;DURATION=[string]$Operation.duration_ms}
    foreach($key in $replacements.Keys){$text=$text.Replace('@'+$key+'@',[string]$replacements[$key])}
    if($text-match'@[A-Z]+@'){throw 'PROBE_EXPRESSION_UNBOUND_TOKEN'}
    $text.Replace("`r`n","`n").Replace("`r","`n").Replace("`n"," ")+"`r"
}
function Read-CadProbeEvidenceV1([string]$Path,$Scope,$Operation,$Owner) {
    if(-not(Test-Path -LiteralPath $Path)){return [pscustomobject]@{status='PENDING';rows=@()}}
    try{$raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop}catch{return [pscustomobject]@{status='PENDING';rows=@()}}
    if([string]::IsNullOrEmpty($raw)-or-not$raw.EndsWith("`n")){return [pscustomobject]@{status='PENDING';rows=@()}}
    $signal=Read-CadCommandSignalResultV3 -Path $Path
    $typed=@($signal.lines|Where-Object {$_-like'CX_MULTI_OWNER_PROBE_V1|*'})
    $rows=@()
    foreach($line in $typed){
        $f=$line.Split('|')
        if($f.Count-ne10-or$f[1]-cne$Operation.nonce-or$f[2]-cne$Scope.run_id-or$f[3]-cne$Operation.id-or$f[4]-cne$Operation.owner-or$f[5]-cne[string]$Owner.window_handle-or$f[6]-cnotin@('ACK','COMPLETE')){throw 'PROBE_SIGNAL_IDENTITY'}
        foreach($i in @(7,8,9)){if($f[$i]-cnotmatch'^[0-9]+$'){throw 'PROBE_SIGNAL_NUMBER'}}
        if([decimal]$f[7]-gt[uint32]::MaxValue-or[decimal]$f[8]-gt[int]::MaxValue-or[decimal]$f[9]-gt[int]::MaxValue){throw 'PROBE_SIGNAL_RANGE'}
        $rows+=[pscustomobject]@{stage=$f[6];tick=[long]$f[7];dbmod=[int]$f[8];model_count=[int]$f[9]}
    }
    if($rows.Count-gt2-or($rows.Count-eq1-and$rows[0].stage-cne'ACK')-or($rows.Count-eq2-and($rows.stage-join',')-cne'ACK,COMPLETE')){throw 'PROBE_SIGNAL_ORDER_OR_DUPLICATE'}
    if($rows.Count-ne2){return [pscustomobject]@{status='PENDING';rows=$rows}}
    if($signal.lines.Count-ne4){throw 'PROBE_SIGNAL_UNEXPECTED_LINES'}
    foreach($token in @('CAD_COMMAND_ACK','CAD_COMMAND_COMPLETE')){if(@(Get-CadCommandSignalV3 -Lines $signal.lines -Token $token).Count-ne1){throw 'PROBE_OBSERVER_TOKEN_NOT_UNIQUE'}}
    $ack=@(Get-CadCommandSignalV3 -Lines $signal.lines -Token CAD_COMMAND_ACK)[0];$complete=@(Get-CadCommandSignalV3 -Lines $signal.lines -Token CAD_COMMAND_COMPLETE)[0]
    if([long]$ack.timestamp-ne$rows[0].tick-or[long]$complete.timestamp-ne$rows[1].tick){throw 'PROBE_OBSERVER_NATIVE_STAMP_CONFLICT'}
    $elapsed=($rows[1].tick-$rows[0].tick+4294967296L)%4294967296L
    if($elapsed-lt$Operation.duration_ms-or$elapsed-gt15000-or$rows[0].dbmod-ne$rows[1].dbmod-or$rows[0].model_count-ne$rows[1].model_count){throw 'PROBE_DURATION_OR_DATABASE_DIAGNOSTIC_CHANGED'}
    [pscustomobject]@{status='PASS';operation_id=$Operation.id;owner=$Operation.owner;nonce=$Operation.nonce;ack_tick=$rows[0].tick;complete_tick=$rows[1].tick;elapsed_ms=$elapsed;dbmod=$rows[0].dbmod;model_count=$rows[0].model_count;native_identity_checked=$true;clock='MILLISECS_U32_SYSTEM_BOOT_GETTICKCOUNT'}
}
function Measure-CadProbeOverlapV1($A,$B) {
    $aEnd=($A.complete_tick-$A.ack_tick+4294967296L)%4294967296L
    $bStart=($B.ack_tick-$A.ack_tick+4294967296L)%4294967296L;if($bStart-gt2147483647L){$bStart-=4294967296L}
    $bDuration=($B.complete_tick-$B.ack_tick+4294967296L)%4294967296L
    if($aEnd-lt0-or$aEnd-gt15000-or$bDuration-lt0-or$bDuration-gt15000-or[math]::Abs($bStart)-gt30000){throw 'PROBE_CLOCK_INTERVAL_UNSAFE'}
    $overlap=[math]::Max(0,[math]::Min($aEnd,$bStart+$bDuration)-[math]::Max(0,$bStart))
    [pscustomobject]@{overlap_ms=$overlap;overlap_proven=($overlap-ge100);clock='MILLISECS_U32_SYSTEM_BOOT_GETTICKCOUNT';minimum_proof_ms=100}
}
