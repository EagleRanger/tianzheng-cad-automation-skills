$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$compiler='C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe';$out=Join-Path $PSScriptRoot 'bin/CadChannelV11.dll'
$refs=@('System.Web.Extensions.dll','C:/Windows/Microsoft.NET/Framework64/v4.0.30319/WPF/PresentationCore.dll')+@('acmgd.dll','acdbmgd.dll','accoremgd.dll'|ForEach-Object{Join-Path 'C:/Program Files/Autodesk/AutoCAD 2021' $_})
& $compiler /nologo /target:library /optimize+ ('/out:'+$out) @($refs|ForEach-Object{'/reference:'+$_}) (Join-Path $PSScriptRoot 'FixedTaskProtocol.cs') (Join-Path $PSScriptRoot 'ChannelProtocolV11.cs') (Join-Path $PSScriptRoot 'ChannelModuleV11.cs');if($LASTEXITCODE-ne0){throw 'V11_CHANNEL_BUILD_FAILED'}
[pscustomobject]@{status='COMPILED_NOT_LOADED';sha256=(Get-FileHash $out).Hash;CAD_calls=0}




