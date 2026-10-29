param(
    [Parameter(Mandatory = $true)][string]$ExecutionContractPath,
    [string]$TaskSpecPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Resolve-ProjectFile([string]$Raw, [string]$Code) {
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $Raw)) }
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "${Code}_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}

function Get-TextSha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','') }
    finally { $sha.Dispose() }
}
function Get-SharedFileSha256([string]$Path) {
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$contractPath = Resolve-ProjectFile $ExecutionContractPath 'COMPONENT_CONTRACT'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$contract.schema_version -ne 1 -or [string]$contract.status -cne 'PREPARED') { throw 'COMPONENT_CONTRACT_SCHEMA_OR_STATUS_INVALID' }

$registryPath = Resolve-ProjectFile ([string]$contract.component.registry_path) 'COMPONENT_REGISTRY'
if ((Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash -cne [string]$contract.component.registry_sha256) { throw 'COMPONENT_REGISTRY_HASH_MISMATCH' }
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matches = @($registry.components | Where-Object { [string]$_.id -ceq [string]$contract.component.id })
if ($matches.Count -ne 1) { throw 'COMPONENT_ID_NOT_UNIQUE' }
$componentJson = $matches[0] | ConvertTo-Json -Depth 30 -Compress
if ((Get-TextSha256 $componentJson) -cne [string]$contract.component.record_sha256) { throw 'COMPONENT_RECORD_HASH_MISMATCH' }
if ([string]$matches[0].version -cne [string]$contract.component.version) { throw 'COMPONENT_VERSION_MISMATCH' }
if (@($matches[0].allowed_workflows).Count -gt 0 -and [string]$contract.workflow.id -notin @($matches[0].allowed_workflows)) { throw 'COMPONENT_WORKFLOW_NOT_ALLOWED' }
if (@($matches[0].allowed_actions).Count -gt 0 -and [string]$contract.workflow.action -notin @($matches[0].allowed_actions)) { throw 'COMPONENT_ACTION_NOT_ALLOWED' }

$scopePath = Resolve-ProjectFile ([string]$contract.scope.path) 'COMPONENT_SCOPE'
if ((Get-FileHash -LiteralPath $scopePath -Algorithm SHA256).Hash -cne [string]$contract.scope.sha256) { throw 'COMPONENT_SCOPE_HASH_MISMATCH' }
$scope = Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$scope.scope_id -cne [string]$contract.scope.id -or [string]$scope.component_id -cne [string]$contract.component.id) { throw 'COMPONENT_SCOPE_IDENTITY_MISMATCH' }
if ([string]$scope.governing_phase_id -cne [string]$contract.governing_phase_id) { throw 'COMPONENT_SCOPE_PHASE_MISMATCH' }

$baselinePath = Resolve-ProjectFile ([string]$contract.baseline.path) 'COMPONENT_BASELINE'
if ((Get-SharedFileSha256 $baselinePath) -cne [string]$contract.baseline.sha256) { throw 'COMPONENT_BASELINE_HASH_MISMATCH' }
if ([string]$scope.baseline.sha256 -cne [string]$contract.baseline.sha256) { throw 'COMPONENT_SCOPE_BASELINE_MISMATCH' }

$frozen = @($scope.frozen_annotation_handles | ForEach-Object { ([string]$_).ToUpperInvariant() })
$mutableHandles = @($scope.mutable_annotation_handles | ForEach-Object { ([string]$_).ToUpperInvariant() })
$obsoleteHandles = @($scope.obsolete_annotation_handles | ForEach-Object { ([string]$_).ToUpperInvariant() })
$obstacleHandles = @($scope.obstacle_only_annotation_handles | ForEach-Object { ([string]$_).ToUpperInvariant() })
if (@($mutableHandles | Where-Object { $_ -in $frozen -or $_ -in $obstacleHandles }).Count -gt 0) { throw 'COMPONENT_SCOPE_MUTABLE_OVERLAP' }
if (@($obsoleteHandles | Where-Object { $_ -in $frozen -or $_ -in $obstacleHandles -or $_ -in $mutableHandles }).Count -gt 0) { throw 'COMPONENT_SCOPE_OBSOLETE_OVERLAP' }
if ($frozen.Count -ne [int]$contract.scope.frozen_annotation_count) { throw 'COMPONENT_SCOPE_FROZEN_COUNT_MISMATCH' }

