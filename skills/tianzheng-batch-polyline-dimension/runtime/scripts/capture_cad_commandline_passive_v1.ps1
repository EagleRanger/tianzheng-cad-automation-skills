param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][long]$WindowHandle,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [string]$Label='stall'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$directory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $directory.StartsWith((Join-Path $root 'runs')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'COMMANDLINE_CAPTURE_OUTSIDE_RUNS'}
[IO.Directory]::CreateDirectory($directory)|Out-Null
$safe=[regex]::Replace($Label,'[^A-Za-z0-9._-]+','_')
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$full=Join-Path $directory "${stamp}_${safe}_full.png"
$meta=Join-Path $directory "${stamp}_${safe}_full.json"
$crop=Join-Path $directory "${stamp}_${safe}_commandline.png"
$capture=Join-Path $PSScriptRoot 'cad_capture_compat.ps1'
$rawText=(& $capture -OutputPath $full -MetadataPath $meta -WindowHandle $WindowHandle -ProcessId $ProcessId -Backend PrintWindow -AllowDiversePrintWindowWithoutNearBlack|Out-String).Trim()
$raw=$rawText|ConvertFrom-Json
if([string]$raw.status-cne'PASS'){throw 'COMMANDLINE_PASSIVE_CAPTURE_FAILED'}
Add-Type -AssemblyName System.Drawing
$image=[Drawing.Bitmap]::new($full)
try{
  $height=[Math]::Max(120,[int][Math]::Round($image.Height*0.24))
  $top=[Math]::Max(0,$image.Height-$height)
  $rectangle=[Drawing.Rectangle]::new(0,$top,$image.Width,$height)
  $commandline=$image.Clone($rectangle,$image.PixelFormat)
  try{$commandline.Save($crop,[Drawing.Imaging.ImageFormat]::Png)}finally{$commandline.Dispose()}
}finally{$image.Dispose()}
[pscustomobject]@{status='PASS';passive=$true;foreground_or_input_used=$false;full_path=$full;full_sha256=(Get-FileHash $full -Algorithm SHA256).Hash;commandline_path=$crop;commandline_sha256=(Get-FileHash $crop -Algorithm SHA256).Hash}
