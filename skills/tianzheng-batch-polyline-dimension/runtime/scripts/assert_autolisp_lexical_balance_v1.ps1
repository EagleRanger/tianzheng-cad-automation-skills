param([Parameter(Mandatory=$true)][string]$LispPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$path=[IO.Path]::GetFullPath($LispPath)
if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'AUTOLISP_LEXICAL_PATH_OUTSIDE_PROJECT'}
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'AUTOLISP_LEXICAL_FILE_MISSING'}
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8);$depth=0;$inString=$false;$inComment=$false;$escaped=$false;$line=1;$formCount=0
foreach($ch in $text.ToCharArray()){
  if($ch-eq"`n"){$line++;$inComment=$false;continue}
  if($inComment){continue}
  if($inString){if($escaped){$escaped=$false;continue};if($ch-eq'\'){$escaped=$true;continue};if($ch-eq'"'){$inString=$false};continue}
  if($ch-eq';'){$inComment=$true;continue};if($ch-eq'"'){$inString=$true;continue}
  if($ch-eq'('){if($depth-eq0){$formCount++};$depth++}elseif($ch-eq')'){$depth--;if($depth-lt0){throw "AUTOLISP_LEXICAL_NEGATIVE_DEPTH_AT_LINE:$line"}}
}
if($inString){throw 'AUTOLISP_LEXICAL_UNCLOSED_STRING'}
if($depth-ne0){throw "AUTOLISP_LEXICAL_FINAL_DEPTH_INVALID:$depth"}
[pscustomobject]@{status='PASS';path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;final_depth=0;top_level_form_count=$formCount}
