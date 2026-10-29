param([Parameter(Mandatory)]$Draft, [Parameter(Mandatory)]$Contract)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Get-ScopeField($Object, [string]$Name) {
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { throw "BASEBOARD_FIELD_MISSING:$Name" }
    return $p.Value
}
function Resolve-ProjectEvidence([string]$RelativePath, [string]$Hash) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $Hash -cnotmatch '^[A-F0-9]{64}$') { throw 'BASEBOARD_EVIDENCE_BINDING_INVALID' }
    $p = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $p.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_EVIDENCE_OUTSIDE_PROJECT' }
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne $Hash) { throw 'BASEBOARD_EVIDENCE_HASH_MISMATCH' }
    return $p
}
$scope = Get-ScopeField $Draft 'baseboard_extract_scope'
if ([string](Get-ScopeField $scope 'contract_id') -cne [string]$Contract.id) { throw 'BASEBOARD_CONTRACT_MISMATCH' }
$stage = [string]$Contract.stages.default
if ($null -ne $scope.PSObject.Properties['stage']) { $stage = [string]$scope.stage }
if ($stage -cnotin @('EXPORT','INDEPENDENT_REOPEN_AUDIT','COMPLETE_COPY_REMOVE_IDENTIFIED','COMPLETE_COPY_CLEAR_EXISTING_LAYOUTS','REFINE_SAVED_ENGINEERING_BASEBOARD')) { throw 'BASEBOARD_STAGE_INVALID' }
$refineSaved = $stage -ceq 'REFINE_SAVED_ENGINEERING_BASEBOARD'
$completeCopy = $stage -cin @('COMPLETE_COPY_REMOVE_IDENTIFIED','COMPLETE_COPY_CLEAR_EXISTING_LAYOUTS','REFINE_SAVED_ENGINEERING_BASEBOARD')
$equivalenceOptIn = $scope.PSObject.Properties['paper_viewport_equivalence_contract_id']
if ($null -ne $equivalenceOptIn) {
    $equivalence = $Contract.stages.COMPLETE_COPY_REMOVE_IDENTIFIED.paper_viewport_comparison
    if ($stage -cne 'COMPLETE_COPY_REMOVE_IDENTIFIED' -or $equivalenceOptIn.Value -isnot [string] -or $equivalenceOptIn.Value -cne [string]$equivalence.id) { throw 'BASEBOARD_PAPER_VIEWPORT_EQUIVALENCE_CONTRACT_INVALID' }
}
foreach ($f in @($Contract.required_true)) {
    $v = Get-ScopeField $scope $f
    if ($v -isnot [bool] -or -not $v) { throw "BASEBOARD_PROTECTION_MISSING:$f" }
}
foreach ($f in @($Contract.required_false)) {
    $v = Get-ScopeField $scope $f
    if ($v -isnot [bool] -or $v) { throw "BASEBOARD_FORBIDDEN:$f" }
}
$actions = @(Get-ScopeField $scope 'allowed_actions')
if ($stage -ceq 'EXPORT') {
    if ($actions.Count -eq 0 -or 'export_test_subset_wblock' -cnotin $actions) { throw 'BASEBOARD_EXPORT_ACTION_MISSING' }
    foreach ($a in $actions) { if ([string]$a -cnotin @($Contract.allowed_actions)) { throw 'BASEBOARD_ACTION_NOT_ADMITTED' } }
} elseif ($stage -ceq 'INDEPENDENT_REOPEN_AUDIT') {
    $auditContract = $Contract.stages.INDEPENDENT_REOPEN_AUDIT
    foreach ($a in $actions) { if ([string]$a -cnotin @($auditContract.allowed_actions)) { throw 'BASEBOARD_AUDIT_ACTION_NOT_ADMITTED' } }
    foreach ($a in @($auditContract.required_actions)) { if ($a -cnotin $actions) { throw 'BASEBOARD_AUDIT_ACTION_MISSING' } }
    foreach ($f in @($auditContract.required_true)) { $v=Get-ScopeField $scope $f; if ($v -isnot [bool] -or -not $v) { throw "BASEBOARD_AUDIT_PROTECTION_MISSING:$f" } }
    foreach ($f in @($auditContract.zero_counts)) { $v=Get-ScopeField $scope $f; if (($v -isnot [int] -and $v -isnot [long]) -or $v -ne 0) { throw "BASEBOARD_AUDIT_NONZERO_COUNT:$f" } }
    foreach ($f in @($auditContract.one_counts)) { $v=Get-ScopeField $scope $f; if (($v -isnot [int] -and $v -isnot [long]) -or $v -ne 1) { throw "BASEBOARD_AUDIT_ONCE_COUNT_INVALID:$f" } }
} else {
    $copyContract = Get-ScopeField $Contract.stages $stage
    foreach ($a in $actions) { if ([string]$a -cnotin @($copyContract.allowed_actions)) { throw 'BASEBOARD_COMPLETE_COPY_ACTION_NOT_ADMITTED' } }
    foreach ($a in @($copyContract.required_actions)) { if ($a -cnotin $actions) { throw 'BASEBOARD_COMPLETE_COPY_ACTION_MISSING' } }
    foreach ($f in @($copyContract.required_true)) { $v=Get-ScopeField $scope $f; if ($v -isnot [bool] -or -not $v) { throw "BASEBOARD_COMPLETE_COPY_PROTECTION_MISSING:$f" } }
    foreach ($f in @($copyContract.required_false)) { $v=Get-ScopeField $scope $f; if ($v -isnot [bool] -or $v) { throw "BASEBOARD_COMPLETE_COPY_FORBIDDEN:$f" } }
    foreach ($f in @($copyContract.zero_counts)) { $v=Get-ScopeField $scope $f; if (($v -isnot [int] -and $v -isnot [long]) -or $v -ne 0) { throw "BASEBOARD_COMPLETE_COPY_NONZERO_COUNT:$f" } }
    foreach ($f in @($copyContract.one_counts)) { $v=Get-ScopeField $scope $f; if (($v -isnot [int] -and $v -isnot [long]) -or $v -ne 1) { throw "BASEBOARD_COMPLETE_COPY_ONCE_COUNT_INVALID:$f" } }
}
$policy = [string](Get-ScopeField $scope 'annotation_policy')
if (($refineSaved -and $policy -cne $Contract.stages.REFINE_SAVED_ENGINEERING_BASEBOARD.annotation_policy) -or (-not $refineSaved -and $policy -cnotin @($Contract.annotation_policies))) { throw 'BASEBOARD_ANNOTATION_POLICY_INVALID' }
if ([string](Get-ScopeField $scope 'prior_dirty_owner_policy') -cne [string]$Contract.prior_dirty_owner_policy) { throw 'BASEBOARD_DIRTY_OWNER_POLICY_INVALID' }
$sourceManifest = Get-Content -LiteralPath (Join-Path $root $Contract.source_manifest) -Raw -Encoding UTF8 | ConvertFrom-Json
$sources = @($sourceManifest.files | Where-Object { $_.role -ceq $Contract.source_role })
if ($sources.Count -ne 1 -or [string](Get-ScopeField $scope 'source_role') -cne [string]$Contract.source_role) { throw 'BASEBOARD_SOURCE_ROLE_INVALID' }
$sourcePath = [IO.Path]::GetFullPath((Join-Path $sourceManifest.source_directory $sources[0].relative_name))
$sourceHash = [string]$sources[0].sha256
if (-not [string]::Equals([IO.Path]::GetFullPath([string](Get-ScopeField $scope 'source_path')), $sourcePath, [StringComparison]::OrdinalIgnoreCase) -or [string](Get-ScopeField $scope 'source_sha256') -cne $sourceHash -or (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne $sourceHash) { throw 'BASEBOARD_SOURCE_IDENTITY_MISMATCH' }
$inputHash=$sourceHash
if ($refineSaved) {
    $inputHash=Get-ScopeField $scope 'input_copy_sha256'
    if ($inputHash -isnot [string] -or $inputHash -cnotmatch '^[A-F0-9]{64}$') { throw 'BASEBOARD_SAVED_INPUT_HASH_INVALID' }
}
$paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$resolvedPaths = @{}
$pathFields = @('input_copy_path','output_path','audit_copy_path')
if ($completeCopy) { $pathFields += 'working_copy_path' }
foreach ($f in $pathFields) {
    $p = [IO.Path]::GetFullPath((Join-Path $root ([string](Get-ScopeField $scope $f))))
    if (-not $p.StartsWith((Join-Path $root 'runs') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($p) -ine '.dwg' -or -not $paths.Add($p) -or [string]::Equals($p,$sourcePath,[StringComparison]::OrdinalIgnoreCase)) { throw "BASEBOARD_COPY_PATH_UNSAFE:$f" }
    $resolvedPaths[$f] = $p
    if (Test-Path -LiteralPath $p) {
        if ($stage -ceq 'INDEPENDENT_REOPEN_AUDIT' -and $f -ceq 'output_path') {
            if ([string](Get-ScopeField $scope 'output_sha256') -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne [string]$scope.output_sha256) { throw 'BASEBOARD_AUDIT_OUTPUT_HASH_MISMATCH' }
            continue
        }
        if ($f -ne 'input_copy_path') { throw 'BASEBOARD_OUTPUT_ALREADY_EXISTS' }
        # The exact input may be open in CAD; preserve its path/SHA gate using the verified shared-read hasher.
        if ((& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/get_shared_file_sha256_v1.ps1') -Path $p) -cne $inputHash) { throw 'BASEBOARD_INPUT_COPY_HASH_MISMATCH' }
    }
}
if ($completeCopy) {
    $newRun=[string](Get-ScopeField $Draft 'run_id')
    if ($newRun -cnotmatch '^[A-Za-z0-9_-]+$') { throw 'BASEBOARD_COMPLETE_COPY_RUN_INVALID' }
    $newDir=[IO.Path]::GetFullPath((Join-Path $root ('runs/'+$newRun)))+[IO.Path]::DirectorySeparatorChar
    foreach ($f in @('working_copy_path','output_path','audit_copy_path')) {
        if (-not $resolvedPaths[$f].StartsWith($newDir,[StringComparison]::OrdinalIgnoreCase)) { throw "BASEBOARD_COMPLETE_COPY_NOT_IN_NEW_RUN:$f" }
    }
}
if ($refineSaved) {
    if (-not (Test-Path -LiteralPath $resolvedPaths.input_copy_path -PathType Leaf)) { throw 'BASEBOARD_SAVED_INPUT_MISSING' }
    $prior=Get-ScopeField $scope 'prior_saved_baseboard'
    $priorRun=[string](Get-ScopeField $prior 'run_id')
    if ($priorRun -cnotmatch '^[A-Za-z0-9_-]+$' -or $priorRun -ceq $newRun) { throw 'BASEBOARD_SAVED_PRIOR_RUN_INVALID' }
    $priorDir=[IO.Path]::GetFullPath((Join-Path $root ('runs/'+$priorRun)))
    $evidence=@{}
    foreach ($prefix in @($copyContract.prior_evidence)) {
        $bound=Resolve-ProjectEvidence (Get-ScopeField $prior ($prefix+'_path')) (Get-ScopeField $prior ($prefix+'_sha256'))
        if (-not $bound.StartsWith($priorDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_SAVED_PRIOR_EVIDENCE_OUTSIDE_RUN' }
        if ($prefix -cin @('handoff','return','delivery') -and -not [string]::Equals($bound,(Join-Path $priorDir ('execution_'+$prefix+'.json')),[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_SAVED_PRIOR_AUTHORITY_PATH_INVALID' }
        $evidence[$prefix]=$bound
    }
    $priorH=Get-Content -LiteralPath $evidence.handoff -Raw -Encoding UTF8|ConvertFrom-Json
    $priorR=Get-Content -LiteralPath $evidence.return -Raw -Encoding UTF8|ConvertFrom-Json
    $priorD=Get-Content -LiteralPath $evidence.delivery -Raw -Encoding UTF8|ConvertFrom-Json
    $saved=Get-Content -LiteralPath $evidence.saved_binding -Raw -Encoding UTF8|ConvertFrom-Json
    foreach ($record in @($priorH,$priorR,$priorD)) {
        if ([string](Get-ScopeField $record 'run_id') -cne $priorRun -or [string](Get-ScopeField $record 'handoff_id') -cne [string]$priorH.handoff_id) { throw 'BASEBOARD_SAVED_PRIOR_IDENTITY_MISMATCH' }
    }
    if ([string]$priorD.status -cne 'DELIVERED' -or [string]$priorR.status -cne 'REPORTED' -or [string]$priorD.immutable_return_sha256 -cne [string]$prior.return_sha256 -or -not [string]::Equals([IO.Path]::GetFullPath((Join-Path $root $priorD.immutable_return_path)),$evidence.return,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_SAVED_PRIOR_NOT_DELIVERED' }
    if ([string]$priorH.command_routing.route_id -cne 'sheet_layout_baseboard_extract' -or [string]$priorH.issuer.thread_id -cne [string]$Draft.issuer.thread_id -or [string]$priorR.reader.thread_id -cne [string]$Draft.command_routing.detail_return_thread_id -or [string]$priorD.callback_target_thread_id -cne [string]$priorR.reader.thread_id) { throw 'BASEBOARD_SAVED_PRIOR_ROUTE_MISMATCH' }
    if ([string]$priorH.baseboard_extract_scope.source_sha256 -cne $sourceHash -or -not [string]::Equals([IO.Path]::GetFullPath([string]$priorH.baseboard_extract_scope.source_path),$sourcePath,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_SAVED_PRIOR_SOURCE_MISMATCH' }
    $savedPath=[IO.Path]::GetFullPath([string](Get-ScopeField $saved 'output_path'))
    $savedHash=[string](Get-ScopeField $saved 'output_sha256')
    $savedCount=Get-ScopeField $saved 'savecopy_count'
    if (-not $savedPath.StartsWith($priorDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals($savedPath,$resolvedPaths.input_copy_path,[StringComparison]::OrdinalIgnoreCase) -or $savedHash -cne $inputHash -or ($savedCount -isnot [int] -and $savedCount -isnot [long]) -or $savedCount -ne 1) { throw 'BASEBOARD_SAVED_BINDING_MISMATCH' }
    $report=Get-ScopeField $priorR 'controller_report'
    if ($null -ne $report.PSObject.Properties['worker_report']) { $report=$report.worker_report }
    if ([string](Get-ScopeField $report 'output_sha256') -cne $inputHash) { throw 'BASEBOARD_SAVED_OUTPUT_NOT_IN_TERMINAL_EVIDENCE' }
}
if ($stage -ceq 'INDEPENDENT_REOPEN_AUDIT') {
    if (-not(Test-Path -LiteralPath $resolvedPaths.output_path -PathType Leaf)) { throw 'BASEBOARD_AUDIT_OUTPUT_MISSING' }
    $newRun=[string](Get-ScopeField $Draft 'run_id')
    if ($newRun -cnotmatch '^[A-Za-z0-9_-]+$' -or -not $resolvedPaths.audit_copy_path.StartsWith((Join-Path $root ('runs/'+$newRun)) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_COPY_NOT_IN_NEW_RUN' }
    $prior=Get-ScopeField $scope 'prior_export'
    $priorRun=[string](Get-ScopeField $prior 'run_id')
    if ($priorRun -cnotmatch '^[A-Za-z0-9_-]+$' -or $priorRun -ceq $newRun) { throw 'BASEBOARD_AUDIT_PRIOR_RUN_INVALID' }
    $priorDir=[IO.Path]::GetFullPath((Join-Path $root ('runs/'+$priorRun)))
    $evidence=@{}
    foreach ($prefix in @($auditContract.prior_evidence)) {
        $bound=Resolve-ProjectEvidence (Get-ScopeField $prior ($prefix+'_path')) (Get-ScopeField $prior ($prefix+'_sha256'))
        if (-not $bound.StartsWith($priorDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_PRIOR_EVIDENCE_OUTSIDE_RUN' }
        if ($prefix -cin @('handoff','return','delivery') -and -not [string]::Equals($bound,(Join-Path $priorDir ('execution_'+$prefix+'.json')),[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_PRIOR_AUTHORITY_PATH_INVALID' }
        $evidence[$prefix]=$bound
    }
    $priorH=Get-Content -LiteralPath $evidence.handoff -Raw -Encoding UTF8|ConvertFrom-Json
    $priorR=Get-Content -LiteralPath $evidence.return -Raw -Encoding UTF8|ConvertFrom-Json
    $priorD=Get-Content -LiteralPath $evidence.delivery -Raw -Encoding UTF8|ConvertFrom-Json
    if ([string]$priorH.run_id -cne $priorRun -or [string]$priorR.run_id -cne $priorRun -or [string]$priorD.run_id -cne $priorRun -or [string]$priorH.handoff_id -cne [string]$priorR.handoff_id -or [string]$priorD.handoff_id -cne [string]$priorR.handoff_id) { throw 'BASEBOARD_AUDIT_PRIOR_IDENTITY_MISMATCH' }
    if ([string]$priorD.status -cne 'DELIVERED' -or [string]$priorD.immutable_return_sha256 -cne [string]$prior.return_sha256 -or -not [string]::Equals([IO.Path]::GetFullPath((Join-Path $root $priorD.immutable_return_path)),$evidence.return,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_PRIOR_NOT_DELIVERED' }
    if ([string]$priorR.status -cne 'REPORTED') { throw 'BASEBOARD_AUDIT_PRIOR_RETURN_UNSETTLED' }
    if ([string]$priorH.command_routing.route_id -cne 'sheet_layout_baseboard_extract' -or [string]$priorH.issuer.thread_id -cne [string]$Draft.issuer.thread_id -or [string]$priorR.reader.thread_id -cne [string]$Draft.command_routing.detail_return_thread_id -or [string]$priorD.callback_target_thread_id -cne [string]$priorR.reader.thread_id) { throw 'BASEBOARD_AUDIT_PRIOR_ROUTE_MISMATCH' }
    $priorScope=$priorH.baseboard_extract_scope
    foreach ($f in @('source_sha256','inventory_sha256','manifest_sha256','annotation_policy')) { if ([string](Get-ScopeField $priorScope $f) -cne [string](Get-ScopeField $scope $f)) { throw "BASEBOARD_AUDIT_PRIOR_SCOPE_MISMATCH:$f" } }
    foreach ($f in @('output_path','input_copy_path')) { if (-not [string]::Equals([IO.Path]::GetFullPath((Join-Path $root ([string](Get-ScopeField $priorScope $f)))),$resolvedPaths[$f],[StringComparison]::OrdinalIgnoreCase)) { throw "BASEBOARD_AUDIT_PRIOR_PATH_MISMATCH:$f" } }
    $worker=Get-ScopeField (Get-ScopeField $priorR 'controller_report') 'worker_report'
    if ([string](Get-ScopeField $worker 'status') -cnotmatch '^PASS_' -or [int](Get-ScopeField $worker 'export_count') -ne 1 -or [int](Get-ScopeField $worker 'delete_count') -ne 0 -or [string](Get-ScopeField $worker 'output_sha256') -cne [string]$scope.output_sha256) { throw 'BASEBOARD_AUDIT_PRIOR_EXPORT_NOT_PROVEN' }
    $exportEncoding=[string](Get-ScopeField $prior 'export_report_encoding')
    if ($exportEncoding -cnotin @('utf-8','cp936')) { throw 'BASEBOARD_AUDIT_EXPORT_ENCODING_INVALID' }
    $encoding=if($exportEncoding -ceq 'cp936'){[Text.Encoding]::GetEncoding(936)}else{[Text.UTF8Encoding]::new($false,$true)}
    $exportRows=@([IO.File]::ReadAllText($evidence.export_report,$encoding)|ConvertFrom-Csv -Delimiter ([char]9))
    if ($exportRows.Count -ne 1 -or [string]$exportRows[0].STATUS -cne 'PASS' -or [string]$exportRows[0].OUTPUT_EXISTS -cne 'YES' -or -not [string]::IsNullOrWhiteSpace([string]$exportRows[0].MISSING_HANDLES) -or -not [string]::Equals([IO.Path]::GetFullPath([string]$exportRows[0].OUTPUT_PATH),$resolvedPaths.output_path,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([IO.Path]::GetFullPath([string]$exportRows[0].SOURCE_DWG),$resolvedPaths.input_copy_path,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_NATIVE_EXPORT_REPORT_INVALID' }
    $sourceAudit=Get-Content -LiteralPath $evidence.source_audit -Raw -Encoding UTF8|ConvertFrom-Json
    if ([string]$sourceAudit.status -cnotmatch '^PASS_' -or $sourceAudit.complete_current_source_before_after_exact -isnot [bool] -or -not $sourceAudit.complete_current_source_before_after_exact -or $sourceAudit.all_engineering_entget_xdata_exact_since_classification -isnot [bool] -or -not $sourceAudit.all_engineering_entget_xdata_exact_since_classification -or [int]$sourceAudit.source_dbmod -ne 0 -or [string]$sourceAudit.output_sha256 -cne [string]$scope.output_sha256 -or -not [string]::Equals([IO.Path]::GetFullPath([string]$sourceAudit.output_path),$resolvedPaths.output_path,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_AUDIT_SOURCE_PROTECTION_NOT_PROVEN' }
}
$inventoryPath = Resolve-ProjectEvidence (Get-ScopeField $scope 'inventory_path') (Get-ScopeField $scope 'inventory_sha256')
$manifestPath = Resolve-ProjectEvidence (Get-ScopeField $scope 'manifest_path') (Get-ScopeField $scope 'manifest_sha256')
$inv = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($record in @($inv,$manifest)) {
    if ([string](Get-ScopeField $record 'source_sha256') -cne $sourceHash -or -not [string]::Equals([IO.Path]::GetFullPath([string](Get-ScopeField $record 'source_path')),$sourcePath,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_RECORD_SOURCE_MISMATCH' }
    if ($refineSaved -and ([string](Get-ScopeField $record 'baseline_sha256') -cne $inputHash -or -not [string]::Equals([IO.Path]::GetFullPath([string](Get-ScopeField $record 'baseline_path')),$resolvedPaths.input_copy_path,[StringComparison]::OrdinalIgnoreCase))) { throw 'BASEBOARD_RECORD_SAVED_BASELINE_MISMATCH' }
}
Resolve-ProjectEvidence (Get-ScopeField $inv 'native_evidence_path') (Get-ScopeField $inv 'native_evidence_sha256') | Out-Null
Resolve-ProjectEvidence (Get-ScopeField $manifest 'reference_evidence_path') (Get-ScopeField $manifest 'reference_evidence_sha256') | Out-Null
Resolve-ProjectEvidence (Get-ScopeField $manifest 'dependency_manifest_path') (Get-ScopeField $manifest 'dependency_manifest_sha256') | Out-Null
if ([string](Get-ScopeField $manifest 'inventory_sha256') -cne [string]$scope.inventory_sha256 -or [string](Get-ScopeField $manifest 'annotation_policy') -cne $policy) { throw 'BASEBOARD_MANIFEST_BINDING_MISMATCH' }
$model = @{}
$modelRoles=@('engineering_geometry','engineering_annotation','necessary_engineering_text','unknown_or_mixed','old_model_layout_packaging')
$removableRoles=@($Contract.removable_roles)
if ($refineSaved) { $modelRoles=@($copyContract.model_roles); $removableRoles=@($copyContract.removable_roles) }
foreach ($o in @(Get-ScopeField $inv 'model_objects')) {
    $h = [string](Get-ScopeField $o 'handle')
    if ($h -notmatch '^[A-Fa-f0-9]+$' -or $model.ContainsKey($h) -or [string](Get-ScopeField $o 'owner') -cne 'Model') { throw 'BASEBOARD_MODEL_IDENTITY_INVALID' }
    if ([string](Get-ScopeField $o 'semantic_role') -cnotin $modelRoles) { throw 'BASEBOARD_MODEL_ROLE_INVALID' }
    if ($refineSaved) {
        $nativeType=[string](Get-ScopeField $o 'native_type')
        foreach ($p in @($copyContract.protected_native_roles.PSObject.Properties)+@($copyContract.training_native_roles.PSObject.Properties)) {
            if ($nativeType -ceq $p.Name -and [string]$o.semantic_role -cne [string]$p.Value) { throw 'BASEBOARD_NATIVE_ROLE_SEMANTIC_CONFLICT' }
        }
    }
    $model[$h] = $o
}
if ($model.Count -eq 0) { throw 'BASEBOARD_MODEL_EMPTY' }
$covered = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$export = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$remove = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($partition in @('keep','remove','review')) {
    foreach ($row in @(Get-ScopeField $manifest $partition)) {
        $h = [string](Get-ScopeField $row 'handle')
        if (-not $model.ContainsKey($h) -or -not $covered.Add($h)) { throw 'BASEBOARD_PARTITION_OVERLAP_OR_FOREIGN' }
        $role = [string]$model[$h].semantic_role
        if ($partition -ceq 'remove') {
            if ($role -cnotin $removableRoles -or ($role -ceq 'engineering_annotation' -and $policy -cne 'remove_identified')) { throw 'BASEBOARD_REMOVAL_NOT_PROVEN_ROLE' }
            if ($refineSaved) {
                $semantic=Get-ScopeField $row 'removal_semantics'
                foreach ($f in @('not_retained_engineering','not_vertical_elevation')) { $v=Get-ScopeField $semantic $f; if ($v -isnot [bool] -or -not $v) { throw "BASEBOARD_TRAINING_REMOVAL_PROTECTION_MISSING:$f" } }
                if ([string](Get-ScopeField $semantic 'basis') -cnotin @($copyContract.removal_bases)) { throw 'BASEBOARD_TRAINING_REMOVAL_BASIS_INVALID' }
            }
            if ([string](Get-ScopeField $row 'reason') -notmatch '\S') { throw 'BASEBOARD_REMOVAL_REASON_MISSING' }
            Resolve-ProjectEvidence (Get-ScopeField $row 'proof_path') (Get-ScopeField $row 'proof_sha256') | Out-Null
            $remove.Add($h) | Out-Null
        } else {
            if ($refineSaved -and $role -cin $removableRoles) { throw 'BASEBOARD_KNOWN_TRAINING_EXPRESSION_LEFT_IN_KEEP_OR_REVIEW' }
            $export.Add($h) | Out-Null
        }
    }
}
if ($covered.Count -ne $model.Count -or $export.Count -eq 0) { throw 'BASEBOARD_PARTITION_INCOMPLETE' }
$selected = @(Get-ScopeField $manifest 'export_handles')
if ($selected.Count -ne $export.Count -or -not $export.SetEquals([string[]]$selected)) { throw 'BASEBOARD_EXPORT_SET_MISMATCH' }
if ($completeCopy) {
    $eraseHandles=@(Get-ScopeField $scope 'erase_handles')
    if ($remove.Count -eq 0 -or $eraseHandles.Count -ne $remove.Count -or -not $remove.SetEquals([string[]]$eraseHandles)) { throw 'BASEBOARD_COMPLETE_COPY_ERASE_SET_MISMATCH' }
    $deleteCount=Get-ScopeField $scope 'delete_count'
    if (($deleteCount -isnot [int] -and $deleteCount -isnot [long]) -or $deleteCount -ne $remove.Count) { throw 'BASEBOARD_COMPLETE_COPY_DELETE_COUNT_MISMATCH' }
}
if ($stage -ceq 'INDEPENDENT_REOPEN_AUDIT' -and ([int]$exportRows[0].REQUESTED -ne $export.Count -or [int]$exportRows[0].RESOLVED -ne $export.Count -or [int]$sourceAudit.exported_source_roots -ne $export.Count)) { throw 'BASEBOARD_AUDIT_EXPORTED_ROOT_SET_COUNT_MISMATCH' }
$paper = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$paperObjects = @{}
foreach ($o in @(Get-ScopeField $inv 'paper_objects')) {
    $h = [string](Get-ScopeField $o 'handle')
    $owner = [string](Get-ScopeField $o 'owner')
    if ($h -notmatch '^[A-Fa-f0-9]+$' -or [string]::IsNullOrWhiteSpace($owner) -or $owner -ieq 'Model' -or $model.ContainsKey($h) -or -not $paper.Add($h)) { throw 'BASEBOARD_PAPER_IDENTITY_INVALID' }
    $paperObjects[$h]=$o
}
$refs = @(Get-ScopeField $manifest 'reference_only_handles')
if ($refs.Count -ne $paper.Count -or -not $paper.SetEquals([string[]]$refs)) { throw 'BASEBOARD_PAPER_REFERENCE_SET_MISMATCH' }
if ($stage -ceq 'COMPLETE_COPY_CLEAR_EXISTING_LAYOUTS') {
    $layoutPath=Resolve-ProjectEvidence (Get-ScopeField $scope 'layout_manifest_path') (Get-ScopeField $scope 'layout_manifest_sha256')
    $layoutManifest=Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8|ConvertFrom-Json
    $layoutNativePath=Resolve-ProjectEvidence (Get-ScopeField $layoutManifest 'native_evidence_path') (Get-ScopeField $layoutManifest 'native_evidence_sha256')
    $layoutNative=Get-Content -LiteralPath $layoutNativePath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach ($record in @($layoutManifest,$layoutNative)) {
        if ([string](Get-ScopeField $record 'source_sha256') -cne $sourceHash -or -not [string]::Equals([IO.Path]::GetFullPath([string](Get-ScopeField $record 'source_path')),$sourcePath,[StringComparison]::OrdinalIgnoreCase)) { throw 'BASEBOARD_LAYOUT_SOURCE_MISMATCH' }
    }
    if ([string](Get-ScopeField $layoutManifest 'inventory_sha256') -cne [string]$scope.inventory_sha256) { throw 'BASEBOARD_LAYOUT_INVENTORY_BINDING_MISMATCH' }
    $layouts=@(Get-ScopeField $layoutManifest 'old_layouts')
    $boundLayouts=@(Get-ScopeField $scope 'old_layouts')
    $nativeLayouts=@(Get-ScopeField $layoutNative 'layouts')
    if ($layouts.Count -eq 0 -or $boundLayouts.Count -ne $layouts.Count -or $nativeLayouts.Count -ne $layouts.Count) { throw 'BASEBOARD_LAYOUT_SET_COUNT_MISMATCH' }
    $layoutNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $layoutIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $layoutBtrs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $layoutRoots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($layout in $layouts) {
        $name=Get-ScopeField $layout 'name'; $id=Get-ScopeField $layout 'layout_handle'; $btr=Get-ScopeField $layout 'btr_handle'
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or $name -ieq 'Model' -or $id -isnot [string] -or $id -cnotmatch '^[A-Fa-f0-9]+$' -or $btr -isnot [string] -or $btr -cnotmatch '^[A-Fa-f0-9]+$' -or $id -ieq $btr -or -not $layoutNames.Add($name) -or -not $layoutIds.Add($id) -or -not $layoutBtrs.Add($btr)) { throw 'BASEBOARD_LAYOUT_IDENTITY_INVALID' }
        $roots=@(Get-ScopeField $layout 'root_handles')
        $rootSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($h in $roots) {
            if ($h -isnot [string] -or $h -cnotmatch '^[A-Fa-f0-9]+$' -or -not $paper.Contains($h) -or -not $rootSet.Add($h) -or -not $layoutRoots.Add($h)) { throw 'BASEBOARD_LAYOUT_ROOT_INVALID' }
            if ([string](Get-ScopeField $paperObjects[$h] 'space_handle') -ine $btr) { throw 'BASEBOARD_LAYOUT_ROOT_OWNER_MISMATCH' }
        }
        foreach ($dictionary in @(@{rows=$boundLayouts},@{rows=$nativeLayouts})) {
            $match=@($dictionary.rows|Where-Object { [string](Get-ScopeField $_ 'name') -ceq $name })
            if ($match.Count -ne 1 -or [string](Get-ScopeField $match[0] 'layout_handle') -cne $id -or [string](Get-ScopeField $match[0] 'btr_handle') -cne $btr) { throw 'BASEBOARD_LAYOUT_NATIVE_OR_SCOPE_IDENTITY_MISMATCH' }
            $otherRoots=@(Get-ScopeField $match[0] 'root_handles')
            if ($otherRoots.Count -ne $roots.Count -or -not $rootSet.SetEquals([string[]]$otherRoots)) { throw 'BASEBOARD_LAYOUT_NATIVE_OR_SCOPE_ROOT_MISMATCH' }
        }
    }
    if (-not $layoutRoots.SetEquals($paper)) { throw 'BASEBOARD_LAYOUT_PAPER_COVERAGE_INCOMPLETE' }
    foreach ($h in $layoutIds) { if ($model.ContainsKey($h) -or $paper.Contains($h) -or $layoutBtrs.Contains($h)) { throw 'BASEBOARD_LAYOUT_RECORD_ENTITY_COLLISION' } }
    foreach ($h in $layoutBtrs) { if ($model.ContainsKey($h) -or $paper.Contains($h)) { throw 'BASEBOARD_LAYOUT_RECORD_ENTITY_COLLISION' } }
    $replacement=Get-ScopeField $scope 'replacement_layout_name'
    if ($replacement -isnot [string] -or [string]::IsNullOrWhiteSpace($replacement) -or $replacement -ieq 'Model' -or $replacement -match '[<>/\\":;?*|=`\x00-\x1F]' -or $layoutNames.Contains($replacement)) { throw 'BASEBOARD_REPLACEMENT_LAYOUT_NAME_INVALID' }
    $deleteLayouts=Get-ScopeField $scope 'layout_delete_count'
    if (($deleteLayouts -isnot [int] -and $deleteLayouts -isnot [long]) -or $deleteLayouts -ne $layouts.Count) { throw 'BASEBOARD_LAYOUT_DELETE_COUNT_MISMATCH' }
}
[pscustomobject]@{ status='PASS'; stage=$stage; model_objects=$model.Count; exported_objects=$export.Count; paper_reference_objects=$paper.Count; annotation_policy=$policy; native_output_verified=$false }
