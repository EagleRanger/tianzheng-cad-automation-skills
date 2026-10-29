param(
  [Parameter(Mandatory=$true)][string]$RunDirectory,[Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][long]$WindowHandle,
  [Parameter(Mandatory=$true)][string]$OwnerStatePath,[Parameter(Mandatory=$true)][string]$DocumentName,[Parameter(Mandatory=$true)][string]$TaskSpecPath,
  [Parameter(Mandatory=$true)][string]$GenerationCommandPath,[Parameter(Mandatory=$true)][string]$LoadReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReuseFinalDetailsPath,[Parameter(Mandatory=$true)][string]$ReuseMappingPath,[Parameter(Mandatory=$true)][string]$ReuseGeometryPath,
  [Parameter(Mandatory=$true)][string]$SemanticCommandPath,[Parameter(Mandatory=$true)][string]$SemanticLoadReceiptPath,[Parameter(Mandatory=$true)][string]$SemanticBundlePath,
  [Parameter(Mandatory=$true)][string]$GenerationDllSha256,[Parameter(Mandatory=$true)][string]$ScalarDllSha256,[Parameter(Mandatory=$true)][string]$PreviewDllSha256,
  [Parameter(Mandatory=$true)][string]$CorePreloadManifestPath,[Parameter(Mandatory=$true)][string]$PreviewPreloadManifestPath,
  [int]$ExpectedCapacityReplacementCount=-1,[int]$ExpectedProvisionalSemanticRank1Count=1,[int]$PriorFirstPassGenerationMs=0,[int]$TimeoutSeconds=120,
  [string]$PythonPath=$(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'));$run=[IO.Path]::GetFullPath($RunDirectory)
$semanticBundle=[IO.Path]::GetFullPath($SemanticBundlePath)
$observer=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/cad_command_observer_signal_v1.lsp'))
$controller=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_composed_layout_continuation_v33.ps1'))
$watcher=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/watch_tianzheng_dialogs.ps1'))
foreach($path in @($run,$semanticBundle,$observer,$controller,$watcher)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'COMPOSED_TRUSTED_V34_PATH'}}
foreach($path in @($semanticBundle,$observer,$controller,$watcher)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'COMPOSED_TRUSTED_V34_DEPENDENCY'}}
$trustedPaths=@($observer,$semanticBundle);$trustedHashes=@($trustedPaths|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash})
$dialogLog=Join-Path $run 'trusted_script_dialogs.jsonl';if(Test-Path -LiteralPath $dialogLog){throw 'COMPOSED_TRUSTED_V34_DIALOG_LOG_EXISTS'}
$dialogJob=Start-Job -ScriptBlock {param($Watcher,$OwnedProcessId,$Log,$Paths,$Hashes,$Title,$TrustedRoot,$WatchTimeout);Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force;&$Watcher -ProcessId $OwnedProcessId -LogPath $Log -ExpectedTrustedScriptPaths $Paths -ExpectedTrustedScriptSha256s $Hashes -TrustedScriptRoot $TrustedRoot -MaxTrustedScriptAutoDismissCount $Paths.Count -RequiredMainTitle $Title -TimeoutSeconds $WatchTimeout -QuietSeconds 0} -ArgumentList $watcher,$ProcessId,$dialogLog,$trustedPaths,$trustedHashes,$DocumentName,$root,([Math]::Max(180,$TimeoutSeconds*3))
try{
  $result=&$controller -RunDirectory $run -ProcessId $ProcessId -WindowHandle $WindowHandle -OwnerStatePath $OwnerStatePath -DocumentName $DocumentName -TaskSpecPath $TaskSpecPath -GenerationCommandPath $GenerationCommandPath -LoadReceiptPath $LoadReceiptPath -ReuseFinalDetailsPath $ReuseFinalDetailsPath -ReuseMappingPath $ReuseMappingPath -ReuseGeometryPath $ReuseGeometryPath -SemanticCommandPath $SemanticCommandPath -SemanticLoadReceiptPath $SemanticLoadReceiptPath -GenerationDllSha256 $GenerationDllSha256 -ScalarDllSha256 $ScalarDllSha256 -PreviewDllSha256 $PreviewDllSha256 -CorePreloadManifestPath $CorePreloadManifestPath -PreviewPreloadManifestPath $PreviewPreloadManifestPath -ExpectedCapacityReplacementCount $ExpectedCapacityReplacementCount -ExpectedProvisionalSemanticRank1Count $ExpectedProvisionalSemanticRank1Count -PriorFirstPassGenerationMs $PriorFirstPassGenerationMs -TimeoutSeconds $TimeoutSeconds -PythonPath $PythonPath
  if($dialogJob.State-eq'Failed'){$failure=(Receive-Job -Job $dialogJob -ErrorAction SilentlyContinue 2>&1|Out-String);throw ('COMPOSED_TRUSTED_V34_WATCHER='+$failure)}
  $events=if(Test-Path -LiteralPath $dialogLog){@(Get-Content -LiteralPath $dialogLog -Encoding UTF8)}else{@()}
  [pscustomobject]@{status=[string]$result.status;generation_post_count=0;transport='ACTIVEX_SENDCOMMAND_EXACT_DOCUMENT_NONFOCUS_ISOLATED';trusted_script_count=$trustedPaths.Count;trusted_script_dialog_event_count=$events.Count;trusted_script_dialog_log=$dialogLog;controller_result=$result}
}finally{if($null-ne$dialogJob){if($dialogJob.State-eq'Running'){Stop-Job -Job $dialogJob -ErrorAction SilentlyContinue};Receive-Job -Job $dialogJob -ErrorAction SilentlyContinue|Out-Null;Remove-Job -Job $dialogJob -Force -ErrorAction SilentlyContinue}}
