function ConvertTo-DimOwnedPopupSnapshotV3 {
 param([Parameter(Mandatory)]$Owner,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Windows,[Parameter(Mandatory)][scriptblock]$ReadChildren)
 $main=@($Windows|Where-Object {[long]$_.Handle-eq[long]$Owner.window_handle-and[int]$_.ProcessId-eq[int]$Owner.process_id})
 if($main.Count-ne1-or$main[0].Class-cne'AfxMDIFrame140u'){throw 'DIM_POPUP_MAIN_IDENTITY'}
 $result=[Collections.Generic.List[object]]::new()
 foreach($window in $Windows){
  if(-not$window.Visible-or[int]$window.ProcessId-ne[int]$Owner.process_id-or[long]$window.Handle-eq[long]$Owner.window_handle){continue}
  # WinForms exception dialogs are not #32770. Never restrict observation to
  # the trusted-load signature and never auto-dismiss unknown windows.
  if($window.Class-cne'#32770'-and$window.Class-cnotlike'WindowsForms10.*'-and[long]$window.Owner-ne[long]$Owner.window_handle){continue}
  $children=@(&$ReadChildren ([long]$window.Handle))
  if(@($children|Where-Object {[int]$_.ProcessId-ne[int]$Owner.process_id}).Count){throw 'DIM_POPUP_CHILD_OWNER'}
  $text=@($children|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_.Title)}|Select-Object Handle,Class,Title)
  $kind='UNEXPECTED_OWNED_WINDOW_REVIEW_REQUIRED'
  if($window.Class-ceq'#32770'-and$window.Title-ceq'安全性 - 未签名的可执行文件'){$kind='TRUSTED_LOAD_PROMPT_CANDIDATE'}
  $message=@($text|Where-Object {$_.Class-clike'WindowsForms10.STATIC.*'-and$_.Title-match'未经处理的异常'-and$_.Title-match'(^|[\r\n ])DOCUMENT_IDENTITY[。.\r\n ]*$'})
  $go=@($text|Where-Object {$_.Class-clike'WindowsForms10.BUTTON.*'-and$_.Title-ceq'继续(&C)'})
  $details=@($text|Where-Object {$_.Class-clike'WindowsForms10.BUTTON.*'-and$_.Title-ceq'详细信息(&D)'})
  if($window.Class-clike'WindowsForms10.Window.*'-and$window.Title-ceq'AutoCAD'-and[long]$window.Owner-eq[long]$Owner.window_handle-and$message.Count-eq1-and$go.Count-eq1-and$details.Count-eq1-and$text.Count-eq3){$kind='DOCUMENT_IDENTITY_MANAGED_EXCEPTION'}
  $result.Add([pscustomobject]@{handle=[long]$window.Handle;owner=[long]$window.Owner;class=[string]$window.Class;title=[string]$window.Title;classification=$kind;children=$text;automatic_dismiss_authorized=$false})
 }
 [pscustomobject]@{status='OBSERVED_READ_ONLY';owner_id=$Owner.id;process_id=[int]$Owner.process_id;main_handle=[long]$Owner.window_handle;main_enabled=[bool]$main[0].Enabled;popups=$result.ToArray();blocking_popup_count=@($result|Where-Object classification -CNE TRUSTED_LOAD_PROMPT_CANDIDATE).Count;cad_commands=0;clicks=0;foreground_actions=0}
}

function Read-DimOwnedPopupSnapshotV3 {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Owner)
 $process=Get-Process -Id $Owner.process_id -ErrorAction Stop
 if($process.StartTime.ToUniversalTime().Ticks-ne([datetime]$Owner.process_start_time_utc).ToUniversalTime().Ticks-or$process.Path-ine$Owner.process_image_path){throw 'DIM_POPUP_PROCESS_IDENTITY'}
 $helper=Join-Path $Root 'reference/project-orchestration/scripts/cad_ui_helper.ps1'
 $windows=@(&$helper -Action ListAllRaw -ProcessId $Owner.process_id)
 $read={
  param($handle)
  foreach($child in @(&$helper -Action ListChildrenRaw -WindowHandle $handle)){
   # ListChildrenRaw returns no PID field. Read it from the actual handle;
   # never insert the expected PID as if it were observed evidence.
   [uint32]$childProcessId=0
   $thread=[CadWin32]::GetWindowThreadProcessId([IntPtr]([long]$child.Handle),[ref]$childProcessId)
   if($thread-eq0-or$childProcessId-eq0){throw 'DIM_POPUP_CHILD_HANDLE_STALE'}
   $child|Add-Member NoteProperty ProcessId ([int]$childProcessId)
   $child
  }
 }.GetNewClosure()
 $snapshot=ConvertTo-DimOwnedPopupSnapshotV3 -Owner $Owner -Windows $windows -ReadChildren $read
 $snapshot|Add-Member NoteProperty observed_at ([DateTimeOffset]::Now.ToString('o'))
 $snapshot
}
