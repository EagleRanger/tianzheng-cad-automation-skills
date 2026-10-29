. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/command_probe_v1/probe_contract_v1.ps1')
function New-CadProbeExpressionV2($Scope,$Operation,$Owner) {
    # Retain the frozen V1 expression except the confirmed apply/lambda
    # representation defect. AutoLISP apply requires a symbol or lambda list,
    # not the evaluated SUBR pointer produced by an unquoted lambda.
    $old=New-CadProbeExpressionV1 $Scope $Operation $Owner
    $needle='(setq emit (lambda (stage tick / stream)'
    if(([regex]::Matches($old,[regex]::Escape($needle))).Count-ne1){throw 'PROBE_V2_EXPECTED_EMITTER_FORM_NOT_UNIQUE'}
    $old.Replace($needle,"(setq emit '(lambda (stage tick / stream)")
}
