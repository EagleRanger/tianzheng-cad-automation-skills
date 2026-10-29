function New-CadABNativeExpressionV8($Scope,$Operation,$Owner) {
 $lens=Get-CadNativeOperationLensV8 $Scope $Operation
 if($Operation.kind-ceq'PREPARE'){
  $source=New-CadBackgroundNativeReadExpressionV4 $lens $Operation $Owner
  $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
  $load='(progn (command "_.NETLOAD" '+(ConvertTo-CadProbeLispStringV1 (Join-Path $root $Scope.module_path))+') (princ))'+"`r"
  if(([regex]::Matches($source,[regex]::Escape($load))).Count-ne1){throw 'NATIVE8_LOAD_FORM_NOT_UNIQUE'}
  $hostGuard='(and (= (rem (+ (vla-get-HWND (vlax-get-acad-object)) 4294967296.0) 4294967296.0) '+$Owner.window_handle+') (= (strcase (vla-get-FullName (vla-get-ActiveDocument (vlax-get-acad-object)))) (strcase '+(ConvertTo-CadProbeLispStringV1 $Owner.document_full_path)+')))'
  $conditional='(progn (if (and '+$hostGuard+' (not (getcname "CXANNOTATIONCONTROLREADV1"))) (command "_.NETLOAD" '+(ConvertTo-CadProbeLispStringV1 (Join-Path $root $Scope.module_path))+')) (princ))'+"`r"
  $source=$source.Replace($load,$conditional);$oldReg=Join-Path (Split-Path $lens.native_report) 'module_registration.log'
 }elseif($Operation.kind-ceq'READ'){
  $source=New-CadBackgroundNativeReadExpressionV5 $lens $Operation $Owner
  $oldReg=Join-Path (Split-Path $lens.native_report) 'reader_availability.log'
 }else{throw 'NATIVE8_EXPRESSION_KIND'}
 $oldIdentity='|'+$Scope.run_id+'|A1|A|';$newIdentity='|'+$Scope.run_id+'|'+$Operation.id+'|'+$Operation.owner+'|'
 if(([regex]::Matches($source,[regex]::Escape($oldIdentity))).Count-ne1){throw 'NATIVE8_NATIVE_IDENTITY_ADAPTER_NOT_UNIQUE'}
 $source=$source.Replace($oldIdentity,$newIdentity)
 $old=ConvertTo-CadProbeLispStringV1 $oldReg;$new=ConvertTo-CadProbeLispStringV1 $Operation.registration_path
 if(([regex]::Matches($source,[regex]::Escape($old))).Count-ne1){throw 'NATIVE8_REGISTRATION_PATH_ADAPTER_NOT_UNIQUE'}
 $source=$source.Replace($old,$new)
 if($source.Length-gt6144-or$source-match'(?i)\(setvar|\(entmod|\(entmake|vla-Save|vla-Close'){throw 'NATIVE8_EXPRESSION_FORBIDDEN'}
 if($Operation.kind-ceq'READ'-and$source-match'(?i)NETLOAD'){throw 'NATIVE8_READ_MUST_NOT_LOAD'}
 foreach($form in @($source-split"`r")){if($form.Length-gt2048){throw 'NATIVE8_FORM_ENGINEERING_BUDGET'}}
 $source
}
function Read-CadABReaderRegistrationV8($Scope,$Operation) {
 if(-not(Test-Path $Operation.registration_path)){throw 'NATIVE8_REGISTRATION_MISSING'}
 $f=[IO.File]::ReadAllText($Operation.registration_path).Trim().Split('|')
 if($f.Count-ne3-or$f[0]-cne$Operation.nonce-or$f[1]-cnotin@('0','1')-or$f[2]-cne'1'){throw 'NATIVE8_READER_NOT_REGISTERED'}
 if($Operation.kind-ceq'READ'-and$f[1]-cne'1'){throw 'NATIVE8_READER_MISSING_AT_READ_ENTRY'}
 [pscustomobject]@{registered_before=($f[1]-ceq'1');registered_after=$true;new_module_registration_count=$(if($f[1]-ceq'0'){1}else{0});module_image_identity_independently_read=$false;proof_sha256=(Get-FileHash $Operation.registration_path).Hash}
}
function Read-CadABReaderStageV8($Scope,$Operation) {
 $lens=Get-CadNativeOperationLensV8 $Scope $Operation
 if($Operation.kind-ceq'PREPARE'){$stages=Read-CadModuleLoadStagesV4 $lens}else{$stages=Read-CadReaderStagesV5 $lens}
 if(-not$stages.complete){throw 'NATIVE8_STAGE_INCOMPLETE'}
 $context=Read-CadModuleLoadContextV4 $lens
 if(-not$context.complete-or-not$context.settings_unchanged){throw 'NATIVE8_CONTEXT_UNSETTLED'}
 [pscustomobject]@{stages=$stages;context=$context;registration=(Read-CadABReaderRegistrationV8 $Scope $Operation)}
}
