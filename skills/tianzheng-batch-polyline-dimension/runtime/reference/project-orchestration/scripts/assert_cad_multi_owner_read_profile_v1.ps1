param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function ProfilePath([string]$Value) {
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not $path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'MULTI_OWNER_PATH_OUTSIDE_PROJECT'}
    $path
}
function ProfileHash([string]$Path) {(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function AssertReadNoReparse([string]$Path){
    $ancestor=$Path
    while($ancestor.Length-gt$Root.Length){
        if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'MULTI_OWNER_CANDIDATE_REPARSE'}
        $ancestor=Split-Path -Parent $ancestor
    }
}
function AssertReadCapabilities($Actual,$Expected){
    foreach($p in $Expected.PSObject.Properties){
        $a=$Actual.PSObject.Properties[$p.Name]
        if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or
            ($a.Value|ConvertTo-Json -Compress -Depth 5)-cne($p.Value|ConvertTo-Json -Compress -Depth 5)){throw ('MULTI_OWNER_CANDIDATE_CAPABILITY:'+ $p.Name)}
    }
    if(@($Actual.PSObject.Properties).Count-ne@($Expected.PSObject.Properties).Count){throw 'MULTI_OWNER_CANDIDATE_CAPABILITY_EXTRA'}
}
function AssertArmSetupUiaAnchorEvidence($Scope,$Bindings,[string]$ExecutorThreadId){
    # The arm producer has an independently persisted setup sidecar; it does
    # not have a completed worker receipt. Validate that real shape, not a
    # fabricated legacy worker or a claim that the queued command executed.
    $data=@{};$paths=@{}
    foreach($name in @('prior_return','prior_scope','prior_controller','setup_receipt','prior_raw','anchor_evidence','prior_roles')){
        $path=ProfilePath $Scope.($name+'_path');AssertReadNoReparse $path
        $hash=$Scope.($name+'_sha256')
        if($hash-isnot[string]-or$hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-Item -LiteralPath $path).Length-gt1048576-or
            (ProfileHash $path)-cne$hash-or-not$Bindings.ContainsKey($path)-or$Bindings[$path]-cne$hash){throw 'MULTI_OWNER_UIA_ARM_SOURCE_BINDING'}
        $paths[$name]=$path
        if($name-cne'prior_raw'){$data[$name]=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}
    }
    $r=$data.prior_return;$s=$data.prior_scope;$c=$data.prior_controller;$p=$data.setup_receipt
    if($r.run_id-cne$s.run_id-or$r.run_id-ceq$Scope.run_id-or$r.writer.thread_id-cne$ExecutorThreadId-or
        $c.run_id-cne$r.run_id-or$c.scope_sha256-cne$Scope.prior_scope_sha256-or$s.profile_id-cne'CAD-EXISTING-B-DOCUMENT-ARM-BACKGROUND-READ-V1'-or
        $c.profile_id-cne$s.profile_id-or$c.status-cne'WORKER_EFFECT_UNKNOWN'-or$c.reason-cne'ARM_SETUP_NATIVE_PARENT_HARD_DEADLINE_15S'-or
        $null-ne$c.worker_receipt-or$c.protected_hashes_after-cne'UNCHANGED'-or$r.terminal_state-cne'CONTROLLER_EXCEPTION__EVIDENCE_PRESERVED__NO_RETRY'-or
        (ProfilePath $r.controller_report_path)-ine$paths.prior_controller-or$r.controller_report_sha256-cne$Scope.prior_controller_sha256){throw 'MULTI_OWNER_UIA_ARM_RETURN_CHAIN'}
    $left=$r.controller_report|ConvertTo-Json -Depth 30|ConvertFrom-Json -DateKind String
    $right=$c|ConvertTo-Json -Depth 30|ConvertFrom-Json -DateKind String
    # One observed envelope serialization difference: UTC versus local offset.
    foreach($value in @($left,$right)){$value.setup_observation.phase.enter_utc=([DateTimeOffset]::Parse($value.setup_observation.phase.enter_utc,[Globalization.CultureInfo]::InvariantCulture)).UtcDateTime.ToString('o')}
    if(($left|ConvertTo-Json -Depth 30 -Compress)-cne($right|ConvertTo-Json -Depth 30 -Compress)){throw 'MULTI_OWNER_UIA_ARM_CONTROLLER_EMBEDDING'}
    foreach($field in @('job_bound_before_resume','root_exited','own_stop_attempted','output_complete')){
        if($c.helper.$field-isnot[bool]-or-not$c.helper.$field){throw 'MULTI_OWNER_UIA_ARM_HELPER_SETTLEMENT'}
    }
    if($c.helper.exit_code-ne124-or$c.helper.active-ne0){throw 'MULTI_OWNER_UIA_ARM_HELPER_SETTLEMENT'}
    $priorRun=ProfilePath ('runs/'+$r.run_id)
    foreach($pair in @(@('prior_return','execution_return.json'),@('prior_controller','controller_receipt.json'),@('setup_receipt','setup_uia_receipt.json'),@('prior_raw','setup_command_raw.jsonl'),@('anchor_evidence','current_native_anchor.json'),@('prior_roles','current_uia_roles.json'))){
        if($paths[$pair[0]]-ine(Join-Path $priorRun $pair[1])){throw 'MULTI_OWNER_UIA_ARM_PRODUCER_PATH'}
    }
    if($p.run_id-cne$r.run_id-or$p.nonce-cne$s.nonce-or(ProfilePath $p.raw_path)-ine$paths.prior_raw-or$p.raw_sha256-cne$Scope.prior_raw_sha256-or
        $p.actual_focus_count-ne1-or$p.actual_replace_count-ne1-or$p.actual_queue_submit_count-ne1-or$p.clear_count-ne0-or$p.retry_count-ne0-or
        $p.native_arm_proven-isnot[bool]-or$p.native_arm_proven-or$p.result.queue_receipt.api-cne'PostMessageW'-or
        $p.result.queue_receipt.request_queued-isnot[bool]-or-not$p.result.queue_receipt.request_queued-or
        $p.result.queue_receipt.message-ne258-or$p.result.queue_receipt.wparam-ne13-or$p.result.queue_receipt.lparam-ne1){throw 'MULTI_OWNER_UIA_ARM_SIDECAR_CHAIN'}
    if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($s.owners|ConvertTo-Json -Depth 8 -Compress)-or
        $Scope.source_path-cne$s.source_path-or$Scope.source_sha256-cne$s.source_sha256){throw 'MULTI_OWNER_UIA_ARM_OWNER_CHANGED'}
    if(($Scope.native_anchor|ConvertTo-Json -Depth 15 -Compress)-cne($data.anchor_evidence|ConvertTo-Json -Depth 15 -Compress)-or
        ($Scope.bound_uia_roles|ConvertTo-Json -Depth 12 -Compress)-cne($data.prior_roles|ConvertTo-Json -Depth 12 -Compress)){throw 'MULTI_OWNER_UIA_ARM_ACTUAL_EVIDENCE'}
    $raw=@(Get-Content -LiteralPath $paths.prior_raw -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json -DateKind String})
    foreach($part in $Scope.native_anchor.chain){
        $rows=@($raw|Where-Object {$_.kind-ceq'CURRENT_B_CLI_CANDIDATE'-and$_.native.hwnd-eq$part.native.hwnd})
        if($rows.Count-ne1-or($rows[0].native|ConvertTo-Json -Depth 8 -Compress)-cne($part.native|ConvertTo-Json -Depth 8 -Compress)-or$rows[0].text-cne$part.text){throw 'MULTI_OWNER_UIA_ARM_RAW_ANCHOR'}
    }
    foreach($name in @('root','parent','target','prompt')){
        $role=$Scope.bound_uia_roles.$name
        $rows=@($raw|Where-Object {$_.kind-ceq'UIA_ROW'-and$_.before.runtime_id-ceq$role.runtime_id})
        $side=@($p.collection.rows|Where-Object {$_.before.runtime_id-ceq$role.runtime_id})
        if($rows.Count-ne1-or$side.Count-ne1-or($rows[0].before|ConvertTo-Json -Depth 8 -Compress)-cne($role|ConvertTo-Json -Depth 8 -Compress)-or
            ($side[0]|ConvertTo-Json -Depth 12 -Compress)-cne($rows[0]|ConvertTo-Json -Depth 12 -Compress)-or
            $rows[0].read_complete-isnot[bool]-or-not$rows[0].read_complete-or$rows[0].identity_stable-isnot[bool]-or-not$rows[0].identity_stable-or
            $role.process_id-ne$Scope.owners[1].process_id){throw 'MULTI_OWNER_UIA_ARM_ROLE_PROVENANCE'}
    }
    $roles=$Scope.bound_uia_roles
    if($roles.root.native_window_handle-ne$Scope.native_anchor.surface_handle-or$roles.parent.parent_runtime_id-cne$roles.root.runtime_id-or$roles.parent.class_name-cne'CommandLineControl'-or
        $roles.target.parent_runtime_id-cne$roles.parent.runtime_id-or$roles.target.class_name-cne'TextBox'-or$roles.target.automation_id-cne'local:AutoCompleteEdit_1'-or
        $roles.prompt.parent_runtime_id-cne$roles.parent.runtime_id-or$roles.prompt.class_name-cne'TextBlock'-or$roles.prompt.name-cne'键入命令'){throw 'MULTI_OWNER_UIA_ARM_ROLE_CHAIN'}
    if($Scope.projection_mode-cne'COMMAND_ROOT_DIRECT_CHILDREN_ONLY'-or$Scope.projection_depth-ne2-or
        $Scope.late_signal_directory-cne$s.stage_directory-or$Scope.late_signal_read_max-ne2-or$Scope.expected_pending_expression_sha256-cne$s.expression_sha256-or
        $Scope.native_input_buffer_observable-isnot[bool]-or$Scope.native_input_buffer_observable-or$null-ne$Scope.PSObject.Properties['history_target']){throw 'MULTI_OWNER_UIA_ARM_READ_SCOPE'}
}
function AssertCurrentBUiaAnchorEvidence($Scope,$Bindings,[string]$ExecutorThreadId){
    if($null-ne$Scope.PSObject.Properties['evidence_producer']){
        if($Scope.evidence_producer-cne'EXISTING_B_ARM_SETUP_SIDECAR_V1'){throw 'MULTI_OWNER_UIA_EVIDENCE_PRODUCER_UNKNOWN'}
        AssertArmSetupUiaAnchorEvidence $Scope $Bindings $ExecutorThreadId
        return
    }
    # Current native JSON is a second producer format, not permission to trust
    # an old fresh=true flag. Bind it to its actual terminal return and raw log.
    $data=@{};$paths=@{}
    foreach($name in @('prior_return','prior_scope','prior_raw','anchor_evidence','prior_roles')){
        $path=ProfilePath $Scope.($name+'_path');AssertReadNoReparse $path
        $hash=$Scope.($name+'_sha256')
        if($hash-isnot[string]-or$hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-Item -LiteralPath $path).Length-gt1048576-or
            (ProfileHash $path)-cne$hash-or-not$Bindings.ContainsKey($path)-or$Bindings[$path]-cne$hash){throw 'MULTI_OWNER_UIA_CURRENT_SOURCE_BINDING'}
        $paths[$name]=$path
        if($name-cne'prior_raw'){$data[$name]=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}
    }
    $returned=$data.prior_return;$previous=$data.prior_scope;$controller=$returned.controller_report;$worker=$controller.worker_receipt
    if($returned.run_id-cne$previous.run_id-or$returned.run_id-ceq$Scope.run_id-or
        $returned.writer.thread_id-cne$ExecutorThreadId-or$controller.run_id-cne$returned.run_id-or$worker.run_id-cne$returned.run_id-or
        $controller.profile_id-cne'CAD-EXACT-B-FIXED-READ-COMMAND-V1'-or$worker.scope_sha256-cne$Scope.prior_scope_sha256-or
        $controller.status-cne'UNKNOWN_OR_UNSETTLED_COMMAND_EFFECT'-or$controller.protected_hashes_after-cne'UNCHANGED'-or
        $controller.helper_phase.root_exit_code-ne0-or$controller.helper_phase.job_active_after-ne0-or
        -not$controller.helper_phase.output_complete-or$controller.helper_phase.own_job_stop_attempted-or$controller.helper_phase.reason){throw 'MULTI_OWNER_UIA_CURRENT_RETURN_CHAIN'}
    $priorRun=ProfilePath ('runs/'+$returned.run_id)
    foreach($pair in @(@('prior_return','execution_return.json'),@('prior_raw','command_raw.jsonl'),@('anchor_evidence','current_native_anchor.json'),@('prior_roles','current_uia_roles.json'))){
        if($paths[$pair[0]]-ine(Join-Path $priorRun $pair[1])){throw 'MULTI_OWNER_UIA_CURRENT_PRODUCER_PATH'}
    }
    if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($previous.owners|ConvertTo-Json -Depth 8 -Compress)-or
        $Scope.source_path-cne$previous.source_path-or$Scope.source_sha256-cne$previous.source_sha256-or
        (ProfilePath $worker.raw_evidence_path)-ine$paths.prior_raw-or$worker.raw_evidence_sha256-cne$Scope.prior_raw_sha256){throw 'MULTI_OWNER_UIA_CURRENT_OWNER_OR_RAW'}
    $anchor=$Scope.native_anchor
    if(($anchor|ConvertTo-Json -Depth 15 -Compress)-cne($data.anchor_evidence|ConvertTo-Json -Depth 15 -Compress)-or
        ($Scope.bound_uia_roles|ConvertTo-Json -Depth 12 -Compress)-cne($data.prior_roles|ConvertTo-Json -Depth 12 -Compress)){throw 'MULTI_OWNER_UIA_CURRENT_ACTUAL_EVIDENCE'}
    $beforeUia=@(Get-Content -LiteralPath $paths.prior_raw -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json -DateKind String}|Where-Object kind -CEQ 'BEFORE_UIA')
    if($beforeUia.Count-ne1-or($beforeUia[0].native_anchor|ConvertTo-Json -Depth 15 -Compress)-cne($anchor|ConvertTo-Json -Depth 15 -Compress)){throw 'MULTI_OWNER_UIA_CURRENT_RAW_ANCHOR'}
    foreach($role in @($Scope.bound_uia_roles.root,$Scope.bound_uia_roles.parent,$Scope.bound_uia_roles.buffer_target,$Scope.history_target)){
        $rows=@($worker.collection.rows|Where-Object {$_.before.runtime_id-ceq$role.runtime_id})
        if($rows.Count-ne1-or($rows[0].before|ConvertTo-Json -Depth 8 -Compress)-cne($role|ConvertTo-Json -Depth 8 -Compress)-or
            $role.process_id-ne$Scope.owners[1].process_id){throw 'MULTI_OWNER_UIA_CURRENT_ROLE_PROVENANCE'}
    }
    if($Scope.bound_uia_roles.root.native_window_handle-ne$anchor.surface_handle-or
        $Scope.bound_uia_roles.parent.parent_runtime_id-cne$Scope.bound_uia_roles.root.runtime_id-or
        $Scope.bound_uia_roles.parent.class_name-cne'CommandLineControl'-or
        $Scope.bound_uia_roles.buffer_target.parent_runtime_id-cne$Scope.bound_uia_roles.parent.runtime_id-or
        $Scope.bound_uia_roles.buffer_target.class_name-cne'TextBox'-or$Scope.bound_uia_roles.buffer_target.automation_id-cne'local:AutoCompleteEdit_1'-or
        $Scope.history_target.parent_runtime_id-cne$Scope.bound_uia_roles.parent.runtime_id-or
        $Scope.history_target.class_name-cne'HistoryViewer'-or$Scope.history_target.automation_id-cne'local:HistoryViewer_2'){throw 'MULTI_OWNER_UIA_CURRENT_ROLE_CHAIN'}
    if($Scope.projection_mode-cne'COMMAND_OUTLINE_WITH_ONE_BOUND_HISTORY_BRANCH'-or$Scope.projection_depth-ne8-or
        (ProfilePath $Scope.late_signal_path)-ine(ProfilePath $previous.command_receipt_path)-or$Scope.late_signal_read_max-ne2-or
        $Scope.expected_pending_expression_sha256-cne$previous.expression_sha256){throw 'MULTI_OWNER_UIA_CURRENT_READ_SCOPE'}
}
function AssertCurrentBStateDiagnostic($Scope,$Policy,$Manifest,$Bindings){
    # A run is bound by its sealed scope, literal invocation and private contract.
    # Shared authority describes capabilities and provenance, not one run name.
    if($Scope.diagnostic_variant-cne$Policy.diagnostic_variant-or$Scope.run_id-isnot[string]-or
        $Scope.run_id-cnotmatch'\A[A-Za-z0-9_]{1,100}\z'-or$Scope.candidate_version-ne$Policy.implementation_version-or
        $Scope.projection_mode-cne'COMMAND_ROOT_DIRECT_CHILDREN_ONLY'-or$Scope.projection_depth-ne2-or
        $Scope.nonce-isnot[string]-or$Scope.nonce-cnotmatch'\A[a-f0-9]{32}\z'-or
        $null-ne$Scope.native_anchor-or$null-ne$Scope.buffer_target-or$null-ne$Scope.ready_prompt){throw 'MULTI_OWNER_STATE_DIAGNOSTIC_SCOPE'}
    $receiptPath=ProfilePath $Scope.command_receipt_path;AssertReadNoReparse $receiptPath
    if($receiptPath-ine(Join-Path $Root ('runs/'+$Scope.run_id+'/cad_b_'+$Scope.nonce+'.txt'))-or(Test-Path -LiteralPath $receiptPath)){throw 'MULTI_OWNER_STATE_DIAGNOSTIC_OUTPUT'}
    if($Scope.transport.focus_reason-isnot[string]-or[string]::IsNullOrWhiteSpace($Scope.transport.focus_reason)-or$Scope.transport.focus_reason.Length-gt512){throw 'MULTI_OWNER_COMMAND_FOCUS_REASON'}
    $transport=[pscustomobject]@{api='SendMessageTimeoutW';receiver='CURRENT_RUN_EXACT_B_WPF_SURFACE_ONLY';surface_handle=0;message=258;wparam=13;lparam=1;flags=35;timeout_ms=500;max_submit_calls=1;focus_api='AutomationElement.SetFocus';max_focus_calls=1;focus_reason=$Scope.transport.focus_reason}
    AssertReadCapabilities $Scope.transport ($transport|ConvertTo-Json -Compress|ConvertFrom-Json)
    $expressionPath=ProfilePath $Policy.expression_contract_path;AssertReadNoReparse $expressionPath
    if((ProfileHash $expressionPath)-cne$Policy.expression_contract_sha256-or-not$Bindings.ContainsKey($expressionPath)-or
        $Bindings[$expressionPath]-cne$Policy.expression_contract_sha256-or
        @($Manifest.files|Where-Object{(ProfilePath $_.path)-ieq$expressionPath-and$_.sha256-ceq$Policy.expression_contract_sha256}).Count-ne1){throw 'MULTI_OWNER_COMMAND_EXPRESSION_CONTRACT'}
    $expression=& {param($Path,$InputScope) . $Path;New-CadExactBExpressionV1 $InputScope} $expressionPath $Scope
    $expressionHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($expression)))
    if($Scope.command_text-isnot[string]-or$Scope.command_text-match'[\x00\r\n]'-or$Scope.command_text.Length-gt3500-or
        $Scope.command_text-cne$expression-or$Scope.expression_sha256-cne$expressionHash){throw 'MULTI_OWNER_COMMAND_EXPRESSION'}
    $fixed=@{
        prior_return_path='runs/20261028_b_document_job_membership_68/execution_return.json'
        prior_scope_path='reports/cad_multi_window_interface_research/b_document_bridge_background_v3/runtime/20261028_b_document_job_membership_68/scope.json'
        prior_native_ready_path='runs/20261028_b_document_job_membership_68/bridge_evidence/bridge_identity_ready.json'
        prior_revoked_path='runs/20261028_b_document_job_membership_68/bridge_evidence/bridge_revoked.json'
    }
    $prior=@{}
    foreach($name in $fixed.Keys){
        $path=ProfilePath $Scope.$name;AssertReadNoReparse $path;$hash=$Scope.($name.Replace('_path','_sha256'))
        if($path-ine(ProfilePath $fixed[$name])-or$hash-isnot[string]-or$hash-cnotmatch'\A[A-F0-9]{64}\z'-or
            (Get-Item -LiteralPath $path).Length-gt1048576-or(ProfileHash $path)-cne$hash-or-not$Bindings.ContainsKey($path)-or$Bindings[$path]-cne$hash){throw 'MULTI_OWNER_STATE_PRIOR_BINDING'}
        $prior[$name]=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    }
    if($Scope.prior_return_sha256-cne'A517FD717FF2A69A35168EBDE603BBCC908358D71906EC56EE0B854EA3FE04BA'-or
        $Scope.prior_scope_sha256-cne'092B3640C077881C6E196F6243FA41782E5F309E01D6EA34B23C477C231DA036'){throw 'MULTI_OWNER_STATE_FIXED_PREDECESSOR'}
    $r=$prior.prior_return_path;$s=$prior.prior_scope_path;$ready=$prior.prior_native_ready_path;$rev=$prior.prior_revoked_path;$c=$r.controller_report;$w=$c.worker_receipt
    if($r.run_id-cne'20261028_b_document_job_membership_68'-or$r.writer.thread_id-cne'RECEIVER_ID_REQUIRED'-or
        $r.terminal_state-cne'CONTROLLER_EXCEPTION__EVIDENCE_PRESERVED__NO_RETRY'-or$c.status-cne'PARTIAL_OR_UNKNOWN_AFTER_PARENT_LAUNCH_REQUEST'-or
        $w.fixed_send_count-ne0-or$w.send_entered-isnot[bool]-or$w.send_entered-or$w.detail-cnotlike'*BDOC_B_STRICT:EXACT_FULL_PATH_NOT_FOUND*'-or
        $w.cleanup-cne'OWN_COOKIE_REVOKED_AFTER_RESULT'-or$c.protected_hashes_after-cne'UNCHANGED'-or
        $c.helper.active-ne0-or-not$c.helper.root_exited-or-not$c.helper.output_complete-or$c.helper.exit_code-ne1){throw 'MULTI_OWNER_STATE_PREDECESSOR_UNSETTLED'}
    # The exception return's release flag is not rewritten or treated as a lock.
    # Runtime must still enter the original fresh global operation guard.
    if($ready.status-cne'DOCUMENT_BRIDGE_READY'-or$ready.run_id-cne$s.run_id-or$ready.nonce-cne$s.nonce-or
        $rev.status-cne'OWN_COOKIE_REVOKED'-or$rev.reason-cne'REQUESTED'-or$rev.run_id-cne$s.run_id-or$rev.nonce-cne$s.nonce-or
        $rev.rot_key-cne$ready.rot_key-or-not$rev.registered_ever-or
        ($ready.owner|ConvertTo-Json -Compress)-cne($w.native_ready.owner|ConvertTo-Json -Compress)){throw 'MULTI_OWNER_STATE_READY_REVOKE_CHAIN'}
    foreach($pair in @(@($Scope.owners[0],$s.preserved_a),@($Scope.owners[1],$ready.owner))){
        foreach($field in @('process_id','process_start_time_utc','process_image_path','window_handle','document_full_path')){
            if([string]$pair[0].$field-cne[string]$pair[1].$field){throw 'MULTI_OWNER_STATE_PRIOR_OWNER'}
        }
    }
    if($Scope.source_path-cne$s.source_path-or$Scope.source_sha256-cne$s.source_sha256-or$Scope.owners[1].protected_sha256-cne$s.source_sha256){throw 'MULTI_OWNER_STATE_PRIOR_SOURCE'}
    if($Policy.implementation_version-ge3){
        $focusPath=ProfilePath $Scope.prior_focus_return_path;AssertReadNoReparse $focusPath
        $focusHash='3379E2D47A9EC6EE49CA2FA9D02155BF68123C871FF31609A4E4FFCFC3A7B302'
        if($focusPath-ine(ProfilePath 'runs/20261028_b_native_state_diagnostic_69/execution_return.json')-or
            $Scope.prior_focus_return_sha256-cne$focusHash-or(ProfileHash $focusPath)-cne$focusHash-or
            -not$Bindings.ContainsKey($focusPath)-or$Bindings[$focusPath]-cne$focusHash){throw 'MULTI_OWNER_STATE_FOCUS_PREDECESSOR_BINDING'}
        $fr=Get-Content -LiteralPath $focusPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $fc=$fr.controller_report;$fw=$fc.worker_receipt;$fp=$fw.probe_result;$fh=$fc.helper_phase
        if($fr.writer.thread_id-cne'RECEIVER_ID_REQUIRED'-or
            $fc.status-cne'UNKNOWN_OR_UNSETTLED_COMMAND_EFFECT'-or$fp.error-cne'COMMAND_PROMPT_NOT_READY'-or
            $fw.actual_focus_calls-ne1-or$fw.actual_uia_setter_calls-ne0-or$fw.actual_submit_calls-ne0-or
            $fh.root_exit_code-ne0-or$fh.job_active_after-ne0-or-not$fh.output_complete-or$fh.own_job_stop_attempted-or
            $fc.protected_hashes_after-cne'UNCHANGED'){throw 'MULTI_OWNER_STATE_FOCUS_PREDECESSOR_UNSETTLED'}
        foreach($owner in @($fw.initial_owners)+@($fw.final_owners)){
            $expected=@($Scope.owners|Where-Object id -CEQ $owner.id)
            if($expected.Count-ne1){throw 'MULTI_OWNER_STATE_FOCUS_PREDECESSOR_OWNER'}
            foreach($field in @('process_id','process_start_time_utc','process_image_path','window_handle')){
                if([string]$owner.$field-cne[string]$expected[0].$field){throw 'MULTI_OWNER_STATE_FOCUS_PREDECESSOR_OWNER'}
            }
        }
    }
    foreach($file in $Manifest.validation_dependencies){
        $path=ProfilePath $file.path;AssertReadNoReparse $path
        if((ProfileHash $path)-cne$file.sha256-or-not$Bindings.ContainsKey($path)-or$Bindings[$path]-cne$file.sha256){throw 'MULTI_OWNER_STATE_VALIDATION_BINDING'}
    }
}
$windowPrepare=$Contract.intent-ceq'PrepareExistingBWindow'
$fixedCommand=$Contract.intent-ceq'ExecuteExistingBFixedReadCommand'
$markerClear=$Contract.intent-ceq'ClearExistingBOwnProbeMarker'
$bufferProbe=$markerClear-or$Contract.intent-ceq'WriteAndRestoreExistingBCommandBuffer'
$uiaInspection=$fixedCommand-or$bufferProbe-or$Contract.intent-ceq'InspectExistingBCommandUia'
$inspection=$windowPrepare-or$uiaInspection-or$Contract.intent-ceq'InspectExistingBCommandInput'
$profile=$Draft.($Contract.scope_field)
$stateDiagnostic=$false
if($fixedCommand-and$null-ne$Contract.PSObject.Properties['diagnostic_variants']){
    $variant=$Contract.diagnostic_variants.PSObject.Properties['CURRENT_B68_NATIVE_METADATA_V2']
    if($null-ne$variant-and(ProfilePath $profile.manifest_path)-ieq(ProfilePath $variant.Value.manifest_path)){
        if($profile.manifest_sha256-cne$variant.Value.manifest_sha256-or$variant.Value.diagnostic_variant-cne$variant.Name-or
            $variant.Value.profile_id-cne$Contract.profile_id-or$variant.Value.scope_field-cne$Contract.scope_field-or
            $variant.Value.intent-cne$Contract.intent){throw 'MULTI_OWNER_STATE_VARIANT_IDENTITY'}
        $Contract=$variant.Value;$stateDiagnostic=$true
    }
}
$profileId=if($fixedCommand){'CAD-EXACT-B-FIXED-READ-COMMAND-V1'}elseif($markerClear){'CAD-EXACT-B-COMMAND-BUFFER-OWN-MARKER-CLEAR-V1'}elseif($windowPrepare){'CAD-EXACT-B-WINDOW-PREPARE-V1'}elseif($bufferProbe){'CAD-EXACT-B-COMMAND-BUFFER-PROBE-V1'}elseif($uiaInspection){'CAD-EXACT-B-COMMAND-UIA-READ-V1'}elseif($inspection){'CAD-EXISTING-B-PINNED-PIPE-BOOTSTRAP-V1'}else{'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1'}
if([string]$profile.profile_id-cne$profileId){throw 'MULTI_OWNER_PROFILE_UNKNOWN'}
if($inspection-and($profile.intent-cne$Contract.intent-or$Draft.governance.workflow_id-cne$profileId)){throw 'MULTI_OWNER_INSPECTION_INTENT'}
$legacyManifestPath=ProfilePath $(if($inspection){$Contract.identity_manifest_path}else{$Contract.manifest_path})
$legacyManifestHash=if($inspection){$Contract.identity_manifest_sha256}else{$Contract.manifest_sha256}
if((ProfileHash $legacyManifestPath)-cne[string]$legacyManifestHash){throw 'MULTI_OWNER_MANIFEST_CHANGED'}
$legacyManifest=Get-Content -LiteralPath $legacyManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$versioned=$false
$lookupIntent=''
$capabilityBounds=$null
if(-not$inspection-and$null-ne$profile.PSObject.Properties['manifest_path']-and(ProfilePath $profile.manifest_path)-ieq$legacyManifestPath-and
    ($null-eq$profile.PSObject.Properties['manifest_sha256']-or$profile.manifest_sha256-cne$Contract.manifest_sha256)){throw 'MULTI_OWNER_CANDIDATE_HASH'}
