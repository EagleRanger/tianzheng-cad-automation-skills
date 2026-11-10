param(
    [Parameter(Mandatory = $true)][ValidateRange(1,2147483647)][int]$ClosedProcessId,
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
# Called only after the owned host exits. Do not command another live CAD or
# guess the profile from CurVer (another installed release can change it).
if (Get-Process -Id $ClosedProcessId -ErrorAction SilentlyContinue) {
    throw 'MANUAL_DIALOG_RESTORE_OWNER_STILL_RUNNING'
}
$exactExe = [IO.Path]::GetFullPath($ExecutablePath)
if ([IO.Path]::GetFileName($exactExe) -ine 'acad.exe' -or
    -not (Test-Path -LiteralPath $exactExe -PathType Leaf)) {
    throw 'MANUAL_DIALOG_RESTORE_EXECUTABLE_INVALID'
}
$profiles = @()
$installedRoot = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\AutoCAD'
foreach ($release in Get-ChildItem -LiteralPath $installedRoot) {
    if ($release.PSChildName -notmatch '^R\d+\.\d+$') { continue }
    foreach ($product in Get-ChildItem -LiteralPath $release.PSPath) {
        if ($product.PSChildName -notmatch '^ACAD-[\w:]+$') { continue }
        $location = [string]$product.GetValue('AcadLocation')
        if ([string]::IsNullOrWhiteSpace($location)) { continue }
        $installedExe = [IO.Path]::GetFullPath((Join-Path $location 'acad.exe'))
        if ($installedExe -ine $exactExe) { continue }
        $candidate = 'Registry::HKEY_CURRENT_USER\Software\Autodesk\AutoCAD\' +
            $release.PSChildName + '\' + $product.PSChildName + '\FixedProfile\General Configuration'
        if (Test-Path -LiteralPath $candidate) { $profiles += $candidate }
    }
}
if ($profiles.Count -ne 1) { throw "MANUAL_DIALOG_RESTORE_PROFILE_COUNT=$($profiles.Count)" }
$dialogKey = $profiles[0]
$key = Get-Item -LiteralPath $dialogKey
$before = [ordered]@{}
# Validate both existing values before writing either. Never create a profile.
foreach ($name in @('FileDialog','CommandDialogs')) {
    if ($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw "MANUAL_DIALOG_RESTORE_VALUE_KIND=$name"
    }
    $before[$name] = [int]$key.GetValue($name)
}
$after = [ordered]@{}
foreach ($name in @('FileDialog','CommandDialogs')) {
    if (-not $CheckOnly -and $before[$name] -ne 1) {
        Set-ItemProperty -LiteralPath $dialogKey -Name $name -Type DWord -Value 1
    }
    $after[$name] = [int](Get-ItemPropertyValue -LiteralPath $dialogKey -Name $name)
    if ($after[$name] -ne 1) { throw "MANUAL_DIALOG_RESTORE_READBACK_FAILED=$name" }
}
[pscustomobject]@{
    status = 'PASS'
    closed_process_id = $ClosedProcessId
    executable = $exactExe
    registry_path = $dialogKey
    check_only = [bool]$CheckOnly
    before = $before
    after = $after
    changed = (-not $CheckOnly -and ($before.FileDialog -ne 1 -or $before.CommandDialogs -ne 1))
    cad_command_count = 0
    checked_at = (Get-Date).ToString('o')
}
