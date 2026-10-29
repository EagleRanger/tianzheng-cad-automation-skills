# V4 changes only A acquisition, not the NONDB scope/phase/provenance contract.
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/command_probe_v3/probe_contract_v3.ps1')
function Assert-CadProbeScopeV4($Scope,[string]$Root,[string]$RunDirectory,[switch]$AllowStartedSiblingSignals) {
 if($Scope.candidate_version-ne4-or$Scope.lookup_intent-cne'KnownAApplicationAndExactBFileDocumentNonDbProbe'){throw 'PROBE_V4_SCOPE_IDENTITY'}
 $r=Assert-CadProbeProofFileV3 $Root (Join-Path $Root 'runs/20261028_ab_file_document_alternating_77/execution_return.json') '48995E5E9DB54DD5E92E58F6D71B53BFB15483F7E2BF28C265292637555DEACA' 'runs/20261028_ab_file_document_alternating_77/execution_return.json' '48995E5E9DB54DD5E92E58F6D71B53BFB15483F7E2BF28C265292637555DEACA'
 if($r.run_id-cne'20261028_ab_file_document_alternating_77'-or$r.controller_report.results.Count-ne0-or$r.controller_report.send_attempt_count_from_returned_workers-ne0-or$r.controller_report.missing_worker_receipt_count-ne0-or$r.controller_report.protected_hashes_after-cne'UNCHANGED'){throw 'PROBE_V4_FAILED_A_FILE_PREDECESSOR'}
 $w=Assert-CadProbeProofFileV3 $Root (Join-Path $Root 'runs/20261028_ab_file_document_alternating_77/worker_A1.json') '185E063D8E7EF364AFA25F8E3230BCB55782F890C9A134FC5CD8ABA61EBB4573' 'runs/20261028_ab_file_document_alternating_77/worker_A1.json' '185E063D8E7EF364AFA25F8E3230BCB55782F890C9A134FC5CD8ABA61EBB4573'
 if($w.status-cne'BLOCKED_BEFORE_SEND'-or$w.post_call_count-ne0-or$w.file_lookup_facts.status-cne'FILE_MONIKER_NOT_RUNNING'-or$w.file_lookup_facts.counts.get_object-ne0){throw 'PROBE_V4_PREVIOUS_A_FILE_NOT_RECONCILED'}
 $adapter=$Scope|ConvertTo-Json -Depth 24|ConvertFrom-Json -DateKind String
 $adapter.candidate_version=3;$adapter.lookup_intent='ExactFileDocumentNonDbProbe'
 Assert-CadProbeScopeV3 $adapter $Root $RunDirectory -AllowStartedSiblingSignals:$AllowStartedSiblingSignals
}
function Assert-CadProbeDependenciesV4([string]$Directory,[string]$Root) {
 $m=Read-CadPreparationScopeV1 (Join-Path $Directory 'candidate_manifest.json')
 if($m.id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$m.candidate_version-ne4-or$m.lookup_intent-cne'KnownAApplicationAndExactBFileDocumentNonDbProbe'-or$m.A_enumerate_max_per_operation-ne1-or-not$m.A_hold_selected_application-or$m.A_strict_bind_max_per_operation-ne4-or$m.B_file_lookup_max_per_operation-ne1-or$m.B_strict_bind_max_per_operation-ne3-or$m.dynamic_fallback_allowed){throw 'PROBE_V4_MANIFEST_IDENTITY_OR_ACQUISITION'}
 foreach($f in $m.files){$p=Assert-CadPreparationPathV1 (Join-Path $Root $f.path) $Root;if((Get-FileHash $p).Hash-cne$f.sha256){throw ('PROBE_DEPENDENCY_CHANGED:'+ $f.path)}}
}
