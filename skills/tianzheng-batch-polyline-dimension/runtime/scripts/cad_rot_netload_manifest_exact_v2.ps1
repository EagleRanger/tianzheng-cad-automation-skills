param(
    [Parameter(Mandatory = $true)][string]$DocumentName,
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][long]$WindowHandle,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [int]$DocumentBindTimeoutSeconds = 12,
    [int]$CompletionTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifestFull = [IO.Path]::GetFullPath($ManifestPath)
$ownerPath = [IO.Path]::GetFullPath($OwnerStatePath)
$projectPrefix = $root + [IO.Path]::DirectorySeparatorChar
foreach ($path in @($manifestFull, $ownerPath)) {
    if (-not $path.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'NETLOAD_MANIFEST_V2_PATH_OUTSIDE_PROJECT'
    }
}
if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { throw 'NETLOAD_MANIFEST_V2_MANIFEST_MISSING' }
if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) { throw 'NETLOAD_MANIFEST_V2_OWNER_STATE_MISSING' }

$manifest = Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8 | ConvertFrom-Json
$modules = @($manifest.modules)
if ([int]$manifest.schema_version -ne 1 -or $modules.Count -lt 1) { throw 'NETLOAD_MANIFEST_V2_INVALID' }
$seenIds = @{}
$verified = New-Object System.Collections.Generic.List[object]
foreach ($module in $modules) {
    $id = ([string]$module.id).Trim()
    $dll = [IO.Path]::GetFullPath((Join-Path $root ([string]$module.dll_path)))
    $probe = [IO.Path]::GetFullPath((Join-Path $root ([string]$module.probe_path)))
    $kind = ([string]$module.probe_kind).ToUpperInvariant()
    $symbol = ([string]$module.expected_symbol).Trim()
    if ($id -notmatch '^[A-Za-z0-9_.-]+$' -or $seenIds.ContainsKey($id)) { throw "NETLOAD_MANIFEST_V2_MODULE_ID_INVALID:$id" }
    $seenIds[$id] = $true
    if (-not $dll.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $probe.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "NETLOAD_MANIFEST_V2_MODULE_PATH_OUTSIDE_PROJECT:$id" }
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf) -or [IO.Path]::GetExtension($dll) -ine '.dll') { throw "NETLOAD_MANIFEST_V2_DLL_INVALID:$id" }
    if ($symbol -notmatch '^[A-Za-z0-9_:-]+$' -or $kind -notin @('LISP_ATOM','COMMAND')) { throw "NETLOAD_MANIFEST_V2_PROBE_INVALID:$id" }
    $actualSha = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    if ($actualSha -cne ([string]$module.sha256).ToUpperInvariant()) { throw "NETLOAD_MANIFEST_V2_DLL_HASH_MISMATCH:$id" }
    $probeParent = Split-Path -Parent $probe
    if (-not (Test-Path -LiteralPath $probeParent -PathType Container)) { throw "NETLOAD_MANIFEST_V2_PROBE_PARENT_MISSING:$id" }
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    $verified.Add([pscustomobject]@{ id=$id; dll=$dll; sha256=$actualSha; probe=$probe; probe_kind=$kind; expected_symbol=$symbol })
}

$owner = Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8 | ConvertFrom-Json
$owned = Get-Process -Id $ProcessId -ErrorAction Stop
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId -or
    [long]$owner.main_window_handle -ne $WindowHandle -or -not $owned.Responding -or
    [long]$owned.MainWindowHandle -ne $WindowHandle -or
    [IO.Path]::GetFileName([string]$owner.target_dwg) -cne $DocumentName) {
    throw 'NETLOAD_MANIFEST_V2_OWNER_MISMATCH'
}

