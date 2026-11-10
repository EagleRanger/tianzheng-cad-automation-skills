param(
 [Parameter(Mandatory)][string]$OutputDirectory,
 [string]$Compiler='C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe',
 [string]$AutoCadManagedDirectory='C:/Program Files/Autodesk/AutoCAD 2021'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($OutputDirectory)
if($out.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)-or$out-ieq$root){throw 'OFFLINE_BINARIES_MUST_BE_OUTSIDE_SOURCE'}
if(Test-Path $out){throw 'FRESH_BUILD_DIRECTORY_REQUIRED'}
[IO.Directory]::CreateDirectory($out)|Out-Null
$p=Join-Path $root 'reports/cad_multi_window_interface_research/independent_project_jobs_v3'
$helper=Join-Path $root 'reports/cad_multi_window_interface_research/command_uia_inspection_v1/OwnHelperJobV2.cs'
function Compile([string]$Target,[string[]]$Sources,[string[]]$References=@(),[string]$Kind='library'){
 & $Compiler /nologo ('/target:'+$Kind) /optimize+ ('/out:'+(Join-Path $out $Target)) @($References|ForEach-Object{'/reference:'+$_}) @Sources
 if($LASTEXITCODE-ne0){throw ('OFFLINE_COMPILE_FAILED:'+$Target)}
}
Compile 'OwnStartupJobV4.dll' @((Join-Path $p 'OwnStartupJobV4.cs'))
Compile 'CadCommandOwnHelperJobV2.dll' @($helper)
$protocol=@((Join-Path $p 'FixedTaskProtocol.cs'),(Join-Path $p 'ChannelProtocolV11.cs'))
Compile 'ChannelProtocolTestsV11.exe' ($protocol+@((Join-Path $p 'ChannelProtocolTestsV11.cs'))) @('System.Web.Extensions.dll') 'exe'
& (Join-Path $out 'ChannelProtocolTestsV11.exe');if($LASTEXITCODE-ne0){throw 'OFFLINE_PROTOCOL_TEST_FAILED'}
$refs=@('System.Web.Extensions.dll','C:/Windows/Microsoft.NET/Framework64/v4.0.30319/WPF/PresentationCore.dll')+@('acmgd.dll','acdbmgd.dll','accoremgd.dll'|ForEach-Object{Join-Path $AutoCadManagedDirectory $_})
Compile 'CadChannelV11.dll' ($protocol+@((Join-Path $p 'ChannelModuleV11.cs'))) $refs
$parsed=0
foreach($file in Get-ChildItem $root -Recurse -File|Where-Object Extension -In '.ps1','.psm1'){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('OFFLINE_PARSE_FAILED:'+$file.FullName+':'+($errors.Message-join'|'))};$parsed++
}
& (Join-Path $root 'tests/test_tianzheng_startup_fastpath.ps1')
$hashes=@(Get-ChildItem $out -File|ForEach-Object{@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash}})
$receipt=@{status='PASS_OFFLINE_BUILD_PROTOCOL_PARSE_STATIC_FASTPATH_ONLY';parsed_powershell_files=$parsed;outputs=$hashes;CAD_calls=0;COM_calls=0;window_calls=0;registry_writes=0;controller_executed=$false;live_verified=$false}|ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $out 'offline-build-receipt.json'),$receipt,[Text.UTF8Encoding]::new($false))
$receipt
