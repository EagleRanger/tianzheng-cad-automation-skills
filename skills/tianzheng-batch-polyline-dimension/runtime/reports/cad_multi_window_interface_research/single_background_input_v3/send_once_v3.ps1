function Assert-CadBBackgroundForegroundV3($Foreground,$Owner){
 if($null-eq$Foreground-or$Foreground.hwnd-le0-or$Foreground.pid-le0-or$Foreground.pid-eq$Owner.process_id){throw 'B_BACKGROUND_TARGET_FOREGROUND_OR_UNKNOWN'}
}
function Invoke-CadBOneDocumentSendV3($State,$Document,[string]$Expression){
 if($State.entered){throw 'B_BACKGROUND_SEND_ALREADY_ENTERED_NO_RETRY'}
 $State.entered=$true
 $null=$Document.SendCommand($Expression)
 $State.returned=$true
}
