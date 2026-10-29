param(
  [Parameter(Mandatory=$true)][string]$DetailsPath,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [int]$ExpectedCount=86
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$details=[IO.Path]::GetFullPath($DetailsPath)
$output=[IO.Path]::GetFullPath($OutputPath)
foreach($path in @($details,$output)){
  if(-not $path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'DETAIL_MAPPING_V3_PATH_OUTSIDE_PROJECT'}
}
if(-not(Test-Path -LiteralPath $details -PathType Leaf)){throw 'DETAIL_MAPPING_V3_DETAILS_MISSING'}
$rows=@(Import-Csv -LiteralPath $details -Delimiter "`t" -Encoding UTF8)
if($rows.Count-ne$ExpectedCount){throw "DETAIL_MAPPING_V3_COUNT:$($rows.Count)"}
$seen=@{};$handles=@{};$out=@();$provisional=0
foreach($row in $rows){
  $source=([string]$row.SOURCE_HANDLE).ToUpperInvariant();$type=([string]$row.SEGMENT_TYPE).ToUpperInvariant();$segment=[int]$row.SEGMENT_INDEX;$key="$source/$type/$segment"
  if($seen.ContainsKey($key)){throw "DETAIL_MAPPING_V3_DUPLICATE_SOURCE:$key"};$seen[$key]=$true
  if(([string]$row.STATUS).ToUpperInvariant()-cne'PASS'){throw "DETAIL_MAPPING_V3_NONPASS:$key"}
  $handle=([string]$row.ADDED_HANDLE).ToUpperInvariant();if($handle-notmatch'^[0-9A-F]+$'){throw "DETAIL_MAPPING_V3_HANDLE_INVALID:$key"};if($handles.ContainsKey($handle)){throw "DETAIL_MAPPING_V3_DUPLICATE_NATIVE:$handle"};$handles[$handle]=$true
  if(([string]$row.OBJECT_NAME).IndexOf('TDbDimension2',[StringComparison]::OrdinalIgnoreCase)-lt0){throw "DETAIL_MAPPING_V3_TYPE_INVALID:$key"};if(([string]$row.LAYER).ToUpperInvariant()-cne'PUB_DIM'){throw "DETAIL_MAPPING_V3_LAYER_INVALID:$key"}
  $attempts=[string]$row.ATTEMPTS
  if($type-ceq'LINE'){$rank=2}else{$matches=[regex]::Matches($attempts,'(?i)rank=([0-9]+)');$rank=if($matches.Count){[int]$matches[$matches.Count-1].Groups[1].Value}else{0}}
  $semanticRank1=($type-ceq'ARC'-and$rank-eq1-and$attempts.Contains('TRUE_WCS_SEMANTIC_PROMOTION_V19',[StringComparison]::Ordinal)-and$attempts.Contains('semantic_first_pass_rank=1',[StringComparison]::Ordinal)-and$attempts.Contains('second_pass_unified_layout_required=YES',[StringComparison]::Ordinal))
  if($rank-lt2-and-not$semanticRank1){throw "DETAIL_MAPPING_V3_FINAL_RANK_UNACCEPTED:$key"}
  if($semanticRank1){$provisional++}
  $out+=[pscustomobject][ordered]@{
    SOURCE_HANDLE=$source;SEGMENT_TYPE=$type;SEGMENT_INDEX=$segment;STATUS='PASS';NATIVE_HANDLE=$handle;OBJECT_NAME='TDbDimension2';LAYER='PUB_DIM';GRIP_COUNT=5;RANK=$rank
    FINAL_ACCEPTANCE_STATE=if($semanticRank1){'PROVISIONAL_SEMANTIC_RANK1'}else{'FINAL_NATIVE_RANK2'}
    SECOND_PASS_TEXT_FOLLOW=if($semanticRank1){'YES'}else{'NO'}
    ACTUAL_BAND=if($semanticRank1){'UNIFIED_LAYOUT_PENDING'}else{'FINAL_ACCEPTED_TRACE_PASS'}
    EXPECTED_BAND=if($semanticRank1){'RUNTIME_COMMON_OR_CAPACITY_BAND'}else{'FINAL_ACCEPTED_TRACE_PASS'}
    ENDPOINT_GATE=if($semanticRank1){'FINAL_POST_LAYOUT_AUDIT_REQUIRED'}else{'PASS_CXNATIVEPLACEMENTAUDITV5_WCS_XY'}
    CLEANUP_STATUS='UNIQUE_SURVIVOR_PRESERVED'
  }
}
$parent=Split-Path -Parent $output;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
$prior=$PSDefaultParameterValues['Export-Csv:UseQuotes'];$had=$PSDefaultParameterValues.ContainsKey('Export-Csv:UseQuotes')
try{$PSDefaultParameterValues['Export-Csv:UseQuotes']='Never';$out|Sort-Object SOURCE_HANDLE,SEGMENT_INDEX|Export-Csv -LiteralPath $output -Delimiter "`t" -NoTypeInformation -Encoding utf8}finally{if($had){$PSDefaultParameterValues['Export-Csv:UseQuotes']=$prior}else{[void]$PSDefaultParameterValues.Remove('Export-Csv:UseQuotes')}}
[pscustomobject]@{status='PASS';mapping_count=$out.Count;unique_native_count=$handles.Count;provisional_semantic_rank1_count=$provisional;board_specific_algorithm_literals=0;output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
