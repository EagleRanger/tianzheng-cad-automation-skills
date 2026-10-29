param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output = [IO.Path]::GetFullPath($OutputPath)
$specPath = [IO.Path]::GetFullPath($TaskSpecPath)

function Assert-InProject([string]$Path,[string]$Code) {
    if (-not $Path.StartsWith($project + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Code}_OUTSIDE_PROJECT"
    }
}

function Convert-LispString([string]$Value) {
    return $Value.Replace('\','/').Replace('"','\"')
}

Assert-InProject $output 'OUTPUT'
Assert-InProject $specPath 'TASK_SPEC'
if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
    throw 'TASK_SPEC_MISSING'
}

$builder = Join-Path $PSScriptRoot 'build_continuous_selection_bundle_v12.ps1'
$adapter = Join-Path $PSScriptRoot 'tdimarc_native_generation_prompt_staged_v2.lsp'
foreach ($path in @($builder,$adapter)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "TARGETED_DIRECT_STAGED_INPUT_MISSING:$path"
    }
}

$spec = Get-Content -LiteralPath $specPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedDrawing = [IO.Path]::GetFullPath([string]$spec.expected_drawing)
$summaryPath = [IO.Path]::GetFullPath([string]$spec.summary_path)
$detailsPath = [IO.Path]::GetFullPath([string]$spec.details_path)
$stageTracePath = [IO.Path]::GetFullPath([string]$spec.stage_trace_path)
foreach ($item in @(
        @{ value=$expectedDrawing; code='EXPECTED_DRAWING' },
        @{ value=$summaryPath; code='SUMMARY' },
        @{ value=$detailsPath; code='DETAILS' },
        @{ value=$stageTracePath; code='STAGE_TRACE' })) {
    Assert-InProject $item.value $item.code
}

$tasks = @($spec.tasks)
if ($tasks.Count -ne 1) { throw 'TASK_COUNT_MUST_EQUAL_ONE' }
$task = $tasks[0]
$handle = ([string]$task.source_handle).ToUpperInvariant()
$segmentType = ([string]$task.segment_type).ToUpperInvariant()
$segmentIndex = [int]$task.segment_index
$offset = [double]$task.offset
$group = ([string]$task.group).ToUpperInvariant()
if ($handle -notmatch '^[0-9A-F]+$') { throw "TASK_HANDLE_INVALID:$handle" }
if ($segmentType -cne 'ARC') { throw "TASK_TYPE_NOT_ARC:$segmentType" }
if ($segmentIndex -lt 0) { throw "TASK_SEGMENT_NEGATIVE:$segmentIndex" }
if ([Math]::Abs($offset) -lt 1e-9) { throw "TASK_OFFSET_ZERO:${handle}:$segmentIndex" }
if ($group -notin @('SHORE','ROAD')) { throw "TASK_GROUP_INVALID:$group" }
$offsetText = $offset.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
$lispTask = ('  (list "{0}" (list (list "ARC" {1})) {2} "{3}")' -f
    $handle,$segmentIndex,$offsetText,$group)

$directory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}

$temporary = $output + '.v12-base.tmp.lsp'
try {
    $base = & $builder -OutputPath $temporary -Offset 3.30225 -Group SHORE
    if ($base.status -cne 'PASS') { throw 'V12_BASE_BUILD_FAILED' }
    $text = [IO.File]::ReadAllText($temporary,[Text.Encoding]::UTF8)
    $declaration = '(defun cx:fb-run-one'
    $index = $text.LastIndexOf($declaration,[StringComparison]::Ordinal)
    if ($index -lt 0) { throw 'FINAL_ARC_DISPATCHER_NOT_FOUND' }
    $text = $text.Substring(0,$index) +
        '(defun cx:sp2-v12-run-one' +
        $text.Substring($index + $declaration.Length)
    $adapterText = [IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8)
    $tail = @"

(setq cx:*sp2-stage-trace-path* "$(Convert-LispString $stageTracePath)")
(setq cx:*full-batch-expected-drawing* "$(Convert-LispString $expectedDrawing)")
(setq cx:*full-batch-summary-path* "$(Convert-LispString $summaryPath)")
(setq cx:*full-batch-details-path* "$(Convert-LispString $detailsPath)")
(setq cx:*full-batch-cleanup-handles* '())
(setq cx:*full-batch-clean-slate-object-names* '())
(setq cx:*full-batch-save-on-success* nil)
(setq cx:*full-batch-tasks*
  (list
$lispTask
  ))
(c:CXTDIMARCFULLBATCH)
"@
    [IO.File]::WriteAllText(
        $output,$text + "`r`n" + $adapterText + $tail,
        [Text.UTF8Encoding]::new($false))
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

[pscustomobject]@{
    status = 'PASS'
    output = $output
    bytes = (Get-Item -LiteralPath $output).Length
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    task_count = 1
    external_load_count = 1
    cad_internal_batch_count = 1
    ordinary_kernel = 'V12_UNCHANGED'
    exceptional_kernel = 'DIRECT_COMMAND_CONTEXT_STAGED_TDIMARC_V2'
}