$gateConfigPath = Resolve-ProjectFile ([string]$contract.acceptance.gate_config_path) 'ACCEPTANCE_GATE_CONFIG'
if ((Get-FileHash -LiteralPath $gateConfigPath -Algorithm SHA256).Hash -cne [string]$contract.acceptance.gate_config_sha256) { throw 'ACCEPTANCE_GATE_CONFIG_HASH_MISMATCH' }
$gateConfig = Get-Content -LiteralPath $gateConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$knownGates = @($gateConfig.gates | ForEach-Object { [string]$_.id })
foreach ($gate in @($contract.acceptance.required_gate_ids)) {
    if ([string]$gate -notin $knownGates) { throw "UNKNOWN_ACCEPTANCE_GATE:$gate" }
}
$componentRequired = @($matches[0].required_acceptance_gate_ids | ForEach-Object { [string]$_ })
$contractRequired = @($contract.acceptance.required_gate_ids | ForEach-Object { [string]$_ })
if (@($componentRequired | Where-Object { $_ -notin $contractRequired }).Count -gt 0) { throw 'COMPONENT_REQUIRED_ACCEPTANCE_GATE_MISSING' }

if (-not [string]::IsNullOrWhiteSpace($TaskSpecPath)) {
    $specPath = Resolve-ProjectFile $TaskSpecPath 'COMPONENT_TASK_SPEC'
    $specText = Get-Content -LiteralPath $specPath -Raw -Encoding UTF8
    $header = @($specText -split "`r?`n")[0]
    if ($header -ceq "HANDLE`tGRIP_INDEX`tDX`tDY`tDZ") {
        $rows = @(Import-Csv -LiteralPath $specPath -Delimiter "`t")
        if ($rows.Count -eq 0) { throw 'COMPONENT_TASK_SPEC_EMPTY' }
        foreach ($row in $rows) {
            $handle = ([string]$row.HANDLE).ToUpperInvariant()
            if ($handle -notin $mutableHandles) { throw "COMPONENT_TASK_TOUCHES_NON_MUTABLE_HANDLE:$handle" }
            if ([int]$row.GRIP_INDEX -ne 0) { throw "COMPONENT_TASK_TOUCHES_ASSOCIATION_GRIP:${handle}:$($row.GRIP_INDEX)" }
        }
    } else {
        # Parse every typed segment inside each source task.  The earlier
        # expression only captured the first segment of a multi-segment task,
        # which made a valid full-batch contract impossible to express.
        $pairs = @()
        $taskMatches = @([regex]::Matches(
            $specText,
            '\("(?<handle>[0-9A-F]+)"\s+\((?<segments>(?:\s*\("(?:ARC|LINE)"\s+\d+\)\s*)+)\)\s+[-+]?(?:\d+(?:\.\d*)?|\.\d+)',
            'IgnoreCase'
        ))
        foreach ($taskMatch in $taskMatches) {
            $handle = $taskMatch.Groups['handle'].Value
            foreach ($segmentMatch in [regex]::Matches(
                $taskMatch.Groups['segments'].Value,
                '\("(?<type>ARC|LINE)"\s+(?<index>\d+)\)',
                'IgnoreCase'
            )) {
                $pairs += [pscustomobject]@{
                    Handle = $handle
                    Type = $segmentMatch.Groups['type'].Value
                    Index = $segmentMatch.Groups['index'].Value
                }
            }
        }
        $mutablePairs = @($scope.mutable_source_segments | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.handle) } | ForEach-Object { "$(([string]$_.handle).ToUpperInvariant()):$([int]$_.segment):$(([string]$_.type).ToUpperInvariant())" })
        if ($pairs.Count -eq 0 -and ($mutablePairs.Count -ne 0 -or [int]$scope.maximum_created_count -ne 0)) {
            throw 'COMPONENT_TASK_SPEC_UNRECOGNIZED'
        }
        $actualPairs = @()
        foreach ($pair in $pairs) {
            $key = "$($pair.Handle.ToUpperInvariant()):$([int]$pair.Index):$($pair.Type.ToUpperInvariant())"
            if ($key -notin $mutablePairs) { throw "COMPONENT_TASK_TOUCHES_NON_MUTABLE_SEGMENT:$key" }
            $actualPairs += $key
        }
        $expectedPairSet = @($mutablePairs | Sort-Object -Unique)
        $actualPairSet = @($actualPairs | Sort-Object -Unique)
        if ($actualPairs.Count -ne $actualPairSet.Count -or
            $actualPairSet.Count -ne $expectedPairSet.Count -or
            @($expectedPairSet | Where-Object { $_ -notin $actualPairSet }).Count -gt 0 -or
            @($actualPairSet | Where-Object { $_ -notin $expectedPairSet }).Count -gt 0) {
            throw 'COMPONENT_TASK_SOURCE_SEGMENT_SET_MISMATCH'
        }
        if ($pairs.Count -gt 0 -and [int]$scope.maximum_created_count -eq 0) { throw 'COMPONENT_SCOPE_FORBIDS_NEW_ANNOTATION_GENERATION' }
        if ($pairs.Count -gt [int]$scope.maximum_created_count) { throw 'COMPONENT_TASK_EXCEEDS_MAXIMUM_CREATED_COUNT' }

        $cleanupMatch = [regex]::Match(
            $specText,
            "(?is)\(setq\s+cx:\*full-batch-cleanup-handles\*\s+'\((?<body>[^)]*)\)\s*\)"
        )
        if (-not $cleanupMatch.Success) { throw 'COMPONENT_TASK_CLEANUP_HANDLES_MISSING' }
        $cleanupHandles = @(
            [regex]::Matches($cleanupMatch.Groups['body'].Value, '"(?<handle>[0-9A-F]+)"', 'IgnoreCase') |
                ForEach-Object { $_.Groups['handle'].Value.ToUpperInvariant() }
        )
        if ($cleanupHandles.Count -gt [int]$scope.maximum_deleted_count) { throw 'COMPONENT_TASK_EXCEEDS_MAXIMUM_DELETED_COUNT' }
        if (@($cleanupHandles | Where-Object { $_ -notin $obsoleteHandles }).Count -gt 0) { throw 'COMPONENT_TASK_DELETES_NON_OBSOLETE_HANDLE' }
        $requiredCleanup = @($scope.required_cleanup_handles | ForEach-Object { ([string]$_).ToUpperInvariant() })
        if (@($requiredCleanup | Where-Object { $_ -notin $cleanupHandles }).Count -gt 0 -or
            @($cleanupHandles | Where-Object { $_ -notin $requiredCleanup }).Count -gt 0) {
            throw 'COMPONENT_TASK_CLEANUP_SET_MISMATCH'
        }
        $cleanSlateMatch = [regex]::Match(
            $specText,
            "(?is)\(setq\s+cx:\*full-batch-clean-slate-object-names\*\s+'\((?<body>[^)]*)\)\s*\)"
        )
        if ($cleanSlateMatch.Success -and [regex]::IsMatch($cleanSlateMatch.Groups['body'].Value, '"[^\"]+"')) {
            throw 'COMPONENT_TASK_BROAD_CLEAN_SLATE_FORBIDDEN'
        }
        if ([string]$contract.workflow.action -ceq 'TDIMARC_TARGETED_REPLACEMENT') {
            $layoutMatch = [regex]::Match(
                $specText,
                "(?is)\(setq\s+cx:\*targeted-replacement-layouts\*\s+'\((?<body>.*?)\)\s*\)"
            )
            if (-not $layoutMatch.Success) { throw 'COMPONENT_TARGETED_LAYOUTS_MISSING' }
            $layoutRows = @([regex]::Matches(
                $layoutMatch.Groups['body'].Value,
                '\("(?<handle>[0-9A-F]+)"\s+(?<index>\d+)\s+(?<fraction>[-+]?(?:\d+(?:\.\d*)?|\.\d+))\s+(?<offset>[-+]?(?:\d+(?:\.\d*)?|\.\d+))\s+"(?<group>[A-Z]+)"\)?',
                'IgnoreCase'
            ))
            $expectedLayouts = @($scope.targeted_layouts)
            if ($layoutRows.Count -ne $expectedLayouts.Count) { throw 'COMPONENT_TARGETED_LAYOUT_COUNT_MISMATCH' }
            $actualLayoutKeys = @()
            foreach ($row in $layoutRows) {
                $fraction = [double]::Parse($row.Groups['fraction'].Value, [Globalization.CultureInfo]::InvariantCulture)
                $offset = [double]::Parse($row.Groups['offset'].Value, [Globalization.CultureInfo]::InvariantCulture)
                if ($fraction -le 0.0 -or $fraction -ge 1.0 -or [math]::Abs($offset) -le 1e-9) { throw 'COMPONENT_TARGETED_LAYOUT_VALUE_INVALID' }
                $key = "$($row.Groups['handle'].Value.ToUpperInvariant()):$([int]$row.Groups['index'].Value)"
                if ($key -in $actualLayoutKeys) { throw 'COMPONENT_TARGETED_LAYOUT_DUPLICATE' }
                $actualLayoutKeys += $key
                $expected = @($expectedLayouts | Where-Object {
                    ([string]$_.handle).ToUpperInvariant() -ceq $row.Groups['handle'].Value.ToUpperInvariant() -and
                    [int]$_.segment -eq [int]$row.Groups['index'].Value
                })
                if ($expected.Count -ne 1) { throw "COMPONENT_TARGETED_LAYOUT_UNAUTHORIZED:$key" }
                if ([math]::Abs($fraction - [double]$expected[0].pick_fraction) -gt 1e-9 -or
                    [math]::Abs($offset - [double]$expected[0].signed_offset) -gt 1e-9 -or
                    ([string]$expected[0].group).ToUpperInvariant() -cne $row.Groups['group'].Value.ToUpperInvariant()) {
                    throw "COMPONENT_TARGETED_LAYOUT_PARAMETER_MISMATCH:$key"
                }
            }
        }
    }
}

[pscustomobject]@{
    status = 'PASS'
    contract_id = [string]$contract.contract_id
    component_id = [string]$contract.component.id
    governing_phase_id = [string]$contract.governing_phase_id
    frozen_annotation_count = $frozen.Count
    required_gate_count = @($contract.acceptance.required_gate_ids).Count
}