. (Join-Path $PSScriptRoot 'cad_rot_exact_document_binding_v2.ps1')
. (Join-Path $PSScriptRoot 'cad_com_rejected_call_settlement_v1.ps1')
if (-not ('CadRotNetloadManifestExactV2' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class CadRotNetloadManifestExactV2 {
    [DllImport("ole32.dll")] static extern int GetRunningObjectTable(int r, out IRunningObjectTable t);
    [DllImport("ole32.dll")] static extern int CreateBindCtx(int r, out IBindCtx c);
    public sealed class Entry { public string Name; public dynamic Instance; }
    public static IEnumerable<Entry> Enumerate() {
        IRunningObjectTable table; IBindCtx context; IEnumMoniker iterator;
        Marshal.ThrowExceptionForHR(GetRunningObjectTable(0, out table));
        Marshal.ThrowExceptionForHR(CreateBindCtx(0, out context));
        table.EnumRunning(out iterator);
        var monikers = new IMoniker[1];
        while (iterator.Next(1, monikers, IntPtr.Zero) == 0) {
            string name = ""; object value = null;
            try { monikers[0].GetDisplayName(context, null, out name); } catch {}
            try { table.GetObject(monikers[0], out value); } catch {}
            if (value != null) yield return new Entry { Name = name, Instance = value };
        }
    }
}
'@
}

$application = $null; $document = $null; $sample = 0; $lastBinding = $null
$bindStarted = [DateTime]::UtcNow
$bindDeadline = $bindStarted.AddSeconds($DocumentBindTimeoutSeconds)
do {
    $sample++
    $entries = @([CadRotNetloadManifestExactV2]::Enumerate())
    $lastBinding = Select-CadRotExactDocumentV2 -Entries $entries -WindowHandle $WindowHandle -DocumentName $DocumentName -OwnerMainWindowTitle ([string]$owned.MainWindowTitle)
    if ([string]$lastBinding.status -ceq 'PASS') { $application=$lastBinding.application; $document=$lastBinding.document; break }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $bindDeadline)
if ($null -eq $document -or $null -eq $application) { throw 'NETLOAD_MANIFEST_V2_EXACT_DOCUMENT_BIND_TIMEOUT' }

$script:comCallAttempts = 0; $script:rpcRejectedCount = 0
function Invoke-NetloadManifestV1Com([string]$Label,[scriptblock]$Operation) {
    $settled=Invoke-CadRejectedCallSettlementV1 -Operation $Operation -Label $Label -TimeoutMilliseconds 5000 -PollMilliseconds 100
    $script:comCallAttempts += [int]$settled.attempts; $script:rpcRejectedCount += [int]$settled.rejected_count; $settled.value
}
function Wait-NetloadManifestV1Idle([string]$Code) {
    $deadline=[DateTime]::UtcNow.AddSeconds($CompletionTimeoutSeconds);$idleSamples=0
    do {
        Start-Sleep -Milliseconds 250
        $idle=[bool](Invoke-NetloadManifestV1Com 'GET_QUIESCENT' { $application.GetAcadState().IsQuiescent })
        $names=[string](Invoke-NetloadManifestV1Com 'GET_CMDNAMES' { $document.GetVariable('CMDNAMES') })
        $active=[int](Invoke-NetloadManifestV1Com 'GET_CMDACTIVE' { $document.GetVariable('CMDACTIVE') })
        if($idle -and [string]::IsNullOrWhiteSpace($names) -and $active-eq0){$idleSamples++}else{$idleSamples=0}
    }while($idleSamples-lt2-and[DateTime]::UtcNow-lt$deadline)
    if($idleSamples-lt2){throw $Code}
}

$started=[DateTime]::UtcNow
$secureloadBefore=[int](Invoke-NetloadManifestV1Com 'GET_SECURELOAD_BEFORE' { $document.GetVariable('SECURELOAD') })
Wait-NetloadManifestV1Idle 'NETLOAD_MANIFEST_V2_DOCUMENT_IDLE_TIMEOUT'
$parts=New-Object System.Collections.Generic.List[string]
$parts.Add('(progn')
$parts.Add('(setq cx:manifest-secureload-before (getvar "SECURELOAD"))')
$parts.Add('(setvar "SECURELOAD" 0)')
foreach($module in $verified){$parts.Add('(command "_.NETLOAD" "'+$module.dll.Replace('\','/')+'")')}
foreach($module in $verified){
    $probeForLisp=$module.probe.Replace('\','/').Replace('"','\"');$symbol=$module.expected_symbol
    $test=if($module.probe_kind-ceq'LISP_ATOM'){'(atoms-family 0 (list "'+$symbol+'"))'}else{'(getcname "'+$symbol+'")'}
    $parts.Add('(setq cx:manifest-probe-file (open "'+$probeForLisp+'" "w"))')
    $parts.Add('(if cx:manifest-probe-file (progn (write-line (if '+$test+' "FUNCTION_REGISTERED:'+ $symbol +'" "FUNCTION_MISSING:'+ $symbol +'") cx:manifest-probe-file) (close cx:manifest-probe-file)))')
}
$parts.Add('(setvar "SECURELOAD" cx:manifest-secureload-before)')
$parts.Add('(princ))')
$expression=$parts -join ' '
$sendCount=0
try {
    Invoke-NetloadManifestV1Com 'SEND_MANIFEST_COMMAND' { $document.SendCommand($expression+"`n");$null }|Out-Null
    $sendCount=1
    Wait-NetloadManifestV1Idle 'NETLOAD_MANIFEST_V2_COMPLETION_TIMEOUT'
} finally {
    $current=[int](Invoke-NetloadManifestV1Com 'GET_SECURELOAD_AFTER' { $document.GetVariable('SECURELOAD') })
    if($current-ne$secureloadBefore){
        Invoke-NetloadManifestV1Com 'RESTORE_SECURELOAD' { $document.SendCommand('(setvar "SECURELOAD" '+$secureloadBefore+')'+"`n");$null }|Out-Null
        Wait-NetloadManifestV1Idle 'NETLOAD_MANIFEST_V2_SECURELOAD_RESTORE_TIMEOUT'
    }
}
$probeResults=New-Object System.Collections.Generic.List[object]
foreach($module in $verified){
    if(-not(Test-Path -LiteralPath $module.probe -PathType Leaf)){throw "NETLOAD_MANIFEST_V2_PROBE_MISSING:$($module.id)"}
    $probeText=[IO.File]::ReadAllText($module.probe,[Text.Encoding]::Default).Trim()
    if($probeText-cne"FUNCTION_REGISTERED:$($module.expected_symbol)"){throw "NETLOAD_MANIFEST_V2_FUNCTION_NOT_REGISTERED:$($module.id):$probeText"}
    $probeResults.Add([pscustomobject]@{id=$module.id;status='PASS';symbol=$module.expected_symbol;probe=$module.probe})
}
$secureloadAfter=[int](Invoke-NetloadManifestV1Com 'GET_SECURELOAD_FINAL' { $document.GetVariable('SECURELOAD') })
if($secureloadAfter-ne$secureloadBefore){throw 'NETLOAD_MANIFEST_V2_SECURELOAD_RESTORE_FAILED'}
[pscustomobject]@{
    schema_version=1;status='PASS';document=$DocumentName;document_bind_samples=$sample;module_count=$verified.Count
    modules=$probeResults.ToArray();send_command_count=$sendCount;netload_send_count=1;business_retry_count=0
    com_call_attempt_count=$script:comCallAttempts;rpc_rejection_count=$script:rpcRejectedCount
    secureload_before=$secureloadBefore;secureload_after=$secureloadAfter
    elapsed_ms=[int]([DateTime]::UtcNow-$started).TotalMilliseconds
}
