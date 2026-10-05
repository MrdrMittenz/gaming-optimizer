# Read-only plan generation. The exact listed entries are used after confirmation.

function Get-GamingPlan {
    param([string[]]$Keep=@(),[string[]]$KeepServices=@())
    $settings = @(
        foreach ($setting in @(Get-BaseSettings)) {
            [pscustomobject]@{
                Path=$setting.Path;Name=$setting.Name;Description=$setting.Description
                Before=(Get-RegistryState $setting.Path $setting.Name)
                Desired=[pscustomobject]@{Exists=$true;Kind=$setting.Kind;Value=$setting.Value}
            }
        }
    )
    $startup = @(
        foreach ($entry in @(Get-StartupCandidates -Keep $Keep)) {
            [pscustomobject]@{App=$entry.App;Path=$entry.Path;Name=$entry.Name;Before=(Get-RegistryState $entry.Path $entry.Name)}
        }
    )
    $notices=@(); $packages=@()
    $policyNames=@('LetAppsRunInBackground','LetAppsRunInBackground_ForceDenyTheseApps',
        'LetAppsRunInBackground_ForceAllowTheseApps','LetAppsRunInBackground_UserInControlOfTheseApps')
    $policyBefore=@($policyNames | ForEach-Object { [pscustomobject]@{Name=$_;State=(Get-RegistryState $script:PrivacyPath $_)} })
    $os=Get-WindowsInfo
    if ($os.Build -lt 15063 -or -not (Test-PolicyEdition $os)) {
        $notices+='Packaged-app background controls: manual on this Windows edition'
    } else {
        $default=$policyBefore[0].State; $deny=$policyBefore[1].State
        if ($default.Exists -and ($default.Kind -ne 'DWord' -or $default.Value -ne 0)) {
            $notices+='Packaged-app background controls: existing global policy preserved'
        } elseif ($deny.Exists -and $deny.Kind -ne 'MultiString') {
            $notices+='Packaged-app background controls: unexpected policy format, skipped'
        } else {
            $exceptions=@()
            foreach ($value in @($policyBefore[2].State,$policyBefore[3].State)) {
                if ($value.Exists) { $exceptions+=@($value.Value) }
            }
            foreach ($package in @(Get-BackgroundCandidates -Keep $Keep)) {
                if ($exceptions -contains $package.PackageFamilyName) {
                    $notices+="$($package.Name): existing background exception preserved"
                } elseif ($deny.Exists -and @($deny.Value) -contains $package.PackageFamilyName) {
                    $notices+="$($package.Name): background activity already disabled"
                } else { $packages+=$package }
            }
        }
    }
    $security=Get-SecurityPlan
    [pscustomobject]@{
        Settings=@($settings)+@($security.Registry);Startup=$startup;BackgroundPackages=$packages
        BackgroundPolicyBefore=$policyBefore;Services=@(Get-ServicePlan -Keep $KeepServices)
        Processes=@(Get-SessionCandidates -Groups @('Overlay','Recorder','Booster','Chat') -Keep $Keep)
        Notices=@($notices)+@($security.Notices);Security=@($security.Settings);Created=(Get-Date).ToString('o')
    }
}

