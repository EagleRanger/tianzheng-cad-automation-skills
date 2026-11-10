param([Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd('\','/')
$run=if([IO.Path]::IsPathRooted($RunDirectory)){[IO.Path]::GetFullPath($RunDirectory)}else{[IO.Path]::GetFullPath((Join-Path $root $RunDirectory))}
if(-not$run.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'WRITE_OVERLAP_RUN_OUTSIDE_PROJECT'}
function Get-WriteIntervals([string]$Owner){
 $path=Join-Path $run ('hosts/'+$Owner+'/AB_'+$Owner+'_SEQUENCE_1.result.json')
 $r=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
 if($r.run_id-cne[IO.Path]::GetFileName($run)-or$r.owner-cne$Owner-or$r.sequence-ne1-or@($r.write_batches).Count-ne64){throw 'WRITE_OVERLAP_EXACT_RESULT'}
 $rows=@(foreach($b in $r.write_batches){
  $start=[DateTimeOffset]::Parse($b.start_utc,[Globalization.CultureInfo]::InvariantCulture).UtcTicks
  $end=[DateTimeOffset]::Parse($b.end_utc,[Globalization.CultureInfo]::InvariantCulture).UtcTicks
  if($end-lt$start){throw 'WRITE_OVERLAP_REVERSED_INTERVAL'}
  [pscustomobject]@{start=[long]$start;end=[long]$end;batch=[int]$b.batch}
 })
 [pscustomobject]@{owner=$Owner;result_status=$r.status;result_sha256=(Get-FileHash -LiteralPath $path).Hash;rows=$rows}
}
$a=Get-WriteIntervals 'A';$b=Get-WriteIntervals 'B'
$positivePairs=0;$ticks=[long]0
foreach($x in $a.rows){foreach($y in $b.rows){
 $begin=[Math]::Max([long]$x.start,[long]$y.start)
 $end=[Math]::Min([long]$x.end,[long]$y.end)
 if($end-gt$begin){$positivePairs++;$ticks+=$end-$begin}
}}
function Get-Union([object[]]$Rows){
 $merged=[Collections.Generic.List[object]]::new()
 foreach($row in @($Rows|Sort-Object start,end)){
  if($merged.Count-eq0-or$row.start-gt$merged[$merged.Count-1].end){$merged.Add([pscustomobject]@{start=[long]$row.start;end=[long]$row.end})}
  elseif($row.end-gt$merged[$merged.Count-1].end){$merged[$merged.Count-1].end=[long]$row.end}
 }
 $merged.ToArray()
}
$ua=@(Get-Union $a.rows);$ub=@(Get-Union $b.rows);$unionTicks=[long]0
foreach($x in $ua){foreach($y in $ub){$begin=[Math]::Max([long]$x.start,[long]$y.start);$end=[Math]::Min([long]$x.end,[long]$y.end);if($end-gt$begin){$unionTicks+=$end-$begin}}}
if($ticks-ne$unionTicks){throw 'WRITE_OVERLAP_RAW_VS_UNION_MISMATCH'}
[pscustomobject]@{run_id=[IO.Path]::GetFileName($run);status=if($ticks-gt0){'POSITIVE_RAW_WRITE_OVERLAP'}else{'NO_RAW_WRITE_OVERLAP'};overlap_ticks=$ticks;overlap_ms=[Math]::Round($ticks/10000.0,4);positive_raw_batch_pairs=$positivePairs;owner_A_result_status=$a.result_status;owner_B_result_status=$b.result_status;owner_A_result_sha256=$a.result_sha256;owner_B_result_sha256=$b.result_sha256;method='RAW_UTC_TICK_INTERVAL_INTERSECTION__CROSS_CHECKED_AGAINST_PER_OWNER_UNION';CAD_calls=0}
