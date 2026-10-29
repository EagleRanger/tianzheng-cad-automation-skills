param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$baseBuilder=Join-Path $PSScriptRoot 'build_targeted_confirm_arc_dimension_positive_v27.ps1'
$adapterPath=Join-Path $PSScriptRoot 'tdimarc_native_generation_post_create_grip0_outer_v1.lsp'
$result=& $baseBuilder -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if([string]$result.status-cne'PASS'){throw 'V40_V27_BUILD_FAILED'}
$path=[IO.Path]::GetFullPath($OutputPath)
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$adapter=[IO.File]::ReadAllText($adapterPath,[Text.Encoding]::UTF8).Trim()
$autorun='(c:CXTDIMARCFULLBATCH)'
$last=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($last-lt0){throw 'V40_AUTORUN_NOT_FOUND'}
$text=$text.Substring(0,$last)+$adapter+[Environment]::NewLine+
  [Environment]::NewLine+$text.Substring($last)
[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
$semantic=& (Join-Path $PSScriptRoot 'assert_targeted_confirm_arc_dimension_positive_v40_semantics.ps1') `
  -BundlePath $path
if([string]$semantic.status-cne'PASS'){throw 'V40_SEMANTIC_AUDIT_FAILED'}
[pscustomobject]@{
  status='PASS';output=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  prompt_sequence=$semantic.prompt_sequence
  post_create_action=$semantic.post_create_action
  move_function=$semantic.move_function
  endpoint_audit=$semantic.endpoint_audit
  acceptance_dimension_band_h=$semantic.acceptance_dimension_band_h
  transaction_contract=$semantic.transaction_contract
  corrected_variable='POST_CREATE_NATIVE_GRIP0_RADIAL_POSITION_ONLY'
  frozen_generation='RUN162_FIVE_STAGE_ENDPOINT_ASSOCIATED_NATIVE_CREATION'
  minimum_accepted_rank=1;preferred_rank=2;candidate_count_max=1
  semantic_audit='PASS_V40'
}