if($inspection-or($null-ne$profile.PSObject.Properties['manifest_path']-and(ProfilePath $profile.manifest_path)-ine$legacyManifestPath)){
    if($Contract.candidate_resolution-cne'source_sealed_version_with_stable_capability_bounds'){throw 'MULTI_OWNER_CANDIDATE_NOT_ADMITTED'}
    $candidatePath=ProfilePath $profile.manifest_path
    $relative=[IO.Path]::GetRelativePath($Root,$candidatePath).Replace('\','/')
    if($relative-cnotmatch('^'+[regex]::Escape($Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$')){throw 'MULTI_OWNER_CANDIDATE_DIRECTORY'}
    $implementationVersion=[long]$Matches[1]
    AssertReadNoReparse $candidatePath
    if([string]$profile.manifest_sha256-cnotmatch'^[A-F0-9]{64}$'-or(ProfileHash $candidatePath)-cne$profile.manifest_sha256){throw 'MULTI_OWNER_CANDIDATE_HASH'}
    $candidate=Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($candidate.id-cne$profile.profile_id-or$candidate.source_thread_id-cne$Contract.candidate_source_thread_id-or
        ($candidate.implementation_version-isnot[long]-and$candidate.implementation_version-isnot[int])-or$candidate.implementation_version-ne$implementationVersion-or
        ($candidate.package_version-isnot[long]-and$candidate.package_version-isnot[int])-or$candidate.package_version-ne$implementationVersion-or
        $candidate.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'-or$candidate.scope_field-cne$Contract.scope_field-or$candidate.intent-cne$Contract.intent){throw 'MULTI_OWNER_CANDIDATE_IDENTITY'}
    if($stateDiagnostic-and($candidate.diagnostic_variant-cne$Contract.diagnostic_variant-or$implementationVersion-ne$Contract.implementation_version)){throw 'MULTI_OWNER_STATE_VARIANT_IDENTITY'}
    foreach($field in @('concurrency_allowed','live_cad_verified')){
        if($inspection-and$null-eq$candidate.PSObject.Properties[$field]){continue}
        if($candidate.$field-isnot[bool]-or$candidate.$field){throw 'MULTI_OWNER_CANDIDATE_LIVE_OR_CONCURRENT'}
    }
    foreach($field in @('controller','scope_contract')){
        $code=ProfilePath $candidate.$field
        if([IO.Path]::IsPathRooted($candidate.$field)-or(Split-Path -Parent $code)-ine(Split-Path -Parent $candidatePath)-or[IO.Path]::GetExtension($code)-ine'.ps1'){throw 'MULTI_OWNER_CANDIDATE_CODE_PATH'}
        AssertReadNoReparse $code
    }
    $capabilityBounds=$Contract.candidate_capability_bounds|ConvertTo-Json -Depth 10|ConvertFrom-Json -DateKind String
    if($null-ne$candidate.PSObject.Properties['lookup_intent']){
        if($inspection){throw 'MULTI_OWNER_INSPECTION_NO_LOOKUP'}
        $lookupIntent=[string]$candidate.lookup_intent
        if($lookupIntent-cne'ReadExistingBFileRotNonActivating'-or$null-eq$Contract.PSObject.Properties['candidate_lookup_variants']){throw 'MULTI_OWNER_LOOKUP_INTENT_UNKNOWN'}
        $variantProperty=$Contract.candidate_lookup_variants.PSObject.Properties[$lookupIntent]
        if($null-eq$variantProperty){throw 'MULTI_OWNER_LOOKUP_INTENT_NOT_ADMITTED'}
        $variant=$variantProperty.Value
        foreach($field in $variant.capability_remove){$capabilityBounds.PSObject.Properties.Remove($field)}
        foreach($p in $variant.capability_overlay.PSObject.Properties){$capabilityBounds|Add-Member NoteProperty $p.Name $p.Value -Force}
    }
    AssertReadCapabilities $candidate.capability_bounds $capabilityBounds
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    $Contract|Add-Member NoteProperty manifest_path $relative -Force
    $Contract|Add-Member NoteProperty manifest_sha256 $profile.manifest_sha256 -Force
    $Contract|Add-Member NoteProperty controller $candidate.controller -Force
    $versioned=$true
}
$manifestPath=ProfilePath $Contract.manifest_path
if((ProfileHash $manifestPath)-cne[string]$Contract.manifest_sha256){throw 'MULTI_OWNER_MANIFEST_CHANGED'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.id-cne$profile.profile_id-or(-not$inspection-and($manifest.concurrency_allowed-ne$false-or$manifest.live_cad_verified-ne$false))){throw 'MULTI_OWNER_MANIFEST_IDENTITY'}
$bindings=@{}
foreach($property in $Draft.program.PSObject.Properties){
    if($property.Name.EndsWith('_sha256')){
        $key=$property.Name.Substring(0,$property.Name.Length-7)
        $pathProperty=$Draft.program.PSObject.Properties[$key]
        if($null-eq$pathProperty){throw 'MULTI_OWNER_PROGRAM_PAIR_MISSING'}
        $boundPath=ProfilePath ([string]$pathProperty.Value)
        if($bindings.ContainsKey($boundPath)-and$bindings[$boundPath]-cne[string]$property.Value){throw 'MULTI_OWNER_PROGRAM_CONFLICT'}
        $bindings[$boundPath]=[string]$property.Value
    }
}
foreach($file in @($manifest.files)+@([pscustomobject]@{path=$Contract.manifest_path;sha256=$Contract.manifest_sha256})){
    $path=ProfilePath $file.path
    if($versioned){AssertReadNoReparse $path}
    if((ProfileHash $path)-cne[string]$file.sha256-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne[string]$file.sha256){throw ('MULTI_OWNER_CANDIDATE_BINDING:'+ $file.path)}
}
$controller=ProfilePath $Contract.controller
if((ProfilePath $Draft.program.controller)-ine$controller){throw 'MULTI_OWNER_CONTROLLER_NOT_ADMITTED'}
$scopePath=ProfilePath $profile.scope_path
if([string]$profile.scope_sha256-cnotmatch'^[A-F0-9]{64}$'-or(ProfileHash $scopePath)-cne[string]$profile.scope_sha256-or-not$bindings.ContainsKey($scopePath)-or$bindings[$scopePath]-cne[string]$profile.scope_sha256){throw 'MULTI_OWNER_SCOPE_HASH_BINDING'}
$scopeContracts=@($(if($versioned){$legacyManifest.files}else{$manifest.files})|Where-Object{[IO.Path]::GetFileName([string]$_.path)-like'cad_multi_owner_preflight_contract_v*.ps1'})
if($scopeContracts.Count-ne1){throw 'MULTI_OWNER_SCOPE_CONTRACT_NOT_UNIQUE'}
if($versioned){
    # Reuse the frozen pure scope/selector/hash functions independently of a private
    # validator. Their transitive implementation hashes remain the legacy hashes.
    foreach($dependency in @($scopeContracts[0])+@($legacyManifest.files|Where-Object{[IO.Path]::GetFileName($_.path)-cin@('cad_exact_target_candidate_v2.ps1','get_shared_file_sha256_v1.ps1','CadOperationGuard.psm1')})){
        $path=ProfilePath $dependency.path
        AssertReadNoReparse $path
        $dependencyRows=@($manifest.files|Where-Object{(ProfilePath $_.path)-ieq$path-and$_.sha256-ceq$dependency.sha256})
        if($dependencyRows.Count-ne1-or(ProfileHash $path)-cne$dependency.sha256-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$dependency.sha256){throw 'MULTI_OWNER_FROZEN_RUNTIME_BINDING'}
    }
    $privateContract=@($manifest.files|Where-Object{(ProfilePath $_.path)-ieq(ProfilePath $manifest.scope_contract)})
    $controllerRows=@($manifest.files|Where-Object{(ProfilePath $_.path)-ieq$controller})
    if($privateContract.Count-ne1-or$controllerRows.Count-ne1){throw 'MULTI_OWNER_CANDIDATE_CODE_NOT_BOUND'}
    AssertReadNoReparse $scopePath
}
. (ProfilePath $scopeContracts[0].path)
$scope=Read-CadMultiOwnerScopeJsonV2 $scopePath
if($fixedCommand-and-not$stateDiagnostic-and$null-ne$scope.PSObject.Properties['diagnostic_variant']){throw 'MULTI_OWNER_STATE_VARIANT_NOT_ADMITTED'}
if($inspection){
    if($scope.schema_version-ne1-or$scope.profile_id-cne$profileId-or$scope.intent-cne$Contract.intent-or$scope.phase-cne$Contract.phase-or
        @($scope.owners).Count-ne2-or(@($scope.owners.id)-join',')-cne'A,B'-or(@($scope.sequence)-join',')-cne'B'){throw 'MULTI_OWNER_INSPECTION_SCOPE'}
    foreach($p in $scope.PSObject.Properties){if($p.Name-like'allow_*'-or$p.Name-ceq'lookup_intent'){throw 'MULTI_OWNER_INSPECTION_UNKNOWN_RIGHT'}}
    $identityInput=[pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$scope.run_id;owners=$scope.owners;sequence=@('A','B','A')}
    $validated=Assert-CadMultiOwnerPreflightScopeV1 $identityInput $Root
    $validated.sequence=@('B')
}elseif($lookupIntent){
    # Separate B-only lookup admission. Clone identity metadata solely to reuse
    # the frozen owner validator; never turn the actual B plan into an ABA read.
    if($scope.lookup_intent-cne$lookupIntent-or$scope.target_owner_id-cne'B'-or
        @($scope.owners).Count-ne2-or(@($scope.owners.id)-join',')-cne'A,B'-or
        @($scope.sequence).Count-ne1-or$scope.sequence[0]-cne'B'-or
        $scope.lookup_target_path-cne$scope.owners[1].document_full_path){throw 'MULTI_OWNER_LOOKUP_TARGET_OR_SEQUENCE'}
    foreach($field in @('file_moniker_create_max','is_running_max','get_object_max')){
        if($scope.$field.GetType()-notin@([int],[long])-or$scope.$field-ne1){throw 'MULTI_OWNER_LOOKUP_LIMIT'}
    }
    if($scope.allow_file_rot_lookup-isnot[bool]-or-not$scope.allow_file_rot_lookup-or
        $scope.allow_enumeration-isnot[bool]-or$scope.allow_enumeration){throw 'MULTI_OWNER_LOOKUP_ENUMERATION_OR_PERMISSION'}
    foreach($pair in @(@('getter_max_count',6),@('bind_max_count',12),@('rot_producer_max_count',1),@('helper_max_count',1),@('helper_timeout_seconds',27),@('outer_timeout_seconds',30),@('stream_limit_chars',32768))){
        if($scope.($pair[0]).GetType()-notin@([int],[long])-or$scope.($pair[0])-ne$pair[1]){throw ('MULTI_OWNER_LOOKUP_SCOPE_BOUND:'+ $pair[0])}
    }
    foreach($p in $scope.PSObject.Properties){
        if($p.Name-like'allow_*'-and$p.Name-cnotin@('allow_getters','allow_file_rot_lookup')-and($p.Value-isnot[bool]-or$p.Value)){throw ('MULTI_OWNER_LOOKUP_SCOPE_RIGHT:'+ $p.Name)}
    }
    foreach($field in @('allow_getters','all_owner_modal_gate_required','fresh_identity_before_after_each_getter','retain_producer_references_until_worker_exit','exclude_expired_custom_keys')){
        if($scope.$field-isnot[bool]-or-not$scope.$field){throw ('MULTI_OWNER_LOOKUP_SCOPE_REQUIRED:'+ $field)}
    }
    $identityInput=$scope|ConvertTo-Json -Depth 25|ConvertFrom-Json -DateKind String
    $identityInput.sequence=@('A','B','A')
    $validated=Assert-CadMultiOwnerPreflightScopeV1 $identityInput $Root
    $validated.sequence=@('B')
}else{
    if($null-ne$scope.PSObject.Properties['lookup_intent']){throw 'MULTI_OWNER_LOOKUP_MANIFEST_REQUIRED'}
    $validated=Assert-CadMultiOwnerPreflightScopeV1 $scope $Root
}
if($validated.run_id-cne[string]$Draft.run_id){throw 'MULTI_OWNER_SCOPE_RUN_MISMATCH'}
Assert-CadMultiOwnerProtectedHashesV1 $validated
if($versioned){
    foreach($policy in @($Draft.canonical_open,$Draft.launch_policy)){
        if($policy.launch_permitted_for_this_handoff-isnot[bool]-or$policy.launch_permitted_for_this_handoff){throw 'MULTI_OWNER_CANDIDATE_LAUNCH_POLICY'}
    }
    foreach($name in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')){
        if($Draft.launch_policy.$name-isnot[bool]-or$Draft.launch_policy.$name){throw 'MULTI_OWNER_CANDIDATE_LAUNCH_POLICY'}
    }
    $scopeVersion=if($inspection){$scope.candidate_version}else{$scope.implementation_version}
    if($scopeVersion-ne$implementationVersion-or$scopeVersion.GetType()-notin@([int],[long])){throw 'MULTI_OWNER_SCOPE_VERSION'}
    AssertReadCapabilities $scope.capability_bounds $capabilityBounds
    if(@($validated.owners.window_handle|Select-Object -Unique).Count-ne$validated.owners.Count){throw 'MULTI_OWNER_SCOPE_DUPLICATE_HWND'}
    $sourcePath=ProfilePath $scope.source_path
    AssertReadNoReparse $sourcePath
    if([IO.Path]::GetExtension($sourcePath)-ine'.dwg'-or[string]$scope.source_sha256-cnotmatch'^[A-F0-9]{64}$'-or
        (& (ProfilePath 'scripts/get_shared_file_sha256_v1.ps1') -Path $sourcePath)-cne$scope.source_sha256){throw 'MULTI_OWNER_SOURCE_HASH'}
    foreach($owner in $validated.owners){
        if((ProfilePath $owner.document_full_path)-ieq$sourcePath){throw 'MULTI_OWNER_SOURCE_IS_WORK_COPY'}
        AssertReadNoReparse (ProfilePath $owner.document_full_path)
    }
    if($windowPrepare){
        if($scope.window_mode-cnotin@('NOACTIVATE','ALLOW_ACTIVATION')-or$scope.show_window_ncmd.GetType()-notin@([int],[long])-or
            ($scope.window_mode-ceq'NOACTIVATE'-and$scope.show_window_ncmd-ne4)-or
            ($scope.window_mode-ceq'ALLOW_ACTIVATION'-and$scope.show_window_ncmd-ne9)){throw 'MULTI_OWNER_WINDOW_MODE'}
        if($scope.window_mode-ceq'ALLOW_ACTIVATION'){
            if($scope.activation_reason-isnot[string]-or[string]::IsNullOrWhiteSpace($scope.activation_reason)-or$scope.activation_reason.Length-gt512){throw 'MULTI_OWNER_WINDOW_ACTIVATION_REASON'}
            $prior=ProfilePath $scope.activation_evidence_path
            AssertReadNoReparse $prior
            if(-not$prior.StartsWith((Join-Path $Root 'runs')+'\',[StringComparison]::OrdinalIgnoreCase)-or
                [IO.Path]::GetFileName($prior)-cne'execution_return.json'-or(Split-Path -Leaf (Split-Path -Parent $prior))-ceq$scope.run_id-or
                [string]$scope.activation_evidence_sha256-cnotmatch'\A[A-F0-9]{64}\z'-or(ProfileHash $prior)-cne$scope.activation_evidence_sha256-or
                -not$bindings.ContainsKey($prior)-or$bindings[$prior]-cne$scope.activation_evidence_sha256){throw 'MULTI_OWNER_WINDOW_ACTIVATION_EVIDENCE'}
            # The source's pure scope contract also checks that this earlier
            # terminal receipt proves settled necessity, not a pending request.
        }elseif($null-ne$scope.PSObject.Properties['activation_reason']-or$null-ne$scope.PSObject.Properties['activation_evidence_path']-or$null-ne$scope.PSObject.Properties['activation_evidence_sha256']){
            throw 'MULTI_OWNER_WINDOW_NOACTIVATE_NOT_ACTIVATION'
        }
    }
    if($uiaInspection-and-not$stateDiagnostic){
        # Historical evidence pins one command-host chain; runtime fresh validation
        # is still required. No HWND lookup or UIA call is performed by this gate.
        $evidence=ProfilePath $scope.anchor_evidence_path
        AssertReadNoReparse $evidence
        $currentNativeEvidence=$Contract.intent-ceq'InspectExistingBCommandUia'-and[IO.Path]::GetFileName($evidence)-ceq'current_native_anchor.json'
        if(-not$evidence.StartsWith((Join-Path $Root 'runs')+'\',[StringComparison]::OrdinalIgnoreCase)-or
            (-not$currentNativeEvidence-and[IO.Path]::GetFileName($evidence)-cne'input_inspection_raw.jsonl')-or(Get-Item $evidence).Length-gt1048576-or
            [string]$scope.anchor_evidence_sha256-cnotmatch'^[A-F0-9]{64}$'-or(ProfileHash $evidence)-cne$scope.anchor_evidence_sha256-or
            -not$bindings.ContainsKey($evidence)-or$bindings[$evidence]-cne$scope.anchor_evidence_sha256){throw 'MULTI_OWNER_UIA_EVIDENCE_BINDING'}
        $anchor=$scope.native_anchor;$ownerB=$validated.owners[1]
        if(($currentNativeEvidence-and$anchor.status-cne'CURRENT_B_DYNAMIC_CLI_CHAIN')-or
            (-not$currentNativeEvidence-and($anchor.status-cne'HISTORICAL_ANCHOR_EVIDENCE_ONLY'-or$anchor.source_sha256-cne$scope.anchor_evidence_sha256))-or
            $anchor.process_id-ne$ownerB.process_id-or$anchor.main_window_handle-ne$ownerB.window_handle-or
            @($anchor.chain).Count-ne4-or@($anchor.chain.native.hwnd|Select-Object -Unique).Count-ne4){throw 'MULTI_OWNER_UIA_ANCHOR_IDENTITY'}
        foreach($field in @('uia_called','send_authorized')){
            if($anchor.$field-isnot[bool]-or$anchor.$field){throw 'MULTI_OWNER_UIA_ANCHOR_FRESH_CLAIM'}
        }
        if($anchor.fresh_native_chain_verified-isnot[bool]-or(-not$currentNativeEvidence-and$anchor.fresh_native_chain_verified)){throw 'MULTI_OWNER_UIA_ANCHOR_FRESH_CLAIM'}
        if($currentNativeEvidence){
            AssertCurrentBUiaAnchorEvidence $scope $bindings $Draft.target.thread_id
        }else{
            $evidenceRows=@(Get-Content -LiteralPath $evidence -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json -DateKind String})
        }
        $parent=$ownerB.window_handle
        $nativeFields=@('hwnd','pid','thread','parent','structural_parent','root','root_owner','valid','visible','enabled','window_style','style_child','style_popup','window_class','control_id','child_of_main')
        for($i=0;$i-lt4;$i++){
            $node=$anchor.chain[$i];$n=$node.native
            if($n.hwnd.GetType()-notin@([int],[long])-or$n.hwnd-le0-or$n.pid-ne$ownerB.process_id-or$n.thread-le0-or
                $n.parent-ne$parent-or$n.structural_parent-ne$parent-or$n.root-ne$ownerB.window_handle-or$n.root_owner-ne$ownerB.window_handle){throw 'MULTI_OWNER_UIA_ANCHOR_CHAIN'}
            foreach($field in @('valid','visible','enabled','child_of_main','style_child')){if($n.$field-isnot[bool]-or-not$n.$field){throw 'MULTI_OWNER_UIA_ANCHOR_NATIVE_STATE'}}
            if($n.style_popup-isnot[bool]-or$n.style_popup){throw 'MULTI_OWNER_UIA_ANCHOR_NATIVE_STATE'}
            if(($i-eq0-and$n.window_class-cne'AfxControlBar140u')-or($i-in@(1,2)-and$n.window_class-cne'AfxWnd140u')-or
                ($i-eq3-and-not([string]$n.window_class).StartsWith('HwndWrapper['))){throw 'MULTI_OWNER_UIA_ANCHOR_CLASS'}
            if(($i-in@(0,1)-and$node.text-cne'CLI PaletteSet')-or($i-eq2-and$node.text-cne'CLI Palette')){throw 'MULTI_OWNER_UIA_ANCHOR_TITLE'}
            if(-not$currentNativeEvidence){
            $matching=@($evidenceRows|Where-Object{$_.kind-ceq'TEXT_RETURN'-and$_.before.hwnd-eq$n.hwnd})
            if($matching.Count-ne1){throw 'MULTI_OWNER_UIA_ANCHOR_EVIDENCE_ROW'}
            $row=$matching[0]
            if($row.identity_stable-isnot[bool]-or-not$row.identity_stable-or$row.text_read.complete-isnot[bool]-or-not$row.text_read.complete-or
                $row.text_read.timeout-ne$false-or$row.text_read.truncated-ne$false-or$row.text_read.text-cne$node.text){throw 'MULTI_OWNER_UIA_ANCHOR_EVIDENCE_INCOMPLETE'}
            foreach($field in $nativeFields){
                if(($n.$field|ConvertTo-Json -Compress)-cne($row.before.$field|ConvertTo-Json -Compress)-or
                    ($n.$field|ConvertTo-Json -Compress)-cne($row.after.$field|ConvertTo-Json -Compress)){throw 'MULTI_OWNER_UIA_ANCHOR_EVIDENCE_CHANGED'}
            }
            }
            $parent=$n.hwnd
        }
        if($anchor.surface_handle-ne$parent){throw 'MULTI_OWNER_UIA_ANCHOR_SURFACE'}
    }
    if(($bufferProbe-or$fixedCommand)-and-not$stateDiagnostic){
        if($bufferProbe-and($scope.probe_nonce-isnot[string]-or$scope.probe_nonce-cnotmatch'\A[a-f0-9]{32}\z'-or
            $scope.probe_text-isnot[string]-or$scope.probe_text-cnotmatch'\ACXBPROBE[a-f0-9]{32}\z'-or
            $scope.probe_text-cne('CXBPROBE'+$scope.probe_nonce))){throw 'MULTI_OWNER_BUFFER_MARKER'}
        $bufferEvidence=ProfilePath $scope.buffer_evidence_path
        AssertReadNoReparse $bufferEvidence
        if(-not$bufferEvidence.StartsWith((Join-Path $Root 'runs')+'\',[StringComparison]::OrdinalIgnoreCase)-or
            [IO.Path]::GetFileName($bufferEvidence)-cne'command_uia_raw.jsonl'-or(Get-Item $bufferEvidence).Length-gt1048576-or
            [string]$scope.buffer_evidence_sha256-cnotmatch'^[A-F0-9]{64}$'-or(ProfileHash $bufferEvidence)-cne$scope.buffer_evidence_sha256-or
            -not$bindings.ContainsKey($bufferEvidence)-or$bindings[$bufferEvidence]-cne$scope.buffer_evidence_sha256){throw 'MULTI_OWNER_BUFFER_EVIDENCE_BINDING'}
        $bufferRows=@(Get-Content -LiteralPath $bufferEvidence -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json -DateKind String})
        $stop=@($bufferRows|Where-Object kind -CEQ 'UIA_STOP')
        $projection=@($bufferRows|Where-Object kind -CEQ 'UIA_ROW')
        if($stop.Count-ne1-or$stop[0].projection_complete-isnot[bool]-or-not$stop[0].projection_complete-or$null-ne$stop[0].error-or
            $stop[0].row_count-ne$projection.Count-or$projection.Count-gt32-or$stop[0].from_handle_count-ne1){throw 'MULTI_OWNER_BUFFER_PROJECTION_INCOMPLETE'}
        $roots=@($projection|Where-Object depth -EQ 0)
        $parents=@($projection|Where-Object{$_.depth-eq1-and$_.before.class_name-ceq'CommandLineControl'})
        if($roots.Count-ne1-or$parents.Count-ne1-or$roots[0].before.native_window_handle-ne$anchor.surface_handle-or
            $parents[0].before.parent_runtime_id-cne$roots[0].before.runtime_id){throw 'MULTI_OWNER_BUFFER_PARENT_CHAIN'}
        $targets=@($projection|Where-Object{$_.depth-eq2-and$_.before.parent_runtime_id-ceq$parents[0].before.runtime_id-and
            $_.before.class_name-ceq'TextBox'-and$_.before.control_type-ceq'ControlType.Edit'-and$_.before.enabled-eq$true-and$_.before.offscreen-eq$false})
        $prompts=@($projection|Where-Object{$_.depth-eq2-and$_.before.parent_runtime_id-ceq$parents[0].before.runtime_id-and
            $_.before.class_name-ceq'TextBlock'-and$_.before.name-ceq'键入命令'-and$_.before.enabled-eq$true-and$_.before.offscreen-eq$false})
        if($targets.Count-ne1-or$prompts.Count-ne1){throw 'MULTI_OWNER_BUFFER_TARGET_NOT_UNIQUE'}
        $target=$targets[0];$prompt=$prompts[0]
        if($target.value_text-isnot[string]-or$target.document_text-isnot[string]-or$target.value_text-cne''-or$target.document_text-cne''-or
            $target.pattern_capabilities.value_pattern_supported-isnot[bool]-or-not$target.pattern_capabilities.value_pattern_supported-or
            $target.pattern_capabilities.text_pattern_supported-isnot[bool]-or-not$target.pattern_capabilities.text_pattern_supported-or
            $target.pattern_capabilities.value_is_read_only-isnot[bool]-or$target.pattern_capabilities.value_is_read_only){throw 'MULTI_OWNER_BUFFER_INITIAL_OR_PATTERN'}
        $uiaFields=@('runtime_id','parent_runtime_id','process_id','native_window_handle','native_identity_verified','name','automation_id','class_name','framework_id','control_type','is_password','enabled','offscreen','keyboard_focus')
        foreach($row in @($roots[0],$parents[0],$target,$prompt)){
            if($row.read_complete-isnot[bool]-or-not$row.read_complete-or$row.identity_stable-isnot[bool]-or-not$row.identity_stable-or
                $row.before.process_id-ne$ownerB.process_id-or[string]::IsNullOrWhiteSpace($row.before.runtime_id)-or
                $row.before.is_password-isnot[bool]-or$row.before.is_password-or$row.before.keyboard_focus-isnot[bool]-or$row.before.keyboard_focus-or
                $row.before.enabled-isnot[bool]-or-not$row.before.enabled-or$row.before.offscreen-isnot[bool]-or$row.before.offscreen){throw 'MULTI_OWNER_BUFFER_IDENTITY_OR_FOCUS'}
            foreach($field in $uiaFields){if(($row.before.$field|ConvertTo-Json -Compress)-cne($row.after.$field|ConvertTo-Json -Compress)){throw 'MULTI_OWNER_BUFFER_IDENTITY_CHANGED'}}
        }
        AssertReadCapabilities $scope.buffer_target $target.before
        AssertReadCapabilities $scope.ready_prompt $prompt.before
    }
    if($markerClear){
        if($scope.prior_run_id-isnot[string]-or$scope.prior_run_id-cnotmatch'\A[A-Za-z0-9_-]+\z'-or$scope.prior_run_id-ceq$scope.run_id){throw 'MULTI_OWNER_CLEAR_PRIOR_RUN'}
        $priorPaths=@{}
        foreach($part in @('return','scope','controller','raw')){
            $path=ProfilePath $scope.('prior_'+$part+'_path');$hash=$scope.('prior_'+$part+'_sha256')
            AssertReadNoReparse $path
            if($hash-isnot[string]-or$hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-Item $path).Length-gt1048576-or
                (ProfileHash $path)-cne$hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$hash){throw 'MULTI_OWNER_CLEAR_PRIOR_BINDING'}
            if($part-cne'scope'){
                $leaf=@{return='execution_return.json';controller='controller_receipt.json';raw='command_buffer_raw.jsonl'}[$part]
                if($path-ine(Join-Path (Join-Path (Join-Path $Root 'runs') $scope.prior_run_id) $leaf)){throw 'MULTI_OWNER_CLEAR_PRIOR_PATH'}
            }
            $priorPaths[$part]=$path
        }
        $priorReturn=Get-Content -LiteralPath $priorPaths['return'] -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $priorScope=Get-Content -LiteralPath $priorPaths['scope'] -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $priorController=Get-Content -LiteralPath $priorPaths['controller'] -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        if($priorReturn.run_id-cne$scope.prior_run_id-or$priorScope.run_id-cne$scope.prior_run_id-or$priorController.run_id-cne$scope.prior_run_id-or
            $priorReturn.execution_control_released-isnot[bool]-or-not$priorReturn.execution_control_released-or
            (ProfilePath $priorReturn.controller_report_path)-ine$priorPaths['controller']-or$priorReturn.controller_report_sha256-cne$scope.prior_controller_sha256-or
            $priorController.scope_sha256-cne$scope.prior_scope_sha256-or$priorScope.profile_id-cne'CAD-EXACT-B-COMMAND-BUFFER-PROBE-V1'-or
            $priorScope.intent-cne'WriteAndRestoreExistingBCommandBuffer'-or$priorController.profile_id-cne$priorScope.profile_id-or
            $priorController.protected_hashes_after-cne'UNCHANGED'){throw 'MULTI_OWNER_CLEAR_PRIOR_CHAIN'}
        if(@($priorScope.owners).Count-ne2){throw 'MULTI_OWNER_CLEAR_PRIOR_OWNERS'}
        for($i=0;$i-lt2;$i++){
            foreach($field in @('id','scope_kind','process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){
                if([string]$priorScope.owners[$i].$field-cne[string]$scope.owners[$i].$field){throw 'MULTI_OWNER_CLEAR_PRIOR_OWNERS'}
            }
        }
        foreach($field in @('source_path','source_sha256','probe_nonce','probe_text','anchor_evidence_path','anchor_evidence_sha256','buffer_evidence_path','buffer_evidence_sha256')){
            if([string]$priorScope.$field-cne[string]$scope.$field){throw 'MULTI_OWNER_CLEAR_PRIOR_PAYLOAD'}
        }
        AssertReadCapabilities $scope.buffer_target $priorScope.buffer_target
        AssertReadCapabilities $scope.ready_prompt $priorScope.ready_prompt
        $helper=$priorController.helper_phase;$worker=$priorController.worker_receipt;$probe=$worker.probe_result
        if($helper.output_complete-isnot[bool]-or-not$helper.output_complete-or$helper.root_exit_code-ne0-or$helper.job_active_after-ne0-or
            $helper.own_job_stop_attempted-isnot[bool]-or$helper.own_job_stop_attempted-or$null-ne$helper.reason){throw 'MULTI_OWNER_CLEAR_PRIOR_HELPER_UNSETTLED'}
        if($worker.run_id-cne$scope.prior_run_id-or$worker.scope_sha256-cne$scope.prior_scope_sha256-or
            (ProfilePath $worker.raw_evidence_path)-ine$priorPaths['raw']-or$worker.raw_evidence_sha256-cne$scope.prior_raw_sha256-or
            $worker.actual_uia_setter_calls-ne1-or$priorController.actual_uia_setter_calls-ne1-or$probe.setter_attempts-ne1-or
            $probe.marker_setter_returned-isnot[bool]-or-not$probe.marker_setter_returned-or$probe.clear_setter_returned-isnot[bool]-or$probe.clear_setter_returned-or
            $worker.command_submit_call_count-ne0-or$worker.cad_command_count-ne0-or$probe.command_submit_call_count-ne0){throw 'MULTI_OWNER_CLEAR_PRIOR_SETTER'}
        $raw=@(Get-Content -LiteralPath $priorPaths['raw'] -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json -DateKind String})
        $mark=@($raw|Where-Object kind -CEQ 'SET_MARKER_ENTER')
        $clear=@($raw|Where-Object kind -CEQ 'RESTORE_EMPTY_ENTER')
        $initial=@($raw|Where-Object{$_.kind-ceq'BUFFER_CHECKPOINT'-and$_.stage-ceq'INITIAL'})
        $settled=@($raw|Where-Object{$_.kind-ceq'BUFFER_CHECKPOINT'-and$_.stage-ceq'ERROR_SETTLEMENT'})
        if($mark.Count-ne1-or$mark[0].value-cne$scope.probe_text-or$clear.Count-ne0-or$initial.Count-ne1-or$settled.Count-ne1-or
            $initial[0].snapshot.value_text-cne''-or$initial[0].snapshot.document_text-cne''){throw 'MULTI_OWNER_CLEAR_PRIOR_RAW_SEQUENCE'}
        foreach($snapshot in @($settled[0].snapshot,$probe.last_snapshot)){
            if($snapshot.value_text-cne$scope.probe_text-or$snapshot.document_text-cne$scope.probe_text-or
                $snapshot.input_runtime_id-cne$scope.buffer_target.runtime_id-or$snapshot.parent_runtime_id-cne$scope.buffer_target.parent_runtime_id-or
                $snapshot.scope_sha256-cne$scope.prior_scope_sha256-or$snapshot.target_has_keyboard_focus-isnot[bool]-or$snapshot.target_has_keyboard_focus){throw 'MULTI_OWNER_CLEAR_PRIOR_OBSERVED_MARKER'}
        }
    }
    if($fixedCommand-and-not$stateDiagnostic){
        if($scope.projection_mode-cne'COMMAND_ROOT_DIRECT_CHILDREN_ONLY'-or$scope.projection_depth-ne2-or
            $scope.nonce-isnot[string]-or$scope.nonce-cnotmatch'\A[a-f0-9]{32}\z'-or
            $scope.run_id-cnotmatch'\A[A-Za-z0-9_]{1,100}\z'){throw 'MULTI_OWNER_COMMAND_IDENTITY'}
        $receiptPath=ProfilePath $scope.command_receipt_path
        AssertReadNoReparse $receiptPath
        if($receiptPath-ine(Join-Path (Join-Path (Join-Path $Root 'runs') $scope.run_id) ('cad_b_'+$scope.nonce+'.txt'))-or
            (Test-Path -LiteralPath $receiptPath)){throw 'MULTI_OWNER_COMMAND_OUTPUT'}
        if($scope.transport.focus_reason-isnot[string]-or[string]::IsNullOrWhiteSpace($scope.transport.focus_reason)-or$scope.transport.focus_reason.Length-gt512){throw 'MULTI_OWNER_COMMAND_FOCUS_REASON'}
        $transport=[pscustomobject]@{api='SendMessageTimeoutW';receiver='BOUND_B_WPF_SURFACE_ONLY';surface_handle=$scope.native_anchor.surface_handle;message=258;wparam=13;lparam=1;flags=35;timeout_ms=500;max_submit_calls=1;focus_api='AutomationElement.SetFocus';max_focus_calls=1;focus_reason=$scope.transport.focus_reason}
        $transport=$transport|ConvertTo-Json -Compress|ConvertFrom-Json
        AssertReadCapabilities $scope.transport $transport
        # Compare with one reviewed immutable pure builder, not a candidate's
        # potentially permissive validator. Future versions reuse this contract.
        $expressionPath=ProfilePath $Contract.expression_contract_path
        AssertReadNoReparse $expressionPath
        if((ProfileHash $expressionPath)-cne$Contract.expression_contract_sha256-or
            -not$bindings.ContainsKey($expressionPath)-or$bindings[$expressionPath]-cne$Contract.expression_contract_sha256-or
            @($manifest.files|Where-Object{(ProfilePath $_.path)-ieq$expressionPath-and$_.sha256-ceq$Contract.expression_contract_sha256}).Count-ne1){throw 'MULTI_OWNER_COMMAND_EXPRESSION_CONTRACT'}
        $expression=& {param($Path,$InputScope) . $Path;New-CadExactBExpressionV1 $InputScope} $expressionPath $scope
        $expressionHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($expression)))
        if($scope.command_text-isnot[string]-or$scope.command_text-match'[\x00\r\n]'-or$scope.command_text.Length-gt3500-or
            $scope.command_text-cne$expression-or$scope.expression_sha256-cne$expressionHash){throw 'MULTI_OWNER_COMMAND_EXPRESSION'}
        $priorPaths=@{}
        foreach($part in @('return','scope')){
            $path=ProfilePath $scope.('prior_'+$part+'_path');$hash=$scope.('prior_'+$part+'_sha256')
            AssertReadNoReparse $path
            if($hash-isnot[string]-or$hash-cnotmatch'\A[A-F0-9]{64}\z'-or(Get-Item $path).Length-gt1048576-or
                (ProfileHash $path)-cne$hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$hash){throw 'MULTI_OWNER_COMMAND_PRIOR_BINDING'}
            $priorPaths[$part]=$path
        }
        $previousReturn=Get-Content -LiteralPath $priorPaths['return'] -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $previousScope=Get-Content -LiteralPath $priorPaths['scope'] -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $previous=$previousReturn.controller_report
        if($previousReturn.run_id-ceq$scope.run_id-or$previousReturn.run_id-cne$previousScope.run_id-or$previous.run_id-cne$previousReturn.run_id-or
            $priorPaths['return']-ine(Join-Path (Join-Path (Join-Path $Root 'runs') $previousReturn.run_id) 'execution_return.json')-or
            $previousReturn.execution_control_released-isnot[bool]-or-not$previousReturn.execution_control_released-or
            $null-ne$previousReturn.controller_error-or$null-ne$previousReturn.report_error-or
            $previousScope.profile_id-cne'CAD-EXACT-B-COMMAND-UIA-READ-V1'-or$previous.profile_id-cne$previousScope.profile_id-or
            $previous.scope_sha256-cne$scope.prior_scope_sha256-or$previous.status-cne'COMPLETE_UIA_COMMAND_PROJECTION_READ_ONLY'-or
            $previous.protected_hashes_after-cne'UNCHANGED'){throw 'MULTI_OWNER_COMMAND_PRIOR_CHAIN'}
        if(@($previousScope.owners).Count-ne2){throw 'MULTI_OWNER_COMMAND_PRIOR_OWNER'}
        for($i=0;$i-lt2;$i++){
            foreach($field in @('id','scope_kind','process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){
                if([string]$previousScope.owners[$i].$field-cne[string]$scope.owners[$i].$field){throw 'MULTI_OWNER_COMMAND_PRIOR_OWNER'}
            }
        }
        foreach($field in @('source_path','source_sha256','anchor_evidence_path','anchor_evidence_sha256')){
            if([string]$previousScope.$field-cne[string]$scope.$field){throw 'MULTI_OWNER_COMMAND_PRIOR_SCOPE'}
        }
        $helper=$previous.helper_phase;$worker=$previous.worker_receipt
        if($helper.job_bound_before_resume-isnot[bool]-or-not$helper.job_bound_before_resume-or
            $helper.output_complete-isnot[bool]-or-not$helper.output_complete-or$helper.root_exit_code-ne0-or$helper.job_active_after-ne0-or
            $helper.own_job_stop_attempted-isnot[bool]-or$helper.own_job_stop_attempted-or$null-ne$helper.reason){throw 'MULTI_OWNER_COMMAND_PRIOR_HELPER'}
        if($worker.run_id-cne$previousReturn.run_id-or$worker.scope_sha256-cne$scope.prior_scope_sha256-or
            $worker.status-cne'COMPLETE_UIA_COMMAND_PROJECTION_READ_ONLY'-or
            (ProfilePath $worker.raw_evidence_path)-ine$bufferEvidence-or$worker.raw_evidence_sha256-cne$scope.buffer_evidence_sha256-or
            $bufferEvidence-ine(Join-Path (Join-Path (Join-Path $Root 'runs') $previousReturn.run_id) 'command_uia_raw.jsonl')){throw 'MULTI_OWNER_COMMAND_PRIOR_RAW'}
        foreach($field in @('cad_com_count','cad_rot_count','cad_command_count','input_count','click_count','activate_count','focus_change_count','load_count','launch_count','save_count','close_count','kill_cad_count','retry_count')){
            if($worker.$field.GetType()-notin@([int],[long])-or$worker.$field-ne0){throw 'MULTI_OWNER_COMMAND_PRIOR_NOT_READ_ONLY'}
        }
    }
    if($stateDiagnostic){AssertCurrentBStateDiagnostic $scope $Contract $manifest $bindings}
    # Private extra checks run in a child scope, so they cannot replace the shared
    # frozen validators used above or the literal-call parser below.
    & {
        param($ContractPath,$FunctionName,$InputScope,$InputRoot)
        . $ContractPath
        if(-not(Get-Command $FunctionName -CommandType Function -ErrorAction SilentlyContinue)){throw 'MULTI_OWNER_CANDIDATE_CONTRACT_ABI'}
        & $FunctionName $InputScope $InputRoot | Out-Null
    } (ProfilePath $manifest.scope_contract) ($(if($fixedCommand){'Assert-CadExactBCommandScopeV'}elseif($markerClear){'Assert-CadCommandMarkerClearScopeV'}elseif($windowPrepare){'Assert-CadExistingBWindowPrepareScopeV'}elseif($bufferProbe){'Assert-CadCommandBufferProbeScopeV'}elseif($uiaInspection){'Assert-CadCommandUiaInspectionScopeV'}elseif($inspection){'Assert-CadInputInspectionScopeV'}else{'Assert-CadReadSessionScopeV'})+$implementationVersion) $scope $Root
}
$run=Join-Path (Join-Path $Root 'runs') $validated.run_id
if((ProfilePath $Draft.reporting.run_directory)-ine$run-or(ProfilePath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'MULTI_OWNER_REPORT_PATH_MISMATCH'}
# Match the actual single literal call, not unused declarations. No scripts are run.
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($a)$a-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'MULTI_OWNER_TEMPLATE_NOT_LITERAL_COMMAND'}
$command=$commands[0]
if((ProfilePath $command.GetCommandName())-ine$controller){throw 'MULTI_OWNER_TEMPLATE_CONTROLLER'}
$callParameters=@{};$elements=$command.CommandElements
for($i=1;$i-lt$elements.Count;$i+=2){
    if($elements[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$elements[$i].Argument-or$i+1-ge$elements.Count){throw 'MULTI_OWNER_TEMPLATE_PARAMETER'}
    $name=$elements[$i].ParameterName
    if($callParameters.ContainsKey($name)){throw 'MULTI_OWNER_TEMPLATE_DUPLICATE_PARAMETER'}
    $value=$elements[$i+1]
    if($value-is[Management.Automation.Language.StringConstantExpressionAst]){$callParameters[$name]=$value.Value}
    elseif($value-is[Management.Automation.Language.ConstantExpressionAst]){$callParameters[$name]=$value.Value}
    else{throw 'MULTI_OWNER_TEMPLATE_NOT_LITERAL_COMMAND'}
}
if($callParameters.Count-ne4-or@('RunDirectory','ScopePath','ScopeSha256','TimeoutSeconds'|Where-Object{-not$callParameters.ContainsKey($_)}).Count-ne0){throw 'MULTI_OWNER_TEMPLATE_PARAMETER_SET'}
if((ProfilePath $callParameters.RunDirectory)-ine$run-or(ProfilePath $callParameters.ScopePath)-ine$scopePath-or[string]$callParameters.ScopeSha256-cne[string]$profile.scope_sha256){throw 'MULTI_OWNER_TEMPLATE_SCOPE_MISMATCH'}
$timeout=ConvertTo-CadTargetV1Integer $callParameters.TimeoutSeconds
if($timeout-lt5-or$timeout-gt90){throw 'MULTI_OWNER_TIMEOUT_INVALID'}
if($versioned-and$timeout-ne$capabilityBounds.worker_timeout_seconds){throw 'MULTI_OWNER_CANDIDATE_TIMEOUT'}
[pscustomobject]@{status='PASS';profile_id=$profile.profile_id;lookup_intent=$lookupIntent;owner_count=$validated.owners.Count;sequence=$validated.sequence;cad_calls=0;live_verified=$false}
