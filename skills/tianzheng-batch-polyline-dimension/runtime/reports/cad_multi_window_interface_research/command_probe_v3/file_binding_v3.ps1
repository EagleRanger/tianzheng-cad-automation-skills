function Assert-CadProbeSnapshotsV3($Owners,$Target,$Snapshots) {
 if(@($Snapshots).Count-ne2){throw 'PROBE_SNAPSHOT_COUNT'}
 foreach($o in $Owners){
  $rows=@($Snapshots|Where-Object id -CEQ $o.id);if($rows.Count-ne1){throw 'PROBE_SNAPSHOT_OWNER'}
  $s=$rows[0];Assert-CadBindingDiagnosticSnapshotV1 $o $s
  if(-not$s.serial_lease_held){throw 'PROBE_LEASE'}
  # Only this worker's target must be idle; the sibling may be running its probe.
  if($o.id-ceq$Target.id-and(-not$s.window_enabled-or-not$s.responding-or$s.modal_state-cne'NONE')){throw 'PROBE_TARGET_NOT_READY'}
 }
}
function Get-CadProbeFileBindingV3($Owners,$Owner,$Lookup,$State,[scriptblock]$SnapshotsReader,[scriptblock]$Emit,[switch]$OfflineManagedFixture) {
 $State.bind_count++;if($State.bind_count-gt3){throw 'PROBE_BIND_LIMIT'}
 $before=@(&$SnapshotsReader);Assert-CadProbeSnapshotsV3 $Owners $Owner $before
 $snap=@($before|Where-Object id -CEQ $Owner.id)[0]
 $r=Select-CadFileDocumentV8 -Document $Lookup.entry.Instance -Lookup $Lookup -FullPath $Owner.document_full_path -Expected $Owner -Snapshot $snap -TraceSink {param($x)$null=&$Emit @{stage='FILE_DOCUMENT_IDENTITY';bind=$State.bind_count;data=$x}} -OfflineManagedFixture:$OfflineManagedFixture
 if($r.status-cne'PASS'-or$r.intent-cne'Read'){throw ('PROBE_DOCUMENT_BIND:'+ $r.code)}
 $after=@(&$SnapshotsReader);Assert-CadProbeSnapshotsV3 $Owners $Owner $after
 foreach($id in @('A','B')){foreach($f in @('process_id','process_start_time_utc','process_image_path','window_handle','window_process_id','window_valid')){if([string](@($before|Where-Object id -CEQ $id)[0].$f)-cne[string](@($after|Where-Object id -CEQ $id)[0].$f)){throw 'PROBE_IDENTITY_CHANGED_DURING_BIND'}}}
 $r
}
