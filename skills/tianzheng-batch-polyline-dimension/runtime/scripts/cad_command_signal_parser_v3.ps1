Set-StrictMode -Version Latest

function Read-CadCommandSignalResultV3 {
  param([Parameter(Mandatory=$true)][string]$Path)
  $exists=[bool](Test-Path -LiteralPath $Path -PathType Leaf)
  [string[]]$lines=@()
  if($exists){$lines=[string[]]@(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)}
  [pscustomobject]@{path=$Path;exists=$exists;lines=$lines;count=[int]$lines.Count}
}

function Get-CadCommandSignalV3 {
  param(
    [AllowEmptyCollection()][string[]]$Lines,
    [Parameter(Mandatory=$true)][ValidateSet('CAD_COMMAND_ACK','CAD_COMMAND_COMPLETE')][string]$Token
  )
  $materialized=[string[]]@($Lines)
  $escaped=[regex]::Escape($Token)
  $current='^CX_CAD_SIGNAL_V1\|'+$escaped+'\|(?<stamp>[0-9]+(?:\.[0-9]+)?)\s*$'
  $legacy='^'+$escaped+'(?<separator>[\t ])(?<stamp>[0-9]+(?:\.[0-9]+)?)\s*$'
  foreach($line in $materialized){
    if($null-eq$line){continue}
    $match=[regex]::Match([string]$line,$current,[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if($match.Success){
      [pscustomobject]@{token=$Token;timestamp=$match.Groups['stamp'].Value;protocol='CX_CAD_SIGNAL_V1';separator='PIPE';line=[string]$line}
      continue
    }
    $match=[regex]::Match([string]$line,$legacy,[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if($match.Success){
      $separator=if($match.Groups['separator'].Value-eq"`t"){'LEGACY_TAB'}else{'LEGACY_SPACE'}
      [pscustomobject]@{token=$Token;timestamp=$match.Groups['stamp'].Value;protocol='LEGACY_INLINE_V0';separator=$separator;line=[string]$line}
    }
  }
}

function Test-CadCommandSignalSetV3 {
  param(
    [AllowEmptyCollection()][string[]]$Lines,
    [Parameter(Mandatory=$true)][ValidateSet('CAD_COMMAND_ACK','CAD_COMMAND_COMPLETE')][string]$Token
  )
  $matches=[object[]]@(Get-CadCommandSignalV3 -Lines ([string[]]@($Lines)) -Token $Token)
  return $matches.Count-gt0
}
