param(
    [string]$ProjectRoot = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$projectRootPath = [IO.Path]::GetFullPath($ProjectRoot)
$errors = [Collections.Generic.List[string]]::new()

function Resolve-ProjectFile([string]$RelativePath, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "$($Label)_PATH_EMPTY" }
    $path = [IO.Path]::GetFullPath((Join-Path $projectRootPath $RelativePath))
    if (-not $path.StartsWith($projectRootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($Label)_OUTSIDE_PROJECT:$RelativePath"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$($Label)_MISSING:$RelativePath" }
    return $path
}

function Read-ProjectJson([string]$RelativePath, [string]$Label) {
    $path = Resolve-ProjectFile $RelativePath $Label
    [pscustomobject]@{
        path = $path
        relative = $RelativePath.Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Add-Error([bool]$Condition, [string]$Code) {
    if ($Condition) { $errors.Add($Code) }
}

$indexRecord = Read-ProjectJson 'config/project_execution_index.json' 'ITERATION_INDEX'
$index = $indexRecord.value
Add-Error ($null -eq $index.iteration_learning) 'ITERATION_LEARNING_INDEX_MISSING'
if ($errors.Count -eq 0) {
    $learning = $index.iteration_learning
    foreach ($row in @(
        @{ path = [string]$learning.policy; label = 'ITERATION_POLICY' },
        @{ path = [string]$learning.pattern_registry; label = 'ITERATION_PATTERN_REGISTRY' },
        @{ path = [string]$learning.context_builder; label = 'ITERATION_CONTEXT_BUILDER' },
        @{ path = [string]$learning.assertion; label = 'ITERATION_ASSERTION' },
        @{ path = [string]$learning.proposal_builder; label = 'ITERATION_PROPOSAL_BUILDER' }
    )) {
        try { [void](Resolve-ProjectFile $row.path $row.label) } catch { $errors.Add($_.Exception.Message) }
    }
}

if ($errors.Count -eq 0) {
    $policyRecord = Read-ProjectJson ([string]$learning.policy) 'ITERATION_POLICY'
    $registryRecord = Read-ProjectJson ([string]$learning.pattern_registry) 'ITERATION_PATTERN_REGISTRY'
    $policy = $policyRecord.value
    $registry = $registryRecord.value
    Add-Error ([string]$policy.loop_id -cne [string]$index.loop_id) 'ITERATION_POLICY_LOOP_ID_MISMATCH'
    Add-Error ([string]$registry.loop_id -cne [string]$index.loop_id) 'ITERATION_REGISTRY_LOOP_ID_MISMATCH'
    Add-Error ([string]$registry.policy -cne [string]$learning.policy) 'ITERATION_REGISTRY_POLICY_POINTER_MISMATCH'
    Add-Error ([bool]$policy.command_experiment.requires_per_command_human_review) 'ITERATION_POLICY_ADDS_PER_COMMAND_HUMAN_REVIEW'
    Add-Error ([bool]$policy.command_experiment.requires_full_delivery_acceptance_before_experiment) 'ITERATION_POLICY_BLOCKS_EXPERIMENT_WITH_DELIVERY_ACCEPTANCE'
    Add-Error (-not [bool]$policy.command_experiment.do_not_treat_a_single_failure_as_a_command_family_ban) 'ITERATION_POLICY_SINGLE_FAILURE_BAN_ALLOWED'
    Add-Error ([int]$policy.recall.max_pattern_cards -lt 1 -or [int]$policy.recall.max_pattern_cards -gt 5) 'ITERATION_POLICY_PATTERN_LIMIT_INVALID'
    foreach ($path in @([string]$learning.policy, [string]$learning.pattern_registry)) {
        Add-Error ($path -in @($index.model_bootstrap_order)) "ITERATION_ARTIFACT_IN_MODEL_HOT_LAYER:$path"
        Add-Error ($path -in @($index.project_channel_bootstrap_order)) "ITERATION_ARTIFACT_IN_PROJECT_HOT_LAYER:$path"
        Add-Error ($path -in @($index.execution_channel_bootstrap_order)) "ITERATION_ARTIFACT_IN_EXECUTION_HOT_LAYER:$path"
        Add-Error ($path -in @($index.execution_authority_hash_order)) "ITERATION_ARTIFACT_IN_PRE_RUN_HASH_ORDER:$path"
    }

    $ids = @{}
    $allowedStages = @($policy.evidence_stages)
    $allowedDispositions = @($policy.reuse_dispositions)
    foreach ($record in @($registry.records)) {
        $id = [string]$record.id
        Add-Error ([string]::IsNullOrWhiteSpace($id)) 'ITERATION_PATTERN_ID_EMPTY'
        Add-Error ($ids.ContainsKey($id)) "ITERATION_PATTERN_ID_DUPLICATE:$id"
        $ids[$id] = $true
        Add-Error ([string]$record.record_status -cnotin @('admitted','superseded','retired','rejected')) "ITERATION_PATTERN_STATUS_INVALID:$id"
        Add-Error ([string]$record.evidence_stage -notin $allowedStages) "ITERATION_PATTERN_STAGE_INVALID:$id"
        Add-Error ([string]$record.reuse_disposition -notin $allowedDispositions) "ITERATION_PATTERN_DISPOSITION_INVALID:$id"
        Add-Error ([string]::IsNullOrWhiteSpace([string]$record.command_family)) "ITERATION_PATTERN_FAMILY_EMPTY:$id"
        Add-Error (@($record.tags).Count -eq 0) "ITERATION_PATTERN_TAGS_EMPTY:$id"
        Add-Error ([string]::IsNullOrWhiteSpace([string]$record.scope)) "ITERATION_PATTERN_SCOPE_EMPTY:$id"
        Add-Error ([string]::IsNullOrWhiteSpace([string]$record.non_generalization)) "ITERATION_PATTERN_BOUNDARY_EMPTY:$id"
        Add-Error ([string]::IsNullOrWhiteSpace([string]$record.next_use)) "ITERATION_PATTERN_NEXT_USE_EMPTY:$id"
        Add-Error ([string]$record.reuse_disposition -ceq 'reuse_in_declared_scope' -and [string]$record.evidence_stage -cne 'verified_scope') "ITERATION_PATTERN_REUSE_WITHOUT_VERIFIED_SCOPE:$id"
        foreach ($evidence in @($record.evidence)) {
            try {
                $evidencePath = Resolve-ProjectFile ([string]$evidence.path) "ITERATION_PATTERN_EVIDENCE:$id"
                $actual = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash
                Add-Error ($actual -cne [string]$evidence.sha256) "ITERATION_PATTERN_EVIDENCE_HASH_MISMATCH:$id"
            } catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }
    Add-Error (@($registry.records).Count -eq 0) 'ITERATION_PATTERN_REGISTRY_EMPTY'
}

if ($errors.Count -gt 0) { throw ('CAD_ITERATION_LEARNING_ASSERTION_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$index.loop_id
    pattern_card_count = @($registry.records).Count
    max_pattern_recall = [int]$policy.recall.max_pattern_cards
    per_command_human_review = [bool]$policy.command_experiment.requires_per_command_human_review
    learning_artifacts_are_targeted_recall_only = $true
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
