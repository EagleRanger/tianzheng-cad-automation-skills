. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/command_probe_v3/file_binding_v3.ps1')
function Get-CadProbeRetainedABindingV4($Owners,$Owner,$Application,$State,[scriptblock]$SnapshotsReader,[scriptblock]$Emit) {
 if($Owner.id-cne'A'){throw 'PROBE_RETAINED_APPLICATION_ONLY_A'}
 $State.bind_count++;if($State.bind_count-gt3){throw 'PROBE_A_PHASE_BIND_LIMIT'}
 $before=@(&$SnapshotsReader);Assert-CadProbeSnapshotsV3 $Owners $Owner $before
 $snapshot=@($before|Where-Object id -CEQ A)[0]
 # The initial frozen ROT acquisition selected this exact A. No enumeration
 # or sibling-native getter after the dual-ready barrier is permitted.
 $r=Select-CadExactTargetTraceV4 -Entries @([pscustomobject]@{Name='retained_exact_A_application';Instance=$Application}) -Expected $Owner -Snapshot $snapshot -Intent Read -TraceSink {param($x)$null=&$Emit @{stage='RETAINED_A_STRICT';bind=$State.bind_count;data=$x}}
 if($r.status-cne'PASS'-or$r.intent-cne'Read'){throw ('PROBE_RETAINED_A_BIND:'+ $r.code)}
 $after=@(&$SnapshotsReader);Assert-CadProbeSnapshotsV3 $Owners $Owner $after
 foreach($id in @('A','B')){foreach($f in @('process_id','process_start_time_utc','process_image_path','window_handle','window_process_id','window_valid')){if([string](@($before|Where-Object id -CEQ $id)[0].$f)-cne[string](@($after|Where-Object id -CEQ $id)[0].$f)){throw 'PROBE_RETAINED_A_IDENTITY_CHANGED'}}}
 $r
}
