# Extracts historical evidence only, never asserts that an old HWND is fresh.
function Get-CadCommandNativeAnchorV1($Rows,$Owner,[string]$EvidenceSha256){
 if($EvidenceSha256-cnotmatch'^[A-F0-9]{64}$'){throw 'ANCHOR_SOURCE_HASH_REQUIRED'}
 $valid=[Collections.Generic.List[object]]::new()
 foreach($row in $Rows){
  if($row.kind-cne'TEXT_RETURN'-or-not$row.identity_stable-or-not$row.text_read.complete-or$row.text_read.timeout-or$row.text_read.truncated){continue}
  $n=$row.before;$a=$row.after
  if(-not$n.valid-or-not$n.visible-or-not$n.enabled-or$n.pid-ne$Owner.process_id-or$n.thread-le0-or$n.root-ne$Owner.window_handle-or$n.root_owner-ne$Owner.window_handle-or-not$n.child_of_main-or-not$n.style_child-or$n.style_popup-or$n.parent-ne$n.structural_parent){continue}
  $stable=$true
  foreach($f in @('hwnd','pid','thread','parent','structural_parent','root','root_owner','valid','visible','enabled','window_style','style_child','style_popup','window_class','control_id','child_of_main')){
   if([string]$n.$f-cne[string]$a.$f){$stable=$false;break}
  }
  if($stable){$valid.Add($row)}
 }
 $top=@($valid|Where-Object {$_.before.parent-eq$Owner.window_handle-and$_.before.window_class-ceq'AfxControlBar140u'-and$_.text_read.text-ceq'CLI PaletteSet'})
 if($top.Count-ne1){throw 'ANCHOR_TOP_NOT_UNIQUE'}
 $middle=@($valid|Where-Object {$_.before.parent-eq$top[0].before.hwnd-and$_.before.window_class-ceq'AfxWnd140u'-and$_.text_read.text-ceq'CLI PaletteSet'})
 if($middle.Count-ne1){throw 'ANCHOR_MIDDLE_NOT_UNIQUE'}
 $palette=@($valid|Where-Object {$_.before.parent-eq$middle[0].before.hwnd-and$_.before.window_class-ceq'AfxWnd140u'-and$_.text_read.text-ceq'CLI Palette'})
 if($palette.Count-ne1){throw 'ANCHOR_PALETTE_NOT_UNIQUE'}
 $leaf=@($valid|Where-Object {$_.before.parent-eq$palette[0].before.hwnd-and([string]$_.before.window_class).StartsWith('HwndWrapper[')})
 if($leaf.Count-ne1){throw 'ANCHOR_SURFACE_NOT_UNIQUE'}
 $chain=@($top[0],$middle[0],$palette[0],$leaf[0])
 if(@($chain.before.hwnd|Select-Object -Unique).Count-ne4){throw 'ANCHOR_CHAIN_CYCLE'}
 [pscustomobject]@{status='HISTORICAL_ANCHOR_EVIDENCE_ONLY';process_id=$Owner.process_id;main_window_handle=$Owner.window_handle;source_sha256=$EvidenceSha256;chain=@($chain|ForEach-Object{[pscustomobject]@{native=$_.before;text=$_.text_read.text}});surface_handle=$leaf[0].before.hwnd;fresh_native_chain_verified=$false;uia_called=$false;send_authorized=$false}
}
