param(
    [Parameter(Mandatory = $true)][string]$WorkflowId,
    [Parameter(Mandatory = $true)][ValidateSet('production','validation')][string]$Mode,
    [string]$Entrypoint = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $projectRoot 'config\verified_workflow_registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw 'VERIFIED_WORKFLOW_REGISTRY_MISSING' }
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matches = @($registry.workflows | Where-Object { $_.id -ceq $WorkflowId })
if ($matches.Count -ne 1) { throw "WORKFLOW_ID_NOT_UNIQUE_OR_MISSING:$WorkflowId" }
$workflow = $matches[0]

if ($Mode -ceq 'production' -and $workflow.status -cne 'verified') {
    throw "WORKFLOW_NOT_VERIFIED_FOR_PRODUCTION:${WorkflowId}:$($workflow.status)"
}
if ($Mode -ceq 'validation' -and @('verified','validation_only') -cnotcontains [string]$workflow.status) {
    throw "WORKFLOW_NOT_ALLOWED_FOR_VALIDATION:${WorkflowId}:$($workflow.status)"
}

if ($Entrypoint) {
    # Optional variants are normalized in memory only, after status admission.
    # Required registration and explicit hash checks below remain unchanged.
    foreach ($optionalName in @('single_arc_adapter','batch_adapter','engine','engine_sha256','required_marker','forbidden_markers')) {
        if ($null -eq $workflow.implementation.PSObject.Properties[$optionalName]) {
            $workflow.implementation | Add-Member -NotePropertyName $optionalName -NotePropertyValue $null
        }
    }
    $resolved = [IO.Path]::GetFullPath($Entrypoint)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($projectRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'WORKFLOW_ENTRYPOINT_OUTSIDE_PROJECT'
    }
    $relative = $resolved.Substring([IO.Path]::GetFullPath($projectRoot).Length + 1).Replace('\','/')
    $blocked = @($registry.blocked_legacy_paths | ForEach-Object { ([string]$_).Replace('\','/') })
    if ($blocked -ccontains $relative) { throw "WORKFLOW_ENTRYPOINT_BLOCKED:$relative" }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw 'WORKFLOW_ENTRYPOINT_MISSING' }

    if ($workflow.status -ceq 'verified') {
        $expected = $null
        if ($workflow.implementation.single_arc_adapter -and ([string]$workflow.implementation.single_arc_adapter).Replace('\','/') -ceq $relative) {
            $expected = [string]$workflow.implementation.single_arc_sha256
        }
        elseif ($workflow.implementation.batch_adapter -and ([string]$workflow.implementation.batch_adapter).Replace('\','/') -ceq $relative) {
            $expected = [string]$workflow.implementation.batch_sha256
        }
        elseif ($workflow.implementation.engine -and ([string]$workflow.implementation.engine).Replace('\','/') -ceq $relative) {
            $expected = [string]$workflow.implementation.engine_sha256
        }
        if (-not $expected) { throw "ENTRYPOINT_NOT_REGISTERED_FOR_VERIFIED_WORKFLOW:$relative" }
        $actual = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        if ($actual -cne $expected) { throw "FROZEN_VERIFIED_ENTRYPOINT_HASH_MISMATCH:$relative" }

        if ($workflow.implementation.required_marker -or $workflow.implementation.forbidden_markers) {
            $text = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
            if ($workflow.implementation.required_marker -and $text.IndexOf([string]$workflow.implementation.required_marker, [StringComparison]::Ordinal) -lt 0) {
                throw 'VERIFIED_ENTRYPOINT_REQUIRED_MARKER_MISSING'
            }
            foreach ($marker in @($workflow.implementation.forbidden_markers)) {
                if ($text.IndexOf([string]$marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    throw "VERIFIED_ENTRYPOINT_FORBIDDEN_MARKER:$marker"
                }
            }
        }
    }
    elseif ($workflow.status -ceq 'validation_only') {
        $engine = ([string]$workflow.implementation.engine).Replace('\','/')
        if ($engine -cne $relative) { throw "VALIDATION_ENTRYPOINT_NOT_REGISTERED:$relative" }
        if ($workflow.implementation.engine_sha256) {
            $actual = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            if ($actual -cne [string]$workflow.implementation.engine_sha256) { throw 'VALIDATION_ENTRYPOINT_HASH_MISMATCH' }
        }
        if ($workflow.implementation.required_marker -or $workflow.implementation.forbidden_markers) {
            $text = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
            if ($workflow.implementation.required_marker -and
                $text.IndexOf([string]$workflow.implementation.required_marker, [StringComparison]::Ordinal) -lt 0) {
                throw 'VALIDATION_ENTRYPOINT_REQUIRED_MARKER_MISSING'
            }
            foreach ($marker in @($workflow.implementation.forbidden_markers)) {
                if ($text.IndexOf([string]$marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    throw "VALIDATION_ENTRYPOINT_FORBIDDEN_MARKER:$marker"
                }
            }
        }
    }
}

[pscustomobject]@{
    status = 'PASS'
    workflow_id = $WorkflowId
    workflow_status = [string]$workflow.status
    mode = $Mode
    entrypoint = $Entrypoint
}
