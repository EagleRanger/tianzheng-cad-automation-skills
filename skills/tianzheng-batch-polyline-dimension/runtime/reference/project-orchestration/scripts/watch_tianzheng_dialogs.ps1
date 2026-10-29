param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [string]$WhitelistPath = '',
    [Parameter(Mandatory = $true)][string]$LogPath,
    [int]$TimeoutSeconds = 600,
    [int]$PollMilliseconds = 150,
    [string]$RequiredMainTitle = '',
    [string]$ExpectedTrustedScriptPath = '',
    [string]$ExpectedTrustedScriptSha256 = '',
    [string[]]$ExpectedTrustedScriptPaths = @(),
    [string[]]$ExpectedTrustedScriptSha256s = @(),
    [string]$TrustedScriptRoot = 'C:\tmp\tianzheng_whitelist',
    [int]$MaxTrustedScriptAutoDismissCount = 1,
    [int]$QuietSeconds = 0,
    # Some T20/AutoCAD DirectUI dialogs (notably the graphic-repair notice)
    # expose a blank #32770 shell before their title and controls are ready.
    # Three seconds produced a false UNKNOWN_STOP during a real DWG open.
    [int]$TransientBlankDialogGraceMilliseconds = 15000,
    [string]$AllowedProbeRuleId = '',
    [switch]$SinglePass
)
$ErrorActionPreference='Stop'
function Initialize-TzDialogRuleDefaults([object]$Rule){
    # Missing optional restrictions keep the original rule semantics under StrictMode.
    # Explicit trusted-script requirements must never be replaced by a default.
    $defaults=@{requires_trusted_script_context=$false;required_trusted_script_basenames_exact=@();body_exact='';required_text_contains=@()}
    foreach($name in $defaults.Keys){
        if($null-eq$Rule.PSObject.Properties[$name]){$Rule|Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name]}
    }
    return $Rule
}
if([string]::IsNullOrWhiteSpace($WhitelistPath)){
    $WhitelistPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'config\tianzheng_dialog_whitelist.json'
}
$rules=@((Get-Content -LiteralPath $WhitelistPath -Raw -Encoding UTF8|ConvertFrom-Json).rules|Where-Object{
    @('observed_and_user_approved','observed_and_workflow_authorized','observed_safe_failure')-contains$_.status-or
    (-not[string]::IsNullOrWhiteSpace($AllowedProbeRuleId)-and$_.id-eq$AllowedProbeRuleId-and$_.status-eq'isolated_probe_only')
}|ForEach-Object{Initialize-TzDialogRuleDefaults $_})
Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class TzDialogWatch {
 public delegate bool CB(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]public static extern bool EnumWindows(CB c,IntPtr l);
 [DllImport("user32.dll")]public static extern bool EnumChildWindows(IntPtr p,CB c,IntPtr l);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr h);
 public static string Text(IntPtr h){var s=new StringBuilder(4096);GetWindowText(h,s,s.Capacity);return s.ToString();}
 public static string Class(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,s.Capacity);return s.ToString();}
}
'@
function Write-DialogLog([object]$item){
    $dir=Split-Path -Parent $LogPath;if($dir-and-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir|Out-Null}
    ($item|ConvertTo-Json -Compress -Depth 5)|Add-Content -LiteralPath $LogPath -Encoding UTF8
}
function Get-TrustedScriptContext{
    $paths=@($ExpectedTrustedScriptPaths);$hashes=@($ExpectedTrustedScriptSha256s)
    if($paths.Count-eq0-and-not[string]::IsNullOrWhiteSpace($ExpectedTrustedScriptPath)){$paths=@($ExpectedTrustedScriptPath);$hashes=@($ExpectedTrustedScriptSha256)}
    if($paths.Count-eq0-or$paths.Count-ne$hashes.Count){return $null}
    $resolvedRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TrustedScriptRoot).Path).TrimEnd('\')+'\'
    $validated=New-Object System.Collections.Generic.List[object]
    for($i=0;$i-lt$paths.Count;$i++){
        if([string]::IsNullOrWhiteSpace([string]$paths[$i])-or[string]::IsNullOrWhiteSpace([string]$hashes[$i])){return $null}
        if(-not(Test-Path -LiteralPath $paths[$i] -PathType Leaf)){return $null}
        $resolvedScript=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $paths[$i]).Path)
        if(-not$resolvedScript.StartsWith($resolvedRoot,[StringComparison]::OrdinalIgnoreCase)){return $null}
        if([IO.Path]::GetExtension($resolvedScript)-cne'.lsp'){return $null}
        $actualHash=(Get-FileHash -LiteralPath $resolvedScript -Algorithm SHA256).Hash
        if($actualHash-cne([string]$hashes[$i]).ToUpperInvariant()){return $null}
        $validated.Add([pscustomobject]@{path=$resolvedScript;sha256=$actualHash})
    }
    return [pscustomobject]@{files=$validated.ToArray();root=$resolvedRoot.TrimEnd('\')}
}
function Get-OwnedVisibleDialogs{
    $items=New-Object System.Collections.Generic.List[object]
    $cb=[TzDialogWatch+CB]{param($h,$l)[uint32]$pid2=0;[void][TzDialogWatch]::GetWindowThreadProcessId($h,[ref]$pid2);if($pid2-eq$ProcessId-and[TzDialogWatch]::IsWindowVisible($h)-and[TzDialogWatch]::Class($h)-eq'#32770'){$items.Add([pscustomobject]@{handle=$h.ToInt64();class=[TzDialogWatch]::Class($h);title=[TzDialogWatch]::Text($h)})};return $true}
    [void][TzDialogWatch]::EnumWindows($cb,[IntPtr]::Zero);return $items.ToArray()
}
function Get-DialogControls([long]$DialogHandle){
    $items=New-Object System.Collections.Generic.List[object]
    $cb=[TzDialogWatch+CB]{param($h,$l)
        if([TzDialogWatch]::IsWindowVisible($h)){
            $text=[TzDialogWatch]::Text($h)
            $class=[TzDialogWatch]::Class($h)
            if(-not[string]::IsNullOrWhiteSpace($text)-or$class-eq'Button'){
                $items.Add([pscustomobject]@{handle=$h.ToInt64();class=$class;text=$text})
            }
        }
        return $true
    }
    [void][TzDialogWatch]::EnumChildWindows([IntPtr]$DialogHandle,$cb,[IntPtr]::Zero)
    return $items.ToArray()
}
function Find-ExactButton([long]$DialogHandle,[string]$Text){
    $script:found=[IntPtr]::Zero
    $cb=[TzDialogWatch+CB]{param($h,$l)if([TzDialogWatch]::Class($h)-eq'Button'-and[TzDialogWatch]::Text($h)-eq$Text){$script:found=$h;return $false};return $true}
    [void][TzDialogWatch]::EnumChildWindows([IntPtr]$DialogHandle,$cb,[IntPtr]::Zero);return $script:found
}
function Test-TrustedScriptRequirements([object]$Rule,[object]$TrustedScriptContext){
    $requiredBasenames=@($Rule.required_trusted_script_basenames_exact|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)})
    if($requiredBasenames.Count-eq0){return $true}
    if($null-eq$TrustedScriptContext){return $false}
    $actualBasenames=@($TrustedScriptContext.files|ForEach-Object{[IO.Path]::GetFileName([string]$_.path)})
    foreach($required in $requiredBasenames){
        if($actualBasenames-notcontains[string]$required){return $false}
    }
    return $true
}
function Test-OwnedMainTitle([string]$RequiredTitle){
    $script:titleMatched=$false
    $cb=[TzDialogWatch+CB]{param($h,$l)
        [uint32]$pid2=0;[void][TzDialogWatch]::GetWindowThreadProcessId($h,[ref]$pid2)
        if($pid2-eq$ProcessId-and[TzDialogWatch]::IsWindowVisible($h)-and[TzDialogWatch]::Class($h)-ne'#32770'){
            $candidateTitle=[TzDialogWatch]::Text($h)
            if([string]::IsNullOrWhiteSpace($RequiredTitle)-or$candidateTitle.IndexOf($RequiredTitle,[StringComparison]::OrdinalIgnoreCase)-ge0){$script:titleMatched=$true;return $false}
        }
        return $true
    }
    [void][TzDialogWatch]::EnumWindows($cb,[IntPtr]::Zero);return $script:titleMatched
}
$seen=@{};$blankFirstSeen=@{};$incompleteFirstSeen=@{};$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$quietSince=$null;$trustedScriptDismissedCount=0
while((Get-Date)-lt$deadline-and(Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)){
    $dialogs=@(Get-OwnedVisibleDialogs)
    if($dialogs.Count-gt0){$quietSince=$null}
    foreach($dialog in $dialogs){
        $controls=@(Get-DialogControls -DialogHandle $dialog.handle)
        # AutoCAD can expose a modal #32770 before its title and child controls
        # are populated.  Treating that construction phase as an unknown dialog
        # caused an immediate stop before the approved XREF action became
        # identifiable.  Do not add blank dialogs to $seen: their controls may
        # become actionable on the next poll.
        if([string]::IsNullOrWhiteSpace([string]$dialog.title)){
            $blankXrefRule=@($rules|Where-Object{$_.id-eq'xref_missing_ignore_unresolved'}|Select-Object -First 1)
            $ignoreXrefButton=if($blankXrefRule.Count-eq1){Find-ExactButton -DialogHandle $dialog.handle -Text ([string]$blankXrefRule[0].required_button_text)}else{[IntPtr]::Zero}
            if($ignoreXrefButton-ne[IntPtr]::Zero-and$blankXrefRule.Count-eq1){
                [void][TzDialogWatch]::SendMessage($ignoreXrefButton,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
                Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='AUTO_DISMISSED';process_id=$ProcessId;rule_id=$blankXrefRule[0].id;dialog_title='';button_text=$blankXrefRule[0].required_button_text;matched_by='blank_title_exact_button'})
                continue
            }
            $blankKey=[string]$dialog.handle
            if(-not$blankFirstSeen.ContainsKey($blankKey)){
                $blankFirstSeen[$blankKey]=Get-Date
                Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='TRANSIENT_BLANK_DIALOG_DEFERRED';process_id=$ProcessId;dialog_handle=$dialog.handle;grace_milliseconds=$TransientBlankDialogGraceMilliseconds})
            }
            if(((Get-Date)-$blankFirstSeen[$blankKey]).TotalMilliseconds-lt$TransientBlankDialogGraceMilliseconds){continue}
        }
        $trustedScriptContext=Get-TrustedScriptContext
        # A known modal may publish its title one polling frame before its
        # child controls.  Defer only exact known title/class candidates and
        # only inside the same bounded construction grace; unknown titles
        # still fail immediately.
        $knownIncompleteCandidates=@($rules|Where-Object{
            $_.window_class-eq$dialog.class-and$_.title_exact-eq$dialog.title-and
            (-not[bool]$_.requires_trusted_script_context-or$null-ne$trustedScriptContext)-and
            (Test-TrustedScriptRequirements -Rule $_ -TrustedScriptContext $trustedScriptContext)
        })
        if($controls.Count-eq0-and$knownIncompleteCandidates.Count-gt0){
            $incompleteKey=[string]$dialog.handle+'|'+[string]$dialog.title
            if(-not$incompleteFirstSeen.ContainsKey($incompleteKey)){
                $incompleteFirstSeen[$incompleteKey]=Get-Date
                Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='TRANSIENT_KNOWN_DIALOG_CONTROLS_DEFERRED';process_id=$ProcessId;dialog=$dialog;grace_milliseconds=$TransientBlankDialogGraceMilliseconds})
            }
            if(((Get-Date)-$incompleteFirstSeen[$incompleteKey]).TotalMilliseconds-lt$TransientBlankDialogGraceMilliseconds){continue}
        }
        $signature="$($dialog.handle)|$($dialog.title)";if($seen.ContainsKey($signature)){continue}
        $seen[$signature]=$true
        $rule=@($rules|Where-Object{
            if($_.window_class-ne$dialog.class-or$_.title_exact-ne$dialog.title){return $false}
            if([bool]$_.requires_trusted_script_context-and$null-eq$trustedScriptContext){return $false}
            if(-not(Test-TrustedScriptRequirements -Rule $_ -TrustedScriptContext $trustedScriptContext)){return $false}
            $body=[string]$_.body_exact
            if(-not[string]::IsNullOrWhiteSpace($body)-and@($controls|Where-Object{$_.class-eq'Static'-and$_.text-eq$body}).Count-ne1){return $false}
            $allControlText=(@($controls|ForEach-Object{[string]$_.text})-join "`n")
            foreach($requiredText in @($_.required_text_contains)){
                if([string]::IsNullOrWhiteSpace([string]$requiredText)){continue}
                if($allControlText.IndexOf([string]$requiredText,[StringComparison]::OrdinalIgnoreCase)-lt0){return $false}
            }
            return $true
        }|Select-Object -First 1)
        if($rule.Count-ne 1){
            Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='UNKNOWN_STOP';process_id=$ProcessId;dialog=$dialog;controls=$controls})
            throw "UNKNOWN_TIANZHENG_DIALOG=$($dialog.title)"
        }
        $button=Find-ExactButton -DialogHandle $dialog.handle -Text $rule[0].required_button_text
        if($button-eq[IntPtr]::Zero){Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='BUTTON_NOT_FOUND_STOP';process_id=$ProcessId;rule_id=$rule[0].id;dialog=$dialog});throw "WHITELIST_BUTTON_NOT_FOUND=$($rule[0].id)"}
        if([string]$rule[0].action-eq'post_standard_close_and_verify'){
            # AutoCAD's graphic-repair notification exposes a Button handle,
            # but BM_CLICK is ignored by its DirectUI host.  A standard
            # WM_CLOSE follows the same user-visible Close/X path and avoids
            # changing the persistent "do not show again" checkbox.
            $accepted=[TzDialogWatch]::PostMessage([IntPtr][long]$dialog.handle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)
            Start-Sleep -Milliseconds 500
            if(-not$accepted-or[TzDialogWatch]::IsWindow([IntPtr][long]$dialog.handle)){
                # Some T20/AutoCAD 2021 builds keep the DirectUI-hosted
                # notification alive after WM_CLOSE even though the explicit
                # Close button is available.  Fall back only to the exact
                # whitelisted Close button; never toggle "do not show again"
                # and never invoke drawing repair.
                [void][TzDialogWatch]::SendMessage($button,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
                Start-Sleep -Milliseconds 750
            }
            if([TzDialogWatch]::IsWindow([IntPtr][long]$dialog.handle)){
                Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='STANDARD_CLOSE_FAILED_STOP';process_id=$ProcessId;rule_id=$rule[0].id;dialog=$dialog})
                throw "WHITELIST_STANDARD_CLOSE_FAILED=$($rule[0].id)"
            }
            Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='AUTO_DISMISSED';process_id=$ProcessId;rule_id=$rule[0].id;dialog_title=$dialog.title;button_text=$rule[0].required_button_text;matched_by='exact_signature_standard_close'})
            continue
        }
        if([string]$rule[0].action-eq'observe_trusted_nonblocking_command_palette'){
            # Run evidence shows that TDimMP can complete and create the exact
            # native length dimension while this small "逐点标注" palette is
            # visible.  "标总尺寸" is an optional mode control, not a success
            # acknowledgement.  Do not change its state and do not close the
            # palette; accept only the exact trusted signature, then let the
            # native command result and source mapping decide success.
            Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='KNOWN_NONBLOCKING_DIALOG_OBSERVED';process_id=$ProcessId;rule_id=$rule[0].id;dialog_title=$dialog.title;button_text=$rule[0].required_button_text;matched_by='exact_trusted_tdimmp_nonblocking_palette';trusted_script=$trustedScriptContext})
            if([bool]$rule[0].requires_trusted_script_context){$trustedScriptDismissedCount++}
            continue
        }
        [void][TzDialogWatch]::SendMessage($button,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)
        if([string]$rule[0].action-eq'click_exact_button_then_stop'){
            Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='KNOWN_FAILURE_DISMISSED_AND_STOPPED';process_id=$ProcessId;rule_id=$rule[0].id;dialog_title=$dialog.title;button_text=$rule[0].required_button_text})
            throw "KNOWN_TIANZHENG_DIALOG_FAILURE=$($rule[0].id)"
        }
        Write-DialogLog([pscustomobject]@{at=(Get-Date).ToString('o');status='AUTO_DISMISSED';process_id=$ProcessId;rule_id=$rule[0].id;dialog_title=$dialog.title;button_text=$rule[0].required_button_text;trusted_script=$trustedScriptContext})
        if([bool]$rule[0].requires_trusted_script_context){$trustedScriptDismissedCount++}
    }
    if($MaxTrustedScriptAutoDismissCount-gt0-and$trustedScriptDismissedCount-ge$MaxTrustedScriptAutoDismissCount){break}
    if($SinglePass){break}
    if((Test-OwnedMainTitle -RequiredTitle $RequiredMainTitle)-and@(Get-OwnedVisibleDialogs).Count-eq0){
        if($null-eq$quietSince){$quietSince=Get-Date}
        elseif($QuietSeconds-gt0-and((Get-Date)-$quietSince).TotalSeconds-ge$QuietSeconds){break}
    }else{$quietSince=$null}
    Start-Sleep -Milliseconds $PollMilliseconds
}
