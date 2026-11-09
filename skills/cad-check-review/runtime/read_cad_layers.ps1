param([Parameter(Mandatory=$true)][string]$Manifest)
$ErrorActionPreference='Stop'
$env:PSModulePath=$env:WINDIR+'\System32\WindowsPowerShell\v1.0\Modules'
$m=ConvertFrom-Json ([IO.File]::ReadAllText($Manifest))
if(Test-Path -LiteralPath $m.receipt){throw 'LAYER_RECEIPT_EXISTS'}
$doc=$null;$app=$null;$layerCollection=$null;$proc=$null
try {
    Add-Type @'
using System;using System.Runtime.InteropServices;
public static class CadLayerWindowIdentity {
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
}
'@
    $proc=[Diagnostics.Process]::GetProcessById([int]$m.host.pid)
    if($proc.StartTime.ToUniversalTime().ToFileTimeUtc() -ne [int64]$m.host.created){throw 'LAYER_HOST_REUSED'}
    if(-not [String]::Equals($proc.MainModule.FileName,$m.host.image,[StringComparison]::OrdinalIgnoreCase)){throw 'LAYER_HOST_IMAGE_CHANGED'}
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject($m.com_progid)
    [uint32]$windowPid=0
    [void][CadLayerWindowIdentity]::GetWindowThreadProcessId([IntPtr][int64]$app.HWND,[ref]$windowPid)
    if($windowPid -ne [uint32]$m.host.pid){throw 'LAYER_COM_HOST_MISMATCH'}
    $doc=$app.ActiveDocument
    if(-not [String]::Equals([IO.Path]::GetFullPath($doc.FullName),[IO.Path]::GetFullPath($m.document),[StringComparison]::OrdinalIgnoreCase)){throw 'LAYER_DOCUMENT_CHANGED'}
    if([int]$doc.GetVariable('CMDACTIVE') -ne 0){throw 'LAYER_COMMAND_ACTIVE'}
    $statusBefore=[IO.File]::ReadAllText($m.session_status)
    $s=ConvertFrom-Json $statusBefore
    if($s.status -ne 'READY_SAME_DOCUMENT' -or $s.last_sha256 -ne $m.source_sha256 -or $s.last_saved -ne $m.saved_path){throw 'LAYER_CHECKPOINT_CHANGED'}
    $before=$doc.GetVariable('DBMOD')
    $found=New-Object 'System.Collections.Generic.List[string]'
    $layerCollection=$doc.Layers
    $rows=@($layerCollection | ForEach-Object {
        $layer=$_
        try {
            if($m.names -contains $layer.Name){
                $found.Add([string]$layer.Name)
                [pscustomobject]@{name=$layer.Name;on=[bool]$layer.LayerOn;frozen=[bool]$layer.Freeze;locked=[bool]$layer.Lock;color=[int]$layer.Color;plottable=[bool]$layer.Plottable;lineweight=[int]$layer.Lineweight;linetype=$layer.Linetype}
            }
        } finally {if($null -ne $layer){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($layer)}}
    })
    $missing=@($m.names | Where-Object {$found -notcontains $_})
    $lockFade=$doc.GetVariable('LAYLOCKFADECTL')
    $xrefFade=$doc.GetVariable('XDWGFADECTL')
    $after=$doc.GetVariable('DBMOD')
    if($before -ne $after -or $statusBefore -ne [IO.File]::ReadAllText($m.session_status) -or $app.ActiveDocument.FullName -ne $m.document -or [int]$doc.GetVariable('CMDACTIVE') -ne 0){throw 'LAYER_DOCUMENT_CHANGED_DURING_READ'}
    $result=@{status='READ_ONLY_LAYER_STATE';scope='global layer table; per-viewport freezing is not included';pid=$m.host.pid;document=$m.document;saved_path=$m.saved_path;source_sha256=$m.source_sha256;dbmod_before=$before;dbmod_after=$after;layers=@($rows);missing=@($missing);laylockfadectl=$lockFade;xdwgfadectl=$xrefFade;cad_modified=$false;captured_at=[DateTime]::UtcNow.ToString('o')}
} catch {
    $result=@{status='LAYER_QUERY_FAILED';error=$_.Exception.Message;cad_modified=$false}
} finally {
    foreach($obj in @($layerCollection,$doc,$app)){if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)}}
    if($null -ne $proc){$proc.Dispose()}
}
[IO.File]::WriteAllText($m.receipt,(ConvertTo-Json -InputObject $result -Depth 7),(New-Object Text.UTF8Encoding($false)))
if($result.status -ne 'READ_ONLY_LAYER_STATE'){exit 2}
