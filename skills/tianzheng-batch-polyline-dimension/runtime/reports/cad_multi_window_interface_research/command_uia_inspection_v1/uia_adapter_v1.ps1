function Read-CadCommandUiaSubtreeV1($Root,[scriptblock]$FreshGuard,[scriptblock]$ValidateNative,[scriptblock]$Emit){
 # Assembly loading alone is exercised offline. All UIA methods below are live-only.
 $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
 $rootFactory={ [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Root.surface_handle) }
 $describe={
  param($element,[string]$parentId,[bool]$isRoot)
  & $FreshGuard
  $info=$element.Current
  $processId=$info.ProcessId
  if($processId-ne$Root.process_id){throw 'UIA_FOREIGN_PROCESS_BEFORE_TEXT'}
  $runtimeId=$element.GetRuntimeId()-join'.'
  if([string]::IsNullOrWhiteSpace($runtimeId)){throw 'UIA_RUNTIME_ID_EMPTY'}
  if($info.IsPassword){throw 'UIA_PASSWORD_BEFORE_TEXT'}
  if(-not$isRoot){
   # Exactly one logical parent check; never walk above the selected root.
   $parentElement=$walker.GetParent($element)
   if($null-eq$parentElement-or$parentElement.Current.ProcessId-ne$Root.process_id-or($parentElement.GetRuntimeId()-join'.')-cne$parentId){throw 'UIA_PARENT_CHANGED_BEFORE_TEXT'}
  }
  $hwnd=[long]$info.NativeWindowHandle
  $nativeVerified=if($hwnd-ne0){[bool](& $ValidateNative $hwnd)}else{$true}
  if(-not$nativeVerified){throw 'UIA_NATIVE_IDENTITY_BEFORE_TEXT'}
  if($isRoot-and$hwnd-ne$Root.surface_handle){throw 'UIA_ROOT_HWND_CHANGED'}
  $node=[pscustomobject]@{runtime_id=$runtimeId;parent_runtime_id=$parentId;process_id=$processId;native_window_handle=$hwnd;native_identity_verified=$nativeVerified;name=[string]$info.Name;automation_id=[string]$info.AutomationId;class_name=[string]$info.ClassName;framework_id=[string]$info.FrameworkId;control_type=[string]$info.ControlType.ProgrammaticName;is_password=$false;enabled=[bool]$info.IsEnabled;offscreen=[bool]$info.IsOffscreen;keyboard_focus=[bool]$info.HasKeyboardFocus}
  Assert-CadCommandUiaMetadataV1 $node $Root $parentId $isRoot
  $node
 }
 $read={
  param($element,$before)
  & $FreshGuard
  $info=$element.Current
  if($info.ProcessId-ne$Root.process_id-or$info.IsPassword-or($element.GetRuntimeId()-join'.')-cne$before.runtime_id){throw 'UIA_IDENTITY_CHANGED_BEFORE_PATTERNS'}
  $value='';$text='';$pattern=$null
  if($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){$value=[string]$pattern.Current.Value;if($value.Length-ge4096){throw 'UIA_VALUE_LIMIT'}}
  $pattern=$null
  if($element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern,[ref]$pattern)){$text=[string]$pattern.DocumentRange.GetText(4096);if($text.Length-ge4096){throw 'UIA_TEXT_LIMIT'}}
  [pscustomobject]@{value_text=$value;document_text=$text}
 }
 Invoke-CadCommandUiaWalkV1 $Root $rootFactory $describe $read {param($e) $walker.GetFirstChild($e)} {param($e) $walker.GetNextSibling($e)} $FreshGuard $Emit
}
