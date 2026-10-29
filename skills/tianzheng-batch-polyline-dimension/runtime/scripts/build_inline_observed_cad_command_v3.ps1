param(
  [Parameter(Mandatory=$true)][string]$BusinessCommandPath,
  [Parameter(Mandatory=$true)][string]$ProgressPath,
  [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$business=[IO.Path]::GetFullPath($BusinessCommandPath)
$progress=[IO.Path]::GetFullPath($ProgressPath)
$output=[IO.Path]::GetFullPath($OutputPath)
foreach($path in @($business,$progress,$output)){
  if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'INLINE_OBSERVED_V3_PATH_OUTSIDE_PROJECT'}
}
if(-not(Test-Path -LiteralPath $business -PathType Leaf)){throw 'INLINE_OBSERVED_V3_BUSINESS_MISSING'}
function ConvertTo-InlineObservedV3LispLiteral([string]$Value){'"'+$Value.Replace('\','/').Replace('"','\"')+'"'}
function New-InlineObservedV3SignalExpression([string]$Token){
  $pathLiteral=ConvertTo-InlineObservedV3LispLiteral $progress
  '(progn (setq cx:iof (open {0} "a")) (if cx:iof (progn (write-line (strcat "CX_CAD_SIGNAL_V1|{1}|" (rtos (getvar "DATE") 2 8)) cx:iof) (close cx:iof))))' -f $pathLiteral,$Token
}
$body=[IO.File]::ReadAllText($business,[Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n").Trim("`n")
if([string]::IsNullOrWhiteSpace($body)){throw 'INLINE_OBSERVED_V3_BUSINESS_EMPTY'}
$command=@((New-InlineObservedV3SignalExpression 'CAD_COMMAND_ACK'),$body,(New-InlineObservedV3SignalExpression 'CAD_COMMAND_COMPLETE'))-join"`n"
$command+="`n"
if($command.Contains("`r")){throw 'INLINE_OBSERVED_V3_CR_FORBIDDEN'}
if($command.IndexOf('cad_command_observer_signal',[StringComparison]::OrdinalIgnoreCase)-ge0){throw 'INLINE_OBSERVED_V3_EXTERNAL_OBSERVER_FORBIDDEN'}
[IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null
[IO.File]::WriteAllText($output,$command,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{status='PASS';protocol='CX_CAD_SIGNAL_V1';separator='PIPE';ack='CAD_COMMAND_ACK';complete='CAD_COMMAND_COMPLETE';inline_signal_count=2;external_observer_load_count=0;send_count=1;retry_count=0;line_ending='LF_ONLY';sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
