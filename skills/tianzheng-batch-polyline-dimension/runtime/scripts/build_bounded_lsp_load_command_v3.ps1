param(
  [Parameter(Mandatory=$true)][string]$LispPathForCad,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedLispSha256,
  [Parameter(Mandatory=$true)][string]$LoadReceiptPath,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [ValidateRange(512,2048)][int]$MaximumCommandCharacters=1024,
  [string]$ErrorPrefix='CX_BOUNDED_LSP_LOAD_ERROR')
$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$lisp=[IO.Path]::GetFullPath($LispPathForCad);$receipt=[IO.Path]::GetFullPath($LoadReceiptPath);$output=[IO.Path]::GetFullPath($OutputPath)
foreach($path in @($lisp,$receipt,$output)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'BOUNDED_LSP_V3_PATH_OUTSIDE_PROJECT'};if($path.IndexOf('"',[StringComparison]::Ordinal)-ge0){throw 'BOUNDED_LSP_V3_PATH_CONTAINS_QUOTE'}}
if(-not(Test-Path -LiteralPath $lisp -PathType Leaf)){throw 'BOUNDED_LSP_V3_LISP_MISSING'};$actual=(Get-FileHash -LiteralPath $lisp -Algorithm SHA256).Hash;if($actual-cne$ExpectedLispSha256.ToUpperInvariant()){throw 'BOUNDED_LSP_V3_LISP_HASH_MISMATCH'}
if($ErrorPrefix-notmatch'^[A-Z0-9_]+$'){throw 'BOUNDED_LSP_V3_ERROR_PREFIX_INVALID'};$cadPath=$lisp.Replace('\','/');$receiptCad=$receipt.Replace('\','/')
$command=@('(progn',' (setq cx:bls (getvar "SECURELOAD"))',' (setvar "SECURELOAD" 0)'," (setq cx:blr (vl-catch-all-apply 'load (list `"$cadPath`")))",' (setvar "SECURELOAD" cx:bls)'," (setq cx:blf (open `"$receiptCad`" `"w`"))",' (if cx:blf (progn (write-line (if (vl-catch-all-error-p cx:blr) (strcat "LOAD_ERROR\t" (vl-catch-all-error-message cx:blr)) "LOAD_OK") cx:blf) (close cx:blf)))'," (if (vl-catch-all-error-p cx:blr) (prompt (strcat `"\n${ErrorPrefix}: `" (vl-catch-all-error-message cx:blr))))",' (princ))')-join'';$command+=[Environment]::NewLine
if($command.Length-gt$MaximumCommandCharacters){throw "BOUNDED_LSP_V3_COMMAND_TOO_LONG:actual=$($command.Length);maximum=$MaximumCommandCharacters"};[IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null;[IO.Directory]::CreateDirectory((Split-Path -Parent $receipt))|Out-Null;[IO.File]::WriteAllText($output,$command,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{status='PASS';lisp_sha256=$actual;load_receipt_path=$receipt;output_path=$output;output_sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;command_characters=$command.Length;guarded_load_count=([regex]::Matches($command,"vl-catch-all-apply 'load")).Count;load_receipt_success_token_count=([regex]::Matches($command,'LOAD_OK')).Count;load_receipt_error_token_count=([regex]::Matches($command,'LOAD_ERROR\\t')).Count;external_send_count=1}
