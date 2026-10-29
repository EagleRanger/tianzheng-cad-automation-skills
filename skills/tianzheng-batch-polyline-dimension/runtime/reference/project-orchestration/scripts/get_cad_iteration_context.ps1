param(
    [string]$ProjectRoot = '',
    [Parameter(Mandatory = $true)]
    [string]$CommandFamily,
    [string[]]$Tags = @(),
    [int]$MaxPatterns = 0,
    [ValidateSet('Current','Diagnostic','History')]
    [string]$RecallLayer = 'Current',
    [switch]$RequireRegisteredRoute,
    [switch]$TechnicalFirst,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$projectRootPath = [IO.Path]::GetFullPath($ProjectRoot)

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
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Normalize-Token([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

$index = Read-ProjectJson 'config/project_execution_index.json' 'ITERATION_INDEX'
if ($null -eq $index.iteration_learning) { throw 'ITERATION_LEARNING_INDEX_MISSING' }
$learning = $index.iteration_learning
$policy = Read-ProjectJson ([string]$learning.policy) 'ITERATION_POLICY'
$registry = Read-ProjectJson ([string]$learning.pattern_registry) 'ITERATION_PATTERN_REGISTRY'
$recovery = Read-ProjectJson ([string]$index.current_recovery_contract) 'ITERATION_RECOVERY'
$terminal = Read-ProjectJson ([string]$index.current_execution_return) 'ITERATION_TERMINAL_RETURN'
$binding = Read-ProjectJson ([string]$index.current_task_binding) 'ITERATION_TASK_BINDING'
$handoff = Read-ProjectJson 'config/current_execution_handoff.json' 'ITERATION_HANDOFF'
$components = Read-ProjectJson ([string]$index.component_registry) 'ITERATION_COMPONENTS'
$routing = Read-ProjectJson 'config/cad_command_research_routing_v1.json' 'ITERATION_COMMAND_ROUTING'
$architecture = Read-ProjectJson ([string]$index.development_architecture) 'ITERATION_DEVELOPMENT_ARCHITECTURE'
$bootstrap = $policy.shared_research_bootstrap
if ($null -eq $bootstrap -or [string]$bootstrap.id -cne 'CAD_COMMAND_RESEARCH_SHARED_BOOTSTRAP_V1') {
    throw 'ITERATION_SHARED_RESEARCH_BOOTSTRAP_MISSING'
}

$routeProperty = $routing.routes.PSObject.Properties | Where-Object { $_.Name -ceq $CommandFamily } | Select-Object -First 1
if ($RequireRegisteredRoute -and $null -eq $routeProperty) { throw "ITERATION_COMMAND_ROUTE_UNKNOWN:$CommandFamily" }
$route = if ($null -ne $routeProperty) { $routeProperty.Value } else { $null }
if ($RequireRegisteredRoute -and [string]$route.shared_bootstrap_profile -cne [string]$bootstrap.id) {
    throw "ITERATION_ROUTE_SHARED_BOOTSTRAP_UNBOUND:$CommandFamily"
}

$allowedMaximum = [int]$policy.recall.max_pattern_cards
if ($allowedMaximum -lt 1) { throw 'ITERATION_POLICY_MAX_PATTERN_CARDS_INVALID' }
if ($MaxPatterns -lt 1) { $MaxPatterns = $allowedMaximum }
if ($MaxPatterns -gt $allowedMaximum) { throw "ITERATION_PATTERN_LIMIT_EXCEEDED:$MaxPatterns>$allowedMaximum" }

$queryTokens = @((Normalize-Token $CommandFamily)) + @($Tags | ForEach-Object { Normalize-Token ([string]$_) }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if (@($queryTokens).Count -eq 0) { throw 'ITERATION_QUERY_EMPTY' }

$capabilityRecall = $bootstrap.PSObject.Properties['shared_capability_recall']
if ($null -eq $capabilityRecall -or [string]$capabilityRecall.Value.id -cne 'CAD-SHARED-CAPABILITY-RECALL-V1') {
    throw 'ITERATION_SHARED_CAPABILITY_RECALL_MISSING'
}
$capabilityRecall = $capabilityRecall.Value
$capabilityMaximum = [int]$capabilityRecall.max_sources
if ($capabilityMaximum -lt 1) { throw 'ITERATION_SHARED_CAPABILITY_RECALL_LIMIT_INVALID' }
$capabilityMatches = foreach ($source in @($capabilityRecall.sources)) {
    $sourceTags = @($source.tags | ForEach-Object { Normalize-Token ([string]$_) })
    $defaultProperty = $source.PSObject.Properties['default_for_every_command_research']
    $score = if ($null -ne $defaultProperty -and [bool]$defaultProperty.Value) { 1 } else { 0 }
    $matchedTags = @()
    foreach ($token in $queryTokens) {
        if ($sourceTags -contains $token) {
            $score += 10
            $matchedTags += $token
        }
    }
    if ($score -gt 0) {
        $path = Resolve-ProjectFile ([string]$source.path) ('ITERATION_SHARED_CAPABILITY_' + [string]$source.id)
        [pscustomobject]@{ score = $score; source = $source; path = $path; matched_tags = @($matchedTags | Select-Object -Unique) }
    }
}
$sharedCapabilitySources = @($capabilityMatches | Sort-Object -Property @{Expression='score'; Descending=$true}, @{Expression={ [string]$_.source.id }; Descending=$false} | Select-Object -First $capabilityMaximum | ForEach-Object {
    [pscustomobject]@{
        id = [string]$_.source.id
        path = [string]$_.source.path
        sha256 = (Get-FileHash -LiteralPath $_.path -Algorithm SHA256).Hash
        matched_tags = $_.matched_tags
        reference_role = [string]$_.source.reference_role
        scope = [string]$_.source.scope
        grants_runtime_authority = $false
    }
})

$scored = foreach ($record in @($registry.records)) {
    $score = 0
    $family = Normalize-Token ([string]$record.command_family)
    if ($family -eq (Normalize-Token $CommandFamily)) { $score += 100 }
    $recordTags = @($record.tags | ForEach-Object { Normalize-Token ([string]$_) })
    foreach ($token in $queryTokens) {
        if ($recordTags -contains $token) { $score += 10 }
    }
    if ($score -gt 0) {
        [pscustomobject]@{ score = $score; record = $record }
    }
}

$effectiveLayer = if ($RecallLayer -eq 'Current' -and @($Tags).Count -gt 0) { 'Diagnostic' } else { $RecallLayer }
$ranked = @($scored | Sort-Object -Property @{Expression='score'; Descending=$true}, @{Expression={ [string]$_.record.id }; Descending=$false})
function Test-CurrentPattern($Record) {
    $replacement = $Record.PSObject.Properties['superseded_by']
    return ([string]$Record.record_status -ceq 'admitted' -and ($null -eq $replacement -or [string]::IsNullOrWhiteSpace([string]$replacement.Value)))
}
$eligible = @($ranked | Where-Object {
    $current = Test-CurrentPattern $_.record
    $effectiveLayer -eq 'History' -or ($current -and ($effectiveLayer -eq 'Diagnostic' -or
        ([string]$_.record.evidence_stage -ceq 'verified_scope' -and [string]$_.record.reuse_disposition -ceq 'reuse_in_declared_scope')))
})
$patterns = @($eligible | Select-Object -First $MaxPatterns | ForEach-Object {
    [pscustomobject]@{
        id = [string]$_.record.id
        record_status = [string]$_.record.record_status
        superseded_by = if ($null -ne $_.record.PSObject.Properties['superseded_by']) { $_.record.superseded_by } else { $null }
        retrieval_role = if (-not (Test-CurrentPattern $_.record)) { 'historical_only' } elseif ([string]$_.record.reuse_disposition -ceq 'reuse_in_declared_scope') { 'scope_bounded_reference' } else { 'diagnostic_counterexample' }
        grants_runtime_authority = $false
        score = [int]$_.score
        title = [string]$_.record.title
        command_family = [string]$_.record.command_family
        evidence_stage = [string]$_.record.evidence_stage
        reuse_disposition = [string]$_.record.reuse_disposition
        scope = [string]$_.record.scope
        observed_fact = [string]$_.record.observed_fact
        next_use = [string]$_.record.next_use
        non_generalization = [string]$_.record.non_generalization
        evidence = @($_.record.evidence)
    }
})
$pitfalls = @($ranked | Where-Object { (Test-CurrentPattern $_.record) -and [string]$_.record.reuse_disposition -cne 'reuse_in_declared_scope' } | Select-Object -First $MaxPatterns | ForEach-Object {
    [pscustomobject]@{ id = [string]$_.record.id; scope = [string]$_.record.scope; next_use = [string]$_.record.next_use; non_generalization = [string]$_.record.non_generalization; source_pointer = ([string]$learning.pattern_registry + '#'+ [string]$_.record.id) }
})

$activeComponentId = [string]$recovery.active_component.id
$componentRows = @($components.components)
$activeComponent = @($componentRows | Where-Object { [string]$_.id -ceq $activeComponentId } | Select-Object -First 1)
# Keep current component semantics, not its accumulated experiment transcript.
$activeComponentBrief = @($activeComponent | ForEach-Object {
    $brief = [ordered]@{ source_pointer = ([string]$index.component_registry + '#' + [string]$_.id) }
    foreach ($property in $_.PSObject.Properties) {
        if ($property.Name -notmatch '^(validation_|latest_validation_)') { $brief[$property.Name] = $property.Value }
    }
    [pscustomobject]$brief
})
function Resolve-ComponentSet {
    param([object[]]$Ids, [string]$Label, [bool]$RequireReusable)
    $resolved = @()
    foreach ($rawId in @($Ids)) {
        $id = [string]$rawId
        $row = @($componentRows | Where-Object { [string]$_.id -ceq $id })
        if ($row.Count -ne 1) { throw "$($Label)_COMPONENT_IDENTITY_INVALID:$($id):$($row.Count)" }
        if ($RequireReusable -and [string]$row[0].status -notin @('verified','active_with_regression')) {
            throw "$($Label)_COMPONENT_NOT_REUSABLE:$($id):$($row[0].status)"
        }
        $resolved += $row[0]
    }
    return @($resolved)
}
$requiredComponents = @(Resolve-ComponentSet -Ids @($bootstrap.required_component_ids) -Label 'ITERATION_REQUIRED' -RequireReusable $true)
$recallOnlyComponents = @(Resolve-ComponentSet -Ids @($bootstrap.recall_only_component_ids) -Label 'ITERATION_RECALL_ONLY' -RequireReusable $false)
$sharedTextComponent = @(Resolve-ComponentSet -Ids @('CAD-NATIVE-TEXT-READBACK-V1') -Label 'ITERATION_SHARED_TEXT' -RequireReusable $false)[0]
$sharedTextEntry = Resolve-ProjectFile ([string]$sharedTextComponent.entry) 'ITERATION_SHARED_TEXT_ENTRY'
$sharedTextReadback = & $sharedTextEntry -ProjectRoot $projectRootPath -Mode Describe -NoExplode
$authorityPointers = [ordered]@{}
foreach ($pointer in @($bootstrap.required_authority_pointers)) {
    $relative = [string]$index.$pointer
    [void](Resolve-ProjectFile $relative ('ITERATION_AUTHORITY_' + ([string]$pointer).ToUpperInvariant()))
    $authorityPointers[[string]$pointer] = $relative
}
$architectureGoalIds = @($architecture.detail_goals | ForEach-Object { [string]$_.id })
if ($architectureGoalIds -cnotcontains 'D0_LIFECYCLE' -or $architectureGoalIds -cnotcontains 'D1_RUNTIME_INVENTORY_CONTRACT') {
    throw 'ITERATION_DEVELOPMENT_ARCHITECTURE_D0_D1_MISSING'
}

$sharedContracts = Read-ProjectJson ([string]$index.shared_contract_knowledge_base) 'ITERATION_SHARED_CONTRACTS'
$aestheticPointer = $sharedContracts.design_policies.annotation_aesthetic
$aestheticPath = Resolve-ProjectFile ([string]$aestheticPointer.path) 'ITERATION_ANNOTATION_AESTHETIC'
$aestheticPolicy = Get-Content -LiteralPath $aestheticPath -Raw -Encoding UTF8 | ConvertFrom-Json
$acceptancePointer = $sharedContracts.design_policies.acceptance_reuse
$acceptancePath = Resolve-ProjectFile ([string]$acceptancePointer.path) 'ITERATION_ACCEPTANCE_REUSE'
$acceptancePolicy = Get-Content -LiteralPath $acceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json

$notices = @()
if ([string]$handoff.status -eq 'READY') { $notices += 'READY_IN_FLIGHT__LATEST_TERMINAL_IS_PREVIOUS_EVIDENCE_NOT_CURRENT_RUN_RESULT' }
if ([string]$handoff.status -eq 'TERMINAL_RETURNED' -and [string]$handoff.run_id -cne [string]$terminal.run_id) { $notices += 'CURRENT_HANDOFF_TERMINAL_IDENTITY_CONFLICT__READ_CURRENT_AUTHORITY_BEFORE_ACTING' }
if ([string]$recovery.active_component.status -ne [string]$activeComponent[0].status -or [string]$recovery.active_component.version -ne [string]$activeComponent[0].version) { $notices += 'ACTIVE_COMPONENT_METADATA_CONFLICT__DO_NOT_PROMOTE_FROM_HISTORY' }
$result = [pscustomobject]@{
    schema_version = 2
    status = 'PASS'
    loop_id = [string]$index.loop_id
    query = [pscustomobject]@{
        command_family = $CommandFamily
        tags = @($Tags)
        max_pattern_cards = $MaxPatterns
        recall_layer = $effectiveLayer
    }
    command_route = if ($null -eq $route) { $null } else {
        [pscustomobject]@{
            route_id = $CommandFamily
            owner_lane = [string]$route.owner_lane
            research_thread_id = [string]$route.research_thread_id
            command_package_id = [string]$route.command_package_id
            shared_bootstrap_profile = [string]$route.shared_bootstrap_profile
        }
    }
    shared_research_bootstrap = [pscustomobject]@{
        id = [string]$bootstrap.id
        startup_sequence = @($bootstrap.startup_sequence)
        native_access_contract = $bootstrap.native_access_contract
        required_authority_pointers = [pscustomobject]$authorityPointers
        required_components = $requiredComponents
        recall_only_components = $recallOnlyComponents
        native_text_readback = $sharedTextReadback
        shared_capability_recall = [pscustomobject]@{
            id = [string]$capabilityRecall.id
            sources = $sharedCapabilitySources
            non_gating_notice = [string]$capabilityRecall.non_gating_notice
        }
        cross_command_lessons = @($bootstrap.cross_command_lessons)
        performance_policy = [pscustomobject]@{
            source_pointer = ([string]$index.shared_contract_knowledge_base + '#performance_policy')
            policy = $sharedContracts.performance_policy
            grants_runtime_authority = $false
            adds_runtime_gate = $false
        }
        annotation_aesthetic = [pscustomobject]@{
            path = [string]$aestheticPointer.path
            sha256 = (Get-FileHash -LiteralPath $aestheticPath -Algorithm SHA256).Hash
            policy = $aestheticPolicy
        }
        acceptance_reuse = [pscustomobject]@{
            path = [string]$acceptancePointer.path
            sha256 = (Get-FileHash -LiteralPath $acceptancePath -Algorithm SHA256).Hash
            profile = $acceptancePolicy.reuse_profile
            test_profiles = $acceptancePolicy.profiles
            composition_contract = [pscustomobject]@{
                path = [string]$acceptancePointer.composition_contract
                sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot ([string]$acceptancePointer.composition_contract)) -Algorithm SHA256).Hash
                mode_source = 'governance.acceptance_mode'
                ordinary_test_requires_no_final_claim = $true
            }
            human_review_policy = [string]$index.human_review_policy
            return_delivery_policy = [string]$index.return_delivery_policy
        }
        task_coordination = $routing.coordination
        forbidden = @($bootstrap.forbidden)
    }
    current_contract = [pscustomobject]@{
        objective = [string]$recovery.current_objective
        source_pointer = [string]$index.current_recovery_contract
        focus_lock = $recovery.focus_lock
        active_component = $recovery.active_component
        next_checkpoint = [string]$recovery.next_checkpoint
        task_binding_pointer = [string]$index.current_task_binding
        recovery_qualification_review = if ($null -ne $binding.PSObject.Properties['recovery_qualification_review']) { $binding.recovery_qualification_review } else { $null }
    }
    current_execution = [pscustomobject]@{ source_pointer = 'config/current_execution_handoff.json'; status = [string]$handoff.status; run_id = [string]$handoff.run_id; handoff_id = [string]$handoff.handoff_id; runtime_authority_is_source_not_this_recall = $true }
    latest_terminal = [pscustomobject]@{
        run_id = [string]$terminal.run_id
        terminal_state = [string]$terminal.terminal_state
        decisive_fact = [string]$terminal.decisive_fact
    }
    active_component_record = $activeComponentBrief
    verified_or_regression_components = @($requiredComponents | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; version = [string]$_.version; status = [string]$_.status; details_pointer = ('shared_research_bootstrap.required_components#' + [string]$_.id) } })
    relevant_patterns = $patterns
    recurrence_closure = $policy.recurrence_closure
    necessary_pitfalls = $pitfalls
    retrieval_notices = @($notices)
    authority_precedence = @('current_user_instruction','current_project_contract_and_direct_evidence','current_recovery_and_task_binding','declared_component_scope','related_counterexamples','historical_reference_only')
    history_lookup = $index.history_lookup
    non_gating_notice = [string]$policy.recall.non_gating_notice
}
if ($TechnicalFirst) {
    # A model-only view. Preserve the existing detailed result for legacy consumers.
    # Do not apply a top-N limit to applicable negative or unresolved evidence.
    $allPitfalls = @($ranked | Where-Object {
        [string]$_.record.reuse_disposition -cne 'reuse_in_declared_scope'
    } | ForEach-Object { $_.record })
    $componentPointers = @($requiredComponents + $recallOnlyComponents | ForEach-Object {
        [pscustomobject]@{
            id = $_.id; version = $_.version; status = $_.status; entry = $_.entry
            source_pointer = ([string]$index.component_registry + '#' + [string]$_.id)
            read_declared_scope_before_use = $true
        }
    })
    $routeCheckpoint = switch ($CommandFamily) {
        'shared_annotation_interface_read' { 'interface_research_checkpoint' }
        'batch_radius_dimension' { 'radius_stage_checkpoint' }
        { $_ -like 'sheet_layout*' } { 'sheet_layout_stage_checkpoint' }
        default { 'focus_lock' }
    }
    $checkpoint = $recovery.PSObject.Properties[$routeCheckpoint]
    $result = [pscustomobject][ordered]@{
        schema_version = 1
        view = 'TECHNICAL_FIRST_MODEL_RECALL_ONLY'
        command_route = $result.command_route
        verified_technical_details = @($patterns | Where-Object {
            $_.evidence_stage -eq 'verified_scope' -and $_.reuse_disposition -eq 'reuse_in_declared_scope' -and $_.record_status -eq 'admitted' -and -not $_.superseded_by
        })
        scoped_counterexamples = $allPitfalls
        counterexample_rule = 'Read scope, evidence stage and superseded_by; negative evidence forbids repeating the disproven exact profile, not the entire command family. Unresolved evidence is not a proven cause.'
        shared_technical_sources = $sharedCapabilitySources
        components = $componentPointers
        native_access = $bootstrap.native_access_contract
        shared_lessons = $bootstrap.cross_command_lessons
        recurrence_closure = $policy.recurrence_closure
        current_route_checkpoint = [pscustomobject]@{
            source_pointer = ([string]$index.current_recovery_contract + '#' + $routeCheckpoint)
            value = if ($null -eq $checkpoint) { $null } else { $checkpoint.Value }
            current_user_and_direct_evidence_take_precedence = $true
        }
        current_execution = $result.current_execution
        latest_terminal = $result.latest_terminal
        notices = $result.retrieval_notices
        necessary_contracts = [pscustomobject]@{
            scope_and_protection = $index.current_task_binding
            acceptance = $index.acceptance_gates
            aesthetic = $aestheticPointer.path
            forbidden_routes = $index.rejected_legacy_entrypoints
            native_semantics = 'ARC=angle_degrees; LINE=length; radius=native_radius; no_text_override_as_semantic_fix'
            execution = 'exact_owner_original_protection_single_executor_no_blind_retry_true_native_and_visual_acceptance'
        }
        history = 'No full chat, prior tool output, wait narration or unrelated command history by default; inspect exact evidence pointers only when the present decision needs them.'
        grants_runtime_authority = $false
    }
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Depth 30 }
