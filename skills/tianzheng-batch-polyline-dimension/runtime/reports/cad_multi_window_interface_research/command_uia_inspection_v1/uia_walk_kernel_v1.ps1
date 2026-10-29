function Invoke-CadCommandUiaWalkV1($Root,[scriptblock]$GetRoot,[scriptblock]$Describe,[scriptblock]$ReadBody,[scriptblock]$FirstChild,[scriptblock]$NextSibling,[scriptblock]$FreshGuard,[scriptblock]$Emit){
 $clock=[Diagnostics.Stopwatch]::StartNew();$rows=[Collections.Generic.List[object]]::new();$seen=@{};$queue=[Collections.Generic.Queue[object]]::new();$scheduled=0;$complete=$false;$problem=$null;$phase='BEFORE_ROOT';$total=0;$fromHandleCount=0
 function CheckUiaBudgetV1 {if($clock.Elapsed.TotalSeconds-ge2){throw 'UIA_SOFT_BUDGET'};& $FreshGuard}
 try{
  CheckUiaBudgetV1;$phase='FROM_HANDLE';$fromHandleCount++;$element=& $GetRoot
  if($null-eq$element){throw 'UIA_ROOT_NULL'}
  $phase='ROOT_IDENTITY';$first=& $Describe $element '' $true
  Assert-CadCommandUiaMetadataV1 $first $Root '' $true
  $queue.Enqueue([pscustomobject]@{element=$element;meta=$first;parent='';depth=0});$scheduled=1;$seen[$first.runtime_id]=$true
  while($queue.Count){
   CheckUiaBudgetV1;$item=$queue.Dequeue();$isRoot=$item.depth-eq0;$phase='BEFORE_NODE_READ'
   $before=& $Describe $item.element $item.parent $isRoot
   Assert-CadCommandUiaStableV1 $item.meta $before $Root $item.parent $isRoot
   & $Emit ([pscustomobject]@{kind='UIA_READ_ENTER';depth=$item.depth;node=$before})
   $body=& $ReadBody $item.element $before
   $phase='AFTER_NODE_READ';$after=& $Describe $item.element $item.parent $isRoot
   $row=[pscustomobject]@{kind='UIA_ROW';depth=$item.depth;before=$before;after=$after;value_text=$body.value_text;document_text=$body.document_text;read_complete=$false;identity_stable=$false}
   $rows.Add($row)
   try{
    Assert-CadCommandUiaStableV1 $before $after $Root $item.parent $isRoot;CheckUiaBudgetV1
    foreach($value in @($before.name,$body.value_text,$body.document_text)){
     if(([string]$value).Length-ge4096){throw 'UIA_TEXT_LIMIT_OR_TRUNCATION'}
     $total+=([string]$value).Length;if($total-gt16384){throw 'UIA_TOTAL_TEXT_LIMIT'}
    }
    $row.identity_stable=$true;$row.read_complete=$true
   }finally{& $Emit $row}
   $phase='CHILD_ENUMERATION';CheckUiaBudgetV1
   if($item.depth-ge8){throw 'UIA_DEPTH_LIMIT_NO_FURTHER_QUERY'}
   $child=& $FirstChild $item.element
   while($null-ne$child){
    CheckUiaBudgetV1;if($scheduled-ge32){throw 'UIA_NODE_LIMIT'}
    $meta=& $Describe $child $before.runtime_id $false
    Assert-CadCommandUiaMetadataV1 $meta $Root $before.runtime_id $false
    if($seen.ContainsKey($meta.runtime_id)){throw 'UIA_RUNTIME_ID_CYCLE'}
    $seen[$meta.runtime_id]=$true
    $queue.Enqueue([pscustomobject]@{element=$child;meta=$meta;parent=$before.runtime_id;depth=($item.depth+1)});$scheduled++
    if($scheduled-ge32){throw 'UIA_NODE_LIMIT_NO_FURTHER_QUERY'}
    $child=& $NextSibling $child
   }
  }
  $phase='FINAL_ROOT';CheckUiaBudgetV1;$last=& $Describe $element '' $true
  Assert-CadCommandUiaStableV1 $first $last $Root '' $true;CheckUiaBudgetV1
  $complete=$true
 }catch{$problem=$_.Exception.Message}
 & $Emit ([pscustomobject]@{kind='UIA_STOP';phase=$phase;error=$problem;subtree_complete=$complete;scheduled=$scheduled;row_count=$rows.Count;from_handle_count=$fromHandleCount;elapsed_ms=$clock.ElapsedMilliseconds})
 [pscustomobject]@{rows=$rows.ToArray();subtree_complete=$complete;error=$problem;phase=$phase;from_handle_count=$fromHandleCount;elapsed_ms=$clock.ElapsedMilliseconds;native_idle_verified=$false;send_authorized=$false}
}
