param([string]$DraftPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($leaf in @('channel_contract_v11.ps1','invoke_channel_v11.ps1','launch_channel_v11.ps1','publish_channel_request_v11.ps1','receive_channel_result_v11.ps1','build_channel_draft_v11.ps1')){$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $leaf),[ref]$t,[ref]$e);if($e.Count){throw ($leaf+':'+($e.Message-join'|'))}}
$test=Join-Path ([IO.Path]::GetTempPath()) ('CadChannelTests_'+[guid]::NewGuid().ToString('N')+'.exe')
& 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe' /nologo /target:exe ('/out:'+$test) /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'FixedTaskProtocol.cs') (Join-Path $PSScriptRoot 'ChannelProtocolV11.cs') (Join-Path $PSScriptRoot 'ChannelProtocolTestsV11.cs')
if($LASTEXITCODE-ne0){throw 'CHANNEL_PROTOCOL_TEST_BUILD'};& $test;if($LASTEXITCODE-ne0){throw 'CHANNEL_PROTOCOL_TEST_FAILED'}
if($DraftPath){& (Join-Path $PSScriptRoot 'invoke_channel_v11.ps1') -ReadyHandoffPath $DraftPath -PreflightOnly}
[pscustomobject]@{status='PASS_CHANNEL_OFFLINE_ONLY';CAD_calls=0}