function Get-GamingPlanText {
    param($Plan)
    'GAMING PROFILE - REVIEW BEFORE CONTINUING'
    ''
    'Reducing background CPU, GPU, disk and network work can leave more resources for games. Closing competing overlays and recording tools may reduce rendering conflicts, interruptions and frame-time spikes. FPS gains and external ESP compatibility are not guaranteed.'
    ''
    'CHECKLIST: [x] selected action; [=] already set; [ ] preserved, absent or not automated.'
    'No changes have been made by this preview.'
    ''
    foreach ($setting in $Plan.Settings) {
        $mark='x'; if (Test-StateEqual $setting.Before $setting.Desired) { $mark='=' }
        "[$mark] $($setting.Description)"
    }
    foreach ($entry in $Plan.Startup) { "[x] Disable startup: $($entry.App) [$($entry.Name)]" }
    if ($Plan.Startup.Count -eq 0) { '[ ] No matching optional startup entries' }
    foreach ($package in $Plan.BackgroundPackages) { "[x] Disable background activity: $($package.Name)" }
    foreach ($entry in $Plan.Services) {
        $mark=' ';$suffix=''
        if ($entry.Decision -eq 'Disable') { $mark='x' }
        elseif ($entry.Decision -eq 'Already disabled') { $mark='=' }
        else { $suffix=' - '+$entry.Decision }
        $label=$entry.Name
        if ($null -ne $entry.State) { $label="$($entry.State.DisplayName) ($($entry.Name))" }
        "[$mark] Disable service: $label$suffix"
    }
    foreach ($entry in $Plan.Security) {
        $mark='x'; if ($entry.Before -eq $entry.After) { $mark='=' }
        "[$mark] Configure off: $($entry.Label)"
    }
    foreach ($group in @($Plan.Processes | Group-Object App)) {
        "[x] Close app/overlay: $($group.Name) ($($group.Count) process(es))"
    }
    if ($Plan.Processes.Count -eq 0) { '[ ] No matching optional apps currently running' }
    foreach ($notice in $Plan.Notices) { "[ ] $notice" }
    '[ ] In-app overlay switches: Steam, EA, Ubisoft, AMD, Discord, NVIDIA and hardware HUDs (not universally automated)'
    '[ ] Startup folders, packaged startup tasks and scheduled tasks (preserved)'
    ''
    'KEEP AVAILABLE'
    '[x] Audio, microphone, Ethernet/Wi-Fi, USB, Bluetooth, controllers, mouse and keyboard'
    '[x] Graphics drivers, desktop rendering, game launchers, Steam Input and gaming runtimes'
    '[x] Device/profile/fan-control software, Windows Update and unknown services'
    ''
    'Save work and recordings and finish calls first. Apps in the close list will be terminated. Listed service changes apply to all users; printing and indexed-search features will be unavailable if their services are selected. No apps will be uninstalled.'
    'The listed security changes are requested compatibility settings, not proven FPS improvements. Disabling scanning, firewall filtering and Memory integrity exposes the PC to malware and network attacks. Some games may require security features. Memory integrity changes require a restart.'
    'This does not switch off every Windows Security tab. Unsupported, tamper-protected and firmware-controlled items remain listed as not automated.'
    'Re-enable all restores the saved settings and service startup/running states. Closed apps must be reopened.'
}

function Show-GamingChecklist {
    param($Plan)
    $keepSection = $false
    foreach ($line in @(Get-GamingPlanText $Plan)) {
        if ($line -eq 'GAMING PROFILE - REVIEW BEFORE CONTINUING') {
            Write-Host "`n================================================================" -ForegroundColor Magenta
            Write-Host $line -ForegroundColor Cyan
            Write-Host '================================================================' -ForegroundColor Magenta
        } elseif ($line -eq 'KEEP AVAILABLE') {
            $keepSection = $true
            Write-Host $line -ForegroundColor Green
        } elseif ($line -match '^\[([x= ])\]') {
            $marker = $Matches[1]
            $colour = 'Yellow'
            if ($keepSection -or $marker -eq '=') { $colour = 'Green' }
            elseif ($marker -eq ' ') { $colour = 'DarkGray' }
            Write-Host $line.Substring(0, 3) -ForegroundColor $colour -NoNewline
            $bodyColour = 'Cyan'
            if ($keepSection -or $marker -eq '=') { $bodyColour = 'Green' }
            elseif ($marker -eq ' ') { $bodyColour = 'Gray' }
            Write-Host $line.Substring(3) -ForegroundColor $bodyColour
        } elseif ($line.StartsWith('CHECKLIST:')) {
            Write-Host 'CHECKLIST: ' -ForegroundColor Magenta -NoNewline
            Write-Host '[x] selected action; ' -ForegroundColor Yellow -NoNewline
            Write-Host '[=] already set; ' -ForegroundColor Green -NoNewline
            Write-Host '[ ] preserved, absent or not automated.' -ForegroundColor Gray
        } elseif ($line.StartsWith('The listed security changes')) {
            Write-Host $line -ForegroundColor Red
        } elseif ($line.StartsWith('Save work') -or $line.StartsWith('This does not')) {
            Write-Host $line -ForegroundColor Yellow
        } elseif ($line.StartsWith('Re-enable all')) {
            Write-Host $line -ForegroundColor Green
        } elseif ($line.StartsWith('Reducing background')) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line -ForegroundColor Gray
        }
    }
}

function Read-GamingPrompt {
    param([string]$Prompt)
    Write-Host "`n> $Prompt`: " -ForegroundColor Yellow -NoNewline
    Read-Host
}

function Confirm-GamingPlan {
    param($Plan)
    Show-GamingChecklist $Plan
    $answer=Read-GamingPrompt 'Type YES to disable the checked items; press Enter to cancel'
    return ($null -ne $answer -and $answer.Trim() -ceq 'YES')
}
