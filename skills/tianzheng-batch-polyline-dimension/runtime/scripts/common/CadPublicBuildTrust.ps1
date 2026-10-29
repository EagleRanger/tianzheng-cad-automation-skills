# Receiver-local identity/environment adapter. No CAD/COM calls at import.
function Resolve-CadPublicLocalFile {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath)
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 if([IO.Path]::IsPathRooted($RelativePath)){throw 'PUBLIC_RELATIVE_PATH_REQUIRED'}
 $full=[IO.Path]::GetFullPath((Join-Path $base $RelativePath))
 if(-not$full.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PUBLIC_PATH_OUTSIDE_ROOT'}
 $cursor=$full
 while($cursor.Length-gt$base.Length){if((Test-Path -LiteralPath $cursor)-and((Get-Item -LiteralPath $cursor).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'PUBLIC_REPARSE_PATH'};$cursor=Split-Path -Parent $cursor}
 if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "PUBLIC_INPUT_MISSING:$RelativePath"}
 $full
}
function Get-CadPublicTrustedModuleHash {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath)
 $pin=$env:CAD_BUILD_MANIFEST_SHA256
 if($pin-cnotmatch'^[A-Fa-f0-9]{64}$'){throw 'CAD_BUILD_MANIFEST_SHA256_REQUIRED_FROM_TRUSTED_BUILD'}
 $path=Resolve-CadPublicLocalFile -Root $Root -RelativePath 'config/receiver_build_manifest.json'
 if((Get-FileHash -LiteralPath $path).Hash-ine$pin){throw 'PUBLIC_BUILD_MANIFEST_PIN_MISMATCH'}
 $manifest=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
 if($manifest.schema_version-ne1-or$manifest.kind-cne'RECEIVER_LOCAL_BUILD_ONLY'-or$manifest.cad_loaded-isnot[bool]-or$manifest.cad_loaded){throw 'PUBLIC_BUILD_MANIFEST_KIND'}
 $module=@($manifest.modules|Where-Object path -CEQ $RelativePath)
 if($module.Count-ne1-or$module[0].sha256-cnotmatch'^[A-F0-9]{64}$'){throw 'PUBLIC_TRUSTED_MODULE_NOT_UNIQUE'}
 foreach($source in @($module[0].sources)){
  $sourcePath=Resolve-CadPublicLocalFile -Root $Root -RelativePath $source.path
  if((Get-FileHash -LiteralPath $sourcePath).Hash-cne$source.sha256){throw 'PUBLIC_MODULE_SOURCE_CHANGED'}
 }
 $dll=Resolve-CadPublicLocalFile -Root $Root -RelativePath $RelativePath
 if([IO.Path]::GetExtension($dll)-ine'.dll'-or(Get-FileHash -LiteralPath $dll).Hash-cne$module[0].sha256){throw 'PUBLIC_MODULE_BINARY_CHANGED'}
 [string]$module[0].sha256
}
function Assert-CadPublicReceiverConfiguration {
 param([Parameter(Mandatory)][string]$Root)
 $path=Resolve-CadPublicLocalFile -Root $Root -RelativePath 'config/receiver_runtime.json'
 $config=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
 if($config.schema_version-ne1-or$config.kind-cne'RECEIVER_LOCAL_INPUT'-or$config.execution_enabled-isnot[bool]-or-not$config.execution_enabled){throw 'PUBLIC_RECEIVER_EXECUTION_NOT_CONFIGURED'}
 foreach($field in @('issuer_thread_id','executor_thread_id')){if([string]::IsNullOrWhiteSpace([string]$config.$field)-or[string]$config.$field-match'REQUIRED|EXAMPLE|TEMPLATE'){throw 'PUBLIC_RECEIVER_IDENTITIES_REQUIRED'}}
 $routing=Get-Content -LiteralPath (Resolve-CadPublicLocalFile -Root $Root -RelativePath 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String
 if($routing.execution.thread_id-cne$config.executor_thread_id-or$routing.routes.batch_polyline_dimension.ready_issuer_thread_id-cne$config.issuer_thread_id-or$routing.execution.dispatch_enabled-isnot[bool]-or-not$routing.execution.dispatch_enabled){throw 'PUBLIC_RECEIVER_ROUTING_NOT_BOUND'}
}
function Get-CadPublicSourceAdmission {
 param([Parameter(Mandatory)][string]$Root)
 $pin=$env:CAD_SOURCE_ADMISSION_SHA256
 if($pin-cnotmatch'^[A-Fa-f0-9]{64}$'){throw 'CAD_SOURCE_ADMISSION_SHA256_REQUIRED'}
 $path=Resolve-CadPublicLocalFile -Root $Root -RelativePath 'config/receiver_source_admission.json'
 if((Get-FileHash -LiteralPath $path).Hash-ine$pin){throw 'PUBLIC_SOURCE_ADMISSION_PIN'}
 $admission=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -DateKind String
 if($admission.kind-cne'RECEIVER_EXPLICIT_SOURCE_ADMISSION'-or$admission.sha256-cnotmatch'^[A-F0-9]{64}$'){throw 'PUBLIC_SOURCE_ADMISSION_UNCONFIGURED'}
 $source=Resolve-CadPublicLocalFile -Root $Root -RelativePath $admission.path
 if([IO.Path]::GetExtension($source)-ine'.dwg'-or(Get-FileHash -LiteralPath $source).Hash-cne$admission.sha256){throw 'PUBLIC_SOURCE_ADMISSION_SOURCE_CHANGED'}
 $admission
}
