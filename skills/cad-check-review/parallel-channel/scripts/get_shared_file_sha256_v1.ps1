param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$full=[IO.Path]::GetFullPath($Path)
if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'SHARED_HASH_FILE_MISSING'}
$stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
try{$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}finally{$sha.Dispose()}}finally{$stream.Dispose()}
