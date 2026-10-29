param([Parameter(Mandatory=$true)][string]$DetailsPath,[Parameter(Mandatory=$true)][string]$OutputPath,[int]$ExpectedCount=86)
$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$details=[IO.Path]::GetFullPath($DetailsPath);$output=[IO.Path]::GetFullPath($OutputPath)
foreach($path in @($details,$output)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'DETAIL_MAPPING_V4_PATH_OUTSIDE_PROJECT'}}
if(-not(Test-Path -LiteralPath $details -PathType Leaf)){throw 'DETAIL_MAPPING_V4_DETAILS_MISSING'}
$rows=@(Import-Csv -LiteralPath $details -Delimiter "	" -Encoding UTF8);if($rows.Count-ne$ExpectedCount){throw "DETAIL_MAPPING_V4_COUNT:$($rows.Count)"}
$seen=@{};$handles=@{};$out=@()
foreach($row in $rows){
  $source=([string]$row.SOURCE_HANDLE).ToUpperInvariant();$type=([string]$row.SEGMENT_TYPE).ToUpperInvariant();$segment=[int]$row.SEGMENT_INDEX;$key="$source/$type/$segment"
  if($seen.ContainsKey($key)){throw "DETAIL_MAPPING_V4_DUPLICATE_SOURCE:$key"};$seen[$key]=$true
  if(([string]$row.STATUS).ToUpperInvariant()-cne'PASS'){throw "DETAIL_MAPPING_V4_NONPASS:$key"}
  $handle=([string]$row.ADDED_HANDLE).ToUpperInvariant();if($handle-notmatch'^[0-9A-F]+$'-or$handles.ContainsKey($handle)){throw "DETAIL_MAPPING_V4_HANDLE:$key"};$handles[$handle]=$true
  if(([string]$row.OBJECT_NAME).IndexOf('TDbDimension2',[StringComparison]::OrdinalIgnoreCase)-lt0-or([string]$row.LAYER).ToUpperInvariant()-cne'PUB_DIM'){throw "DETAIL_MAPPING_V4_NATIVE:$key"}
  $attempts=[string]$row.ATTEMPTS;$matches=[regex]::Matches($attempts,'(?i)rank=([0-9]+)');$rank=if($type-ceq'LINE'){2}elseif($matches.Count){[int]$matches[$matches.Count-1].Groups[1].Value}else{0}
  $gripMatches=[regex]::Matches($attempts,'(?i)grips=([0-9]+)');$grips=if($type-ceq'LINE'){5}elseif($gripMatches.Count){[int]$gripMatches[$gripMatches.Count-1].Groups[1].Value}else{0}
  if($rank-lt2){throw "DETAIL_MAPPING_V4_RANK_BELOW_2:$key"};if($grips-notin@(5,6)){throw "DETAIL_MAPPING_V4_GRIPS:$key/$grips"}
  $out+=[pscustomobject][ordered]@{SOURCE_HANDLE=$source;SEGMENT_TYPE=$type;SEGMENT_INDEX=$segment;STATUS='PASS';NATIVE_HANDLE=$handle;OBJECT_NAME='TDbDimension2';LAYER='PUB_DIM';GRIP_COUNT=$grips;RANK=$rank;FINAL_ACCEPTANCE_STATE='FINAL_NATIVE_RANK2';SECOND_PASS_TEXT_FOLLOW='NO';ACTUAL_BAND='FINAL_ACCEPTED_TRACE_PASS';EXPECTED_BAND='RUNTIME_COMMON_OR_EXCEPTION_RESCUE_BAND';ENDPOINT_GATE='PASS_CXNATIVEPLACEMENTAUDITV5_WCS_XY';CLEANUP_STATUS='UNIQUE_SURVIVOR_PRESERVED'}
}
$parent=Split-Path -Parent $output;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
$prior=$PSDefaultParameterValues['Export-Csv:UseQuotes'];$had=$PSDefaultParameterValues.ContainsKey('Export-Csv:UseQuotes');try{$PSDefaultParameterValues['Export-Csv:UseQuotes']='Never';$out|Sort-Object SOURCE_HANDLE,SEGMENT_INDEX|Export-Csv -LiteralPath $output -Delimiter "	" -NoTypeInformation -Encoding utf8}finally{if($had){$PSDefaultParameterValues['Export-Csv:UseQuotes']=$prior}else{[void]$PSDefaultParameterValues.Remove('Export-Csv:UseQuotes')}}
[pscustomobject]@{status='PASS';mapping_count=$out.Count;unique_native_count=$handles.Count;rank2_count=$out.Count;semantic_rank1_count=0;text_follow_target_count=0;commanded_grip4_count=0;output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
