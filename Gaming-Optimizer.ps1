#requires -Version 5.1
<#
.SYNOPSIS
Reversible Windows 10/11 gaming settings. Does not uninstall anything.
.DESCRIPTION
The menu offers Disable all and Re-enable all. DisableAll combines supported
Windows settings, selected startup/background restrictions, and closing known
optional apps. EnableAll restores its saved profile without a backup selection.
Third-party switches that cannot be controlled are reported explicitly.
Advanced Audit/Apply/Session/Restore modes remain available on the command line.
Use Windows PowerShell 5.1 (64-bit), elevated as your usual gaming account for
DisableAll/EnableAll/Apply/Restore. Read README.txt for coverage limits.
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode DisableAll
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode EnableAll
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode Apply -DisableStartup -DisableBackgroundApps -WhatIf
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode Apply -DisableStartup -DisableBackgroundApps
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode Session -CloseRecorders -CloseBoosters -WhatIf
.EXAMPLE
.\Gaming-Optimizer.ps1 -Mode Restore -BackupPath 'C:\path\backup.clixml'
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('DisableAll','EnableAll','Audit','Apply','Session','Restore','Guide','Menu')]
    [string]$Mode = 'Menu',
    [switch]$DisableStartup,
    [switch]$DisableBackgroundApps,
    [switch]$CloseRecorders,
    [switch]$CloseBoosters,
    [switch]$CloseChatApps,
    [switch]$ForceClose,
    [string[]]$KeepApps = @(),
    [string[]]$KeepServices = @(),
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Journal = $null
$script:JournalPath = $null
$script:BackupRoot = Join-Path $env:LOCALAPPDATA 'GamingOptimizer\Backups'
$script:ActiveProfilePath = Join-Path $env:LOCALAPPDATA 'GamingOptimizer\ActiveProfile.txt'
$script:PrivacyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
$script:RunPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

function Get-AppCatalog {
    # Exact names only. No drivers, services, launchers or hardware utilities.
    @(
        [pscustomobject]@{ Id='GameBar'; Group='Overlay'; Processes=@('GameBar','GameBarFTServer','GameBarPresenceWriter'); Startup=@() }
        [pscustomobject]@{ Id='Overwolf'; Group='Overlay'; Processes=@('Overwolf','OverwolfBrowser','OverwolfHelper','OverwolfHelper64'); Startup=@('Overwolf') }
        [pscustomobject]@{ Id='RTSS'; Group='Overlay'; Processes=@('RTSS','RTSSHooksLoader','RTSSHooksLoader64'); Startup=@('RTSS','RivaTuner Statistics Server') }
        [pscustomobject]@{ Id='NVIDIAOverlay'; Group='Overlay'; Processes=@('NVIDIA Overlay','NVIDIA Share'); Startup=@() }
        [pscustomobject]@{ Id='NVIDIAApp'; Group='Overlay'; Processes=@('NVIDIA app'); Startup=@() }
        [pscustomobject]@{ Id='Discord'; Group='Overlay'; Processes=@('Discord','DiscordPTB','DiscordCanary'); Startup=@('Discord','DiscordPTB','DiscordCanary') }
        [pscustomobject]@{ Id='SteamOverlay'; Group='Overlay'; Processes=@('gameoverlayui'); Startup=@() }
        [pscustomobject]@{ Id='OBS'; Group='Recorder'; Processes=@('obs32','obs64'); Startup=@('OBS Studio') }
        [pscustomobject]@{ Id='Streamlabs'; Group='Recorder'; Processes=@('Streamlabs OBS','Streamlabs Desktop'); Startup=@('Streamlabs OBS','Streamlabs Desktop') }
        [pscustomobject]@{ Id='Fraps'; Group='Recorder'; Processes=@('fraps'); Startup=@('Fraps') }
        [pscustomobject]@{ Id='Bandicam'; Group='Recorder'; Processes=@('bdcam'); Startup=@('Bandicam') }
        [pscustomobject]@{ Id='Action'; Group='Recorder'; Processes=@('Action'); Startup=@('Action!') }
        [pscustomobject]@{ Id='ISLC'; Group='Booster'; Processes=@('Intelligent standby list cleaner ISLC'); Startup=@('ISLC','Intelligent standby list cleaner') }
        [pscustomobject]@{ Id='CCleaner'; Group='Booster'; Processes=@('CCleaner','CCleaner64','CCleanerBrowser'); Startup=@('CCleaner Smart Cleaning','CCleaner Monitoring') }
        [pscustomobject]@{ Id='RazerCortex'; Group='Booster'; Processes=@('RazerCortex','CortexLauncher'); Startup=@('Razer Cortex','RazerCortex') }
        [pscustomobject]@{ Id='Skype'; Group='Chat'; Processes=@('Skype','SkypeApp'); Startup=@('Skype','Skype for Desktop') }
        [pscustomobject]@{ Id='Zoom'; Group='Chat'; Processes=@('Zoom'); Startup=@('Zoom','Zoom Workplace') }
        [pscustomobject]@{ Id='Teams'; Group='Chat'; Processes=@('Teams','ms-teams'); Startup=@('Teams','com.squirrel.Teams.Teams') }
    )
}

function Get-BackgroundAppNames {
    # Retain Store, Xbox/Gaming Services, codecs, runtimes, audio and input apps.
    @('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingFinance',
      'Microsoft.BingSports','Microsoft.GetHelp','Microsoft.Getstarted',
      'Microsoft.WindowsFeedbackHub','Microsoft.MicrosoftOfficeHub',
      'Microsoft.MicrosoftSolitaireCollection','Microsoft.MixedReality.Portal',
      'Microsoft.Microsoft3DViewer','Microsoft.Print3D','Microsoft.People',
      'Microsoft.YourPhone','Clipchamp.Clipchamp')
}

function Get-WindowsInfo {
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{ Build=[int]$os.CurrentBuildNumber; Edition=[string]$os.EditionID }
}

function Test-PolicyEdition {
    param($WindowsInfo)
    $WindowsInfo.Edition -match '^(Professional|Enterprise|Education|IoTEnterprise)'
}

function Get-BaseSettings {
    param($WindowsInfo = (Get-WindowsInfo))
    $rows = @(
        @('HKCU:\System\GameConfigStore','GameDVR_Enabled',0,'Disable Windows game capture'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR','AppCaptureEnabled',0,'Disable Windows app capture'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR','HistoricalCaptureEnabled',0,'Disable background recording'),
        @('HKCU:\SOFTWARE\Microsoft\GameBar','AutoGameModeEnabled',1,'Enable Game Mode'),
        @('HKCU:\SOFTWARE\Microsoft\GameBar','UseNexusForGameBarEnabled',0,'Disable controller button opening Game Bar'),
        @('HKCU:\SOFTWARE\Microsoft\GameBar','ShowStartupPanel',0,'Hide Game Bar startup tips'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SilentInstalledAppsEnabled',0,'Disable suggested app installation'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SystemPaneSuggestionsEnabled',0,'Disable Start app suggestions'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager','SubscribedContent-338389Enabled',0,'Disable Windows tips'),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement','ScoobeSystemSettingEnabled',0,'Disable setup suggestions')
    )
    if ($WindowsInfo.Build -lt 22000 -and (Test-PolicyEdition $WindowsInfo)) {
        # Microsoft documents this policy as enforced on Windows 10 desktop only.
        $rows += ,@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR','AllowGameDVR',0,'Disable Windows 10 recording policy')
    }
    foreach ($row in $rows) {
        [pscustomobject]@{ Path=$row[0]; Name=$row[1]; Kind='DWord'; Value=[int]$row[2]; Description=$row[3] }
    }
}

function Get-RegistryState {
    param([string]$Path, [string]$Name)
    if (Test-Path -LiteralPath $Path) {
        $key = Get-Item -LiteralPath $Path
        try {
            if ($key.GetValueNames() -contains $Name) {
                return [pscustomobject]@{
                    Exists=$true; Kind=$key.GetValueKind($Name).ToString()
                    Value=$key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            }
        } finally { $key.Close() }
    }
    [pscustomobject]@{ Exists=$false; Kind=$null; Value=$null }
}

function Test-StateEqual {
    param($Left, $Right)
    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    if ($Left.Kind -ne $Right.Kind) { return $false }
    $a = @($Left.Value); $b = @($Right.Value)
    if ($a.Count -ne $b.Count) { return $false }
    for ($i=0; $i -lt $a.Count; $i++) {
        if ($a[$i] -cne $b[$i]) { return $false }
    }
    return $true
}

function Set-RegistryState {
    param([string]$Path, [string]$Name, $State)
    if ($State.Exists) {
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force }
        $value = $State.Value
        if ($State.Kind -eq 'Binary') { $value = [byte[]]$value }
        if ($State.Kind -eq 'MultiString') { $value = [string[]]$value }
        $null = New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $State.Kind -Value $value -Force
    } elseif ((Get-RegistryState $Path $Name).Exists) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name
    }
}

function Save-Journal {
    # A complete original state is flushed before any setting is changed.
    $folder = Split-Path -Parent $script:JournalPath
    if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    $temporary = $script:JournalPath + '.tmp'
    $script:Journal | Export-Clixml -LiteralPath $temporary -Depth 12 -Encoding UTF8
    if (Test-Path -LiteralPath $script:JournalPath) {
        [System.IO.File]::Replace($temporary, $script:JournalPath, [NullString]::Value)
    } else {
        [System.IO.File]::Move($temporary, $script:JournalPath)
    }
}

function Start-Journal {
    if ($null -eq $script:Journal) {
        $script:JournalPath = Join-Path $script:BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.clixml')
        $script:Journal = [pscustomobject]@{
            Version=1; Computer=$env:COMPUTERNAME
            UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            Created=(Get-Date).ToString('o'); Changes=@()
        }
        Save-Journal
        Write-Host "Backup: $script:JournalPath" -ForegroundColor Cyan
    }
}

function Set-BackedSetting {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Path, [string]$Name, $Desired, [string]$Description)
    $original = Get-RegistryState $Path $Name
    if (Test-StateEqual $original $Desired) {
        Write-Host "Already set: $Description" -ForegroundColor Green
        return
    }
    if (-not $PSCmdlet.ShouldProcess("$Path [$Name]", $Description)) { return }
    Start-Journal
    # Repeated DisableAll must retain the first snapshot, including after drift.
    $existing = @($script:Journal.Changes | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name })
    if ($existing.Count -gt 0 -and $script:Journal.PSObject.Properties.Name -contains 'AllProfile') {
        $change = $existing[0]
        $change.After = $Desired; $change.Status = 'Pending'; $change.Error = $null
    } else {
        $change = [pscustomobject]@{ Path=$Path; Name=$Name; Before=$original; After=$Desired; Status='Pending'; Error=$null }
        $script:Journal.Changes = @($script:Journal.Changes) + $change
    }
    Save-Journal
    try {
        Set-RegistryState $Path $Name $Desired
        if (-not (Test-StateEqual (Get-RegistryState $Path $Name) $Desired)) { throw 'Registry verification failed.' }
        $change.Status = 'Applied'
    } catch {
        $change.Status = 'Failed'; $change.Error = $_.Exception.Message
        Save-Journal
        throw
    }
    Save-Journal
    Write-Host "Applied: $Description" -ForegroundColor Green
}

function Get-StartupCandidates {
    param([string[]]$Keep = @())
    foreach ($path in $script:RunPaths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $key = Get-Item -LiteralPath $path
        try { $names = $key.GetValueNames() } finally { $key.Close() }
        foreach ($app in @(Get-AppCatalog)) {
            if ($Keep -contains $app.Id) { continue }
            foreach ($name in $app.Startup) {
                if ($names -contains $name) {
                    [pscustomobject]@{ App=$app.Id; Path=$path; Name=$name }
                }
            }
        }
    }
}

function Get-BackgroundCandidates {
    param([string[]]$Keep = @())
    $allowed = @(Get-BackgroundAppNames | Where-Object { $Keep -notcontains $_ })
    @(Get-AppxPackage -ErrorAction Stop | Where-Object { $allowed -contains $_.Name } |
        Select-Object Name,PackageFamilyName -Unique)
}

function Set-BackgroundPolicy {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string[]]$Keep = @(),[object[]]$Packages)
    $windows = Get-WindowsInfo
    if ($windows.Build -lt 15063 -or -not (Test-PolicyEdition $windows)) {
        Write-Warning 'Selective background policy is unavailable on this edition. Use per-app Background permissions in Settings; see README.txt.'
        return
    }
    if (-not $PSBoundParameters.ContainsKey('Packages')) { $Packages = @(Get-BackgroundCandidates -Keep $Keep) }
    $packages = @($Packages)
    if ($packages.Count -eq 0) { Write-Host 'No matching packaged background apps.' -ForegroundColor Gray; return }
    $default = Get-RegistryState $script:PrivacyPath 'LetAppsRunInBackground'
    if ($default.Exists -and ($default.Kind -ne 'DWord' -or $default.Value -ne 0)) {
        Write-Warning 'An existing global background policy is configured. Leaving that policy and its exceptions untouched.'
        return
    }
    $deny = Get-RegistryState $script:PrivacyPath 'LetAppsRunInBackground_ForceDenyTheseApps'
    if ($deny.Exists -and $deny.Kind -ne 'MultiString') { throw 'Existing background deny list has an unexpected type; no policy changes made.' }
    $conflicts = @()
    foreach ($name in @('LetAppsRunInBackground_ForceAllowTheseApps','LetAppsRunInBackground_UserInControlOfTheseApps')) {
        $existing = Get-RegistryState $script:PrivacyPath $name
        if ($existing.Exists) { $conflicts += @($existing.Value) }
    }
    $families = @($packages | Where-Object { $conflicts -notcontains $_.PackageFamilyName } | ForEach-Object { $_.PackageFamilyName })
    if ($families.Count -ne $packages.Count) { Write-Warning 'Apps with existing allow/user-control policy exceptions were skipped.' }
    if ($families.Count -eq 0) { return }
    $combined = @($families)
    if ($deny.Exists) { $combined += @($deny.Value) }
    $combined = [string[]]@($combined | Sort-Object -Unique)
    Set-BackedSetting $script:PrivacyPath 'LetAppsRunInBackground' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=0}) 'Keep other background apps under user control' -WhatIf:$WhatIfPreference
    Set-BackedSetting $script:PrivacyPath 'LetAppsRunInBackground_ForceDenyTheseApps' ([pscustomobject]@{Exists=$true;Kind='MultiString';Value=$combined}) "Deny selected packaged background apps: $($families -join ', ')" -WhatIf:$WhatIfPreference
}

function Get-SessionCandidates {
    param([string[]]$Groups = @('Overlay'), [string[]]$Keep = @())
    $session = (Get-Process -Id $PID).SessionId
    $running = @(Get-Process | Where-Object { $_.SessionId -eq $session -and $_.Id -ne $PID })
    foreach ($app in @(Get-AppCatalog)) {
        if ($Groups -notcontains $app.Group -or $Keep -contains $app.Id) { continue }
        foreach ($process in $running) {
            if ($app.Processes -contains $process.ProcessName) {
                [pscustomobject]@{ App=$app.Id; Group=$app.Group; Process=$process }
            }
        }
    }
}

function Invoke-SessionCleanup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string[]]$Groups = @('Overlay'), [string[]]$Keep = @(), [switch]$Force, [object[]]$Candidates)
    if (-not $PSBoundParameters.ContainsKey('Candidates')) { $Candidates = @(Get-SessionCandidates -Groups $Groups -Keep $Keep) }
    $candidates = @($Candidates)
    if ($candidates.Count -eq 0) { Write-Host 'No matching apps are running in this Windows session.' -ForegroundColor Gray; return }
    foreach ($item in $candidates) {
        $process = $item.Process
        $label = "$($item.App): $($process.ProcessName) (PID $($process.Id))"
        $action = 'Request app exit (no forced termination)'
        if ($Force) { $action = 'Terminate app; unsaved recordings/calls may be lost' }
        if (-not $PSCmdlet.ShouldProcess($label, $action)) { continue }
        try {
            if ($process.HasExited) { continue }
            if ($Force) {
                # Pass the captured process object, not a fresh name lookup.
                Stop-Process -InputObject $process -Force -ErrorAction Stop
                if (-not $process.WaitForExit(3000)) { Write-Warning "Still running: $label" }
                else { Write-Host "Closed: $label" -ForegroundColor Green }
            } elseif ($process.CloseMainWindow()) {
                if ($process.WaitForExit(3000)) { Write-Host "Closed: $label" -ForegroundColor Green }
                else { Write-Warning "Still running or minimized to tray: $label. Exit using its tray menu." }
            } else {
                Write-Warning "No closeable main window: $label. Exit using its tray menu, or explicitly use -ForceClose after saving work."
            }
        } catch { Write-Warning "Could not close $label. $($_.Exception.Message)" }
    }
    Write-Host 'Restart the game after changing overlays. App settings must also be disabled to prevent helpers returning.' -ForegroundColor Yellow
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open Windows PowerShell as administrator using your usual gaming account, then run again. Audit and -WhatIf need no elevation.'
    }
}

function Test-RestoreTarget {
    param([string]$Path, [string]$Name)
    $allBase = @(Get-BaseSettings ([pscustomobject]@{Build=19045;Edition='Professional'})) + @(Get-SecurityRegistryCatalog)
    if (@($allBase | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name }).Count -gt 0) { return $true }
    if ($Path -eq $script:PrivacyPath -and $Name -in @('LetAppsRunInBackground','LetAppsRunInBackground_ForceDenyTheseApps')) { return $true }
    if ($script:RunPaths -contains $Path) {
        $names = @(Get-AppCatalog | ForEach-Object { $_.Startup })
        return ($names -contains $Name)
    }
    return $false
}

function Read-SettingsJournal {
    param([Parameter(Mandatory=$true)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $journal = Import-Clixml -LiteralPath $resolved
    if ($journal.Version -ne 1 -or $journal.Computer -ne $env:COMPUTERNAME -or
        $journal.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        throw 'This backup belongs to another computer/user or an unsupported script version.'
    }
    # Validate the entire journal before changing anything; never execute saved commands.
    foreach ($change in @($journal.Changes)) {
        if (-not (Test-RestoreTarget $change.Path $change.Name)) { throw 'Backup contains an unexpected registry target.' }
        foreach ($state in @($change.Before,$change.After)) {
            if ($state.Exists -isnot [bool]) { throw 'Invalid backup state.' }
            if ($state.Exists -and $state.Kind -notin @('DWord','QWord','String','ExpandString','MultiString','Binary','None')) { throw 'Invalid backup registry type.' }
        }
    }
    Test-ServiceJournal $journal
    Test-SecurityJournal $journal
    return $journal
}

function Restore-Settings {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $journal = Read-SettingsJournal -Path $resolved
    $script:Journal = $journal; $script:JournalPath = $resolved
    $changes = @($journal.Changes)
    [array]::Reverse($changes)
    $conflicts = 0
    foreach ($change in $changes) {
        if ($change.Status -eq 'Restored') { continue }
        $current = Get-RegistryState $change.Path $change.Name
        if (Test-StateEqual $current $change.Before) {
            if ($PSCmdlet.ShouldProcess($change.Name, 'Mark already-original setting restored in journal')) {
                $change.Status = 'Restored'; Save-Journal
            }
            continue
        }
        if (-not (Test-StateEqual $current $change.After)) {
            $conflicts++
            Write-Warning "Changed since Apply; left untouched: $($change.Path) [$($change.Name)]"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$($change.Path) [$($change.Name)]", 'Restore original setting')) {
            Set-RegistryState $change.Path $change.Name $change.Before
            if (-not (Test-StateEqual (Get-RegistryState $change.Path $change.Name) $change.Before)) { throw 'Restore verification failed.' }
            $change.Status = 'Restored'; Save-Journal
            Write-Host "Restored: $($change.Name)" -ForegroundColor Green
        }
    }
    Restore-Services -WhatIf:$WhatIfPreference
    Restore-SecuritySettings -WhatIf:$WhatIfPreference
    Write-Host "Restore pass finished. Conflicts skipped: $conflicts. Sign out/restart after an actual restore." -ForegroundColor Cyan
    Write-Host 'Closed apps must be reopened manually. Empty registry keys created by Apply may remain.' -ForegroundColor Yellow
}

function Show-Audit {
    Write-Host 'READ-ONLY AUDIT: no settings changed and no apps closed.' -ForegroundColor Cyan
    Write-Host 'Windows settings proposed by Apply:' -ForegroundColor Magenta
    Get-BaseSettings | ForEach-Object {
        $current = Get-RegistryState $_.Path $_.Name
        $value = '(not configured)'
        if ($current.Exists) { $value = [string]$current.Value }
        [pscustomobject]@{ Setting=$_.Description; Current=$value; Target=$_.Value }
    } | Format-Table -AutoSize | Out-Host
    Write-Host 'Selected startup entries (-DisableStartup); unmatched apps are preserved:' -ForegroundColor Magenta
    @(Get-StartupCandidates -Keep $KeepApps) | Format-Table App,Name,Path -AutoSize | Out-Host
    Write-Host 'Packaged apps eligible for selective background restrictions (-DisableBackgroundApps):' -ForegroundColor Magenta
    try { @(Get-BackgroundCandidates -Keep $KeepApps) | Format-Table -AutoSize | Out-Host }
    catch { Write-Warning "Package inventory unavailable: $($_.Exception.Message)" }
    if (-not (Test-PolicyEdition (Get-WindowsInfo))) { Write-Warning 'This Windows edition needs manual per-app background settings.' }
    Write-Host 'Running optional apps (detection does not mean an overlay is enabled):' -ForegroundColor Magenta
    @(Get-SessionCandidates -Groups @('Overlay','Recorder','Booster','Chat') -Keep $KeepApps) |
        Select-Object App,Group,@{Name='Process';Expression={$_.Process.ProcessName}},@{Name='PID';Expression={$_.Process.Id}} |
        Format-Table -AutoSize | Out-Host
    Write-Host 'App-specific overlays, Startup-folder shortcuts, packaged startup tasks and scheduled tasks require the checklist in README.txt.' -ForegroundColor Yellow
}

function Get-ActiveProfile {
    if (-not (Test-Path -LiteralPath $script:ActiveProfilePath)) { return $null }
    $path = (Get-Content -LiteralPath $script:ActiveProfilePath -Raw).Trim()
    $root = [IO.Path]::GetFullPath($script:BackupRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($full) -ne '.clixml') {
        throw 'The active backup pointer is invalid. No settings were changed.'
    }
    $journal = Read-SettingsJournal -Path $full
    if ($journal.PSObject.Properties.Name -notcontains 'AllProfile' -or -not $journal.AllProfile) {
        throw 'The saved file is not a Disable all profile. No settings were changed.'
    }
    [pscustomobject]@{ Path=$full; Journal=$journal }
}

function Open-AllProfile {
    $active = Get-ActiveProfile
    if ($null -ne $active) {
        $script:Journal = $active.Journal; $script:JournalPath = $active.Path
        Write-Host 'Using your original saved settings.' -ForegroundColor Cyan
        return
    }
    $script:Journal = $null; $script:JournalPath = $null
    Start-Journal
    $script:Journal | Add-Member -MemberType NoteProperty -Name AllProfile -Value $true
    Save-Journal
    $folder = Split-Path -Parent $script:ActiveProfilePath
    if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    $temporary = $script:ActiveProfilePath + '.tmp'
    [IO.File]::WriteAllText($temporary, $script:JournalPath)
    # Pointer is committed before changing settings, so interrupted runs can restore.
    [IO.File]::Move($temporary, $script:ActiveProfilePath)
}

function Invoke-DisableAll {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string[]]$Keep = @(),[string[]]$ServiceKeep = @())
    $plan = Get-GamingPlan -Keep $Keep -KeepServices $ServiceKeep
    if ($WhatIfPreference) { Show-GamingChecklist $plan }
    elseif (-not (Confirm-GamingPlan $plan)) { Write-Host 'Cancelled. Nothing was changed or closed.' -ForegroundColor Yellow; return }
    if (-not $WhatIfPreference) { Open-AllProfile }
    $issues = @()
    foreach ($setting in $plan.Settings) {
        try {
            if (@(Get-SecurityRegistryCatalog | Where-Object { $_.Path -eq $setting.Path -and $_.Name -eq $setting.Name }).Count -gt 0) {
                Assert-SecurityRegistryEditable $setting
            }
            if (-not (Test-StateEqual (Get-RegistryState $setting.Path $setting.Name) $setting.Before)) {
                throw 'Changed since the checklist was shown; skipped.'
            }
            Set-BackedSetting $setting.Path $setting.Name $setting.Desired $setting.Description -WhatIf:$WhatIfPreference
        } catch { $issues += "Could not change $($setting.Name): $($_.Exception.Message)" }
    }
    try {
        foreach ($entry in $plan.Startup) {
            try {
                if (-not (Test-StateEqual (Get-RegistryState $entry.Path $entry.Name) $entry.Before)) {
                    throw 'Changed since the checklist was shown; skipped.'
                }
                Set-BackedSetting $entry.Path $entry.Name ([pscustomobject]@{Exists=$false;Kind=$null;Value=$null}) "Disable $($entry.App) startup" -WhatIf:$WhatIfPreference
            } catch { $issues += "Could not disable $($entry.App) startup: $($_.Exception.Message)" }
        }
    } catch { $issues += "Startup scan failed: $($_.Exception.Message)" }
    try {
        foreach ($value in $plan.BackgroundPolicyBefore) {
            if (-not (Test-StateEqual (Get-RegistryState $script:PrivacyPath $value.Name) $value.State)) {
                throw 'Background policy changed since the checklist was shown; skipped.'
            }
        }
        Set-BackgroundPolicy -Keep $Keep -Packages @($plan.BackgroundPackages) -WhatIf:$WhatIfPreference -WarningVariable +issues
    } catch { $issues += "Background settings failed: $($_.Exception.Message)" }
    foreach ($entry in $plan.Services) {
        try { Set-BackedService -Entry $entry -Keep $ServiceKeep -WhatIf:$WhatIfPreference }
        catch { $issues += "Service $($entry.Name): $($_.Exception.Message)" }
    }
    foreach ($entry in $plan.Security) {
        try { Set-BackedSecuritySetting -Entry $entry -WhatIf:$WhatIfPreference }
        catch { $issues += "Security setting $($entry.Label): $($_.Exception.Message)" }
    }
    # Only the process objects shown before confirmation are eligible.
    try {
        Invoke-SessionCleanup -Groups @('Overlay','Recorder','Booster','Chat') -Candidates @($plan.Processes) -Keep $Keep -Force -WhatIf:$WhatIfPreference -WarningVariable +issues
    } catch { $issues += "Closing apps failed: $($_.Exception.Message)" }
    $limitations = @(
        'App-controlled switches still need attention: Discord, Steam, EA, Ubisoft, AMD and hardware/RGB overlays.',
        'NVIDIA/other helper processes may restart; this does not change their in-app overlay switch.',
        'Startup folders, packaged startup tasks and scheduled tasks are not changed.',
        'Audio, network, controllers, mouse, keyboard, USB, Bluetooth, launchers and drivers remain available.',
        'No FPS or external ESP compatibility guarantee; unknown rendering/loader dependencies are preserved.',
        'Memory integrity requires a restart. SmartScreen changes configure policies; browser/app restart may be needed.',
        'Tamper protection, third-party antivirus, firmware security and other unlisted protections are not disabled.'
    )
    if ($WhatIfPreference) {
        Write-Host 'Preview finished. Nothing was changed or closed.' -ForegroundColor Cyan
    } else {
        $reportPath = Join-Path (Split-Path -Parent $script:ActiveProfilePath) 'Last-result.txt'
        Get-GamingPlanText $plan | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $script:ActiveProfilePath) 'Last-checklist.txt') -Encoding UTF8
        @('DISABLE ALL - supported actions processed', (Get-Date).ToString('o'), '',
          'Items requiring attention:') + @($issues | ForEach-Object { [string]$_ }) + $limitations |
            Set-Content -LiteralPath $reportPath -Encoding UTF8
        Write-Host "Supported actions processed. Report: $reportPath" -ForegroundColor Cyan
        Write-Host 'Choose Re-enable all to restore your saved settings automatically.' -ForegroundColor Green
    }
    foreach ($issue in $issues) { Write-Warning ([string]$issue) }
    foreach ($limitation in $limitations) { Write-Host $limitation -ForegroundColor Yellow }
}

function Invoke-EnableAll {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    $active = Get-ActiveProfile
    if ($null -eq $active) { Write-Host 'Nothing to restore: no active Disable all profile.' -ForegroundColor Cyan; return }
    Restore-Settings -Path $active.Path -WhatIf:$WhatIfPreference
    if ($WhatIfPreference) { return }
    $restored = Read-SettingsJournal -Path $active.Path
    $pending = @($restored.Changes | Where-Object { $_.Status -ne 'Restored' })
    if ($restored.PSObject.Properties.Name -contains 'ServiceChanges') {
        $pending += @($restored.ServiceChanges | Where-Object { $_.Status -ne 'Restored' })
    }
    if ($restored.PSObject.Properties.Name -contains 'SecurityChanges') {
        $pending += @($restored.SecurityChanges | Where-Object { $_.Status -ne 'Restored' })
    }
    if ($pending.Count -gt 0) {
        Write-Warning "Re-enable incomplete: $($pending.Count) change(s) need attention. Your backup remains active."
        return
    }
    if ($PSCmdlet.ShouldProcess($script:ActiveProfilePath, 'Mark the profile restored; retain the original backup')) {
        Remove-Item -LiteralPath $script:ActiveProfilePath
    }
    Write-Host 'Saved settings restored. Closed apps can now be reopened normally.' -ForegroundColor Green
}

function Show-Menu {
    while ($true) {
        Write-Host "`n================================================================" -ForegroundColor Magenta
        Write-Host '                         GAMING OPTIMIZER' -ForegroundColor Cyan
        Write-Host '                 WINDOWS 10 / 11  |  NO UNINSTALLING' -ForegroundColor Cyan
        Write-Host '================================================================' -ForegroundColor Magenta
        Write-Host ''
        Write-Host '  [1] ' -ForegroundColor Yellow -NoNewline
        Write-Host 'Disable all' -ForegroundColor Yellow -NoNewline
        Write-Host ' - show checklist, then confirm' -ForegroundColor Cyan
        Write-Host '  [2] ' -ForegroundColor Green -NoNewline
        Write-Host 'Re-enable all' -ForegroundColor Green
        Write-Host ''
        Write-Host 'Close this window or press Enter to exit.' -ForegroundColor Gray
        Write-Host 'Disable closes known optional apps. Save recordings and end calls first.' -ForegroundColor Yellow
        Write-Host 'Applies supported changes; reports overlays that still need in-app settings.' -ForegroundColor Cyan
        $choice = Read-GamingPrompt 'Choose 1 or 2'
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq '0') { return }
        try {
            switch ($choice) {
                '1' { & $PSCommandPath -Mode DisableAll -KeepApps $KeepApps -KeepServices $KeepServices -WhatIf:$WhatIfPreference }
                '2' { & $PSCommandPath -Mode EnableAll -WhatIf:$WhatIfPreference }
                default { Write-Host 'Choose 1 or 2, or press Enter to exit.' -ForegroundColor Yellow }
            }
        } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    }
}

# Dot-sourcing loads functions for isolated tests without running the optimizer.
. (Join-Path $PSScriptRoot 'Gaming-Services.ps1')
. (Join-Path $PSScriptRoot 'Gaming-Security.ps1')
. (Join-Path $PSScriptRoot 'Gaming-Plan.ps1')
if ($MyInvocation.InvocationName -eq '.') { return }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    throw 'Run this script in 64-bit Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 or a 32-bit shell.'
}
$windows = Get-WindowsInfo
if ($windows.Build -lt 10240) { throw 'Windows 10 or 11 is required.' }
$knownKeep = @(Get-AppCatalog | ForEach-Object { $_.Id }) + @(Get-BackgroundAppNames)
foreach ($keep in $KeepApps) {
    if ($knownKeep -notcontains $keep) { throw "Unknown -KeepApps entry '$keep'. See README.txt for valid IDs; other apps are already preserved." }
}
if ($Mode -notin @('Apply','Audit') -and ($DisableStartup -or $DisableBackgroundApps)) { throw 'Startup/background switches are for Apply or Audit.' }
if ($Mode -ne 'Session' -and ($CloseRecorders -or $CloseBoosters -or $CloseChatApps -or $ForceClose)) { throw 'Close switches are for Session mode only.' }
if ($Mode -ne 'Restore' -and $BackupPath) { throw '-BackupPath is for Restore mode only.' }

switch ($Mode) {
    { $_ -in @('DisableAll','EnableAll') } {
        if (-not $WhatIfPreference) { Assert-Administrator }
        $mutexName = 'Local\GamingOptimizer-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $mutex = New-Object Threading.Mutex($false, $mutexName)
        $acquired = $false
        try {
            try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
            if (-not $acquired) { throw 'Another Disable/Re-enable operation is running. Wait for it to finish.' }
            if ($Mode -eq 'DisableAll') { Invoke-DisableAll -Keep $KeepApps -ServiceKeep $KeepServices -WhatIf:$WhatIfPreference }
            else { Invoke-EnableAll -WhatIf:$WhatIfPreference }
        } finally {
            if ($acquired) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
    'Audit' { Show-Audit }
    'Guide' {
        if ($PSCmdlet.ShouldProcess('README.txt', 'Open instructions in Notepad')) {
            Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + (Join-Path $PSScriptRoot 'README.txt') + '"')
        }
    }
    'Menu' { Show-Menu }
    'Apply' {
        if (-not $WhatIfPreference) { Assert-Administrator }
        try {
            foreach ($setting in @(Get-BaseSettings)) {
                Set-BackedSetting $setting.Path $setting.Name ([pscustomobject]@{Exists=$true;Kind=$setting.Kind;Value=$setting.Value}) $setting.Description -WhatIf:$WhatIfPreference
            }
            if ($DisableStartup) {
                foreach ($entry in @(Get-StartupCandidates -Keep $KeepApps)) {
                    Set-BackedSetting $entry.Path $entry.Name ([pscustomobject]@{Exists=$false;Kind=$null;Value=$null}) "Disable $($entry.App) Run startup entry (app stays installed)" -WhatIf:$WhatIfPreference
                }
            }
            if ($DisableBackgroundApps) { Set-BackgroundPolicy -Keep $KeepApps -WhatIf:$WhatIfPreference }
        } finally {
            if ($null -ne $script:JournalPath) { Write-Host "Restore journal: $script:JournalPath" -ForegroundColor Cyan }
        }
        if ($WhatIfPreference) { Write-Host 'Preview complete. No changes or backups were made.' -ForegroundColor Cyan }
        else { Write-Host 'Apply finished. Sign out or restart when convenient, then verify the app overlay settings in README.txt.' -ForegroundColor Cyan }
        Write-Host 'Game Bar remains installed; Win+G can still open it. No apps were uninstalled or closed by Apply.' -ForegroundColor Gray
    }
    'Session' {
        $groups = @('Overlay')
        if ($CloseRecorders) { $groups += 'Recorder' }
        if ($CloseBoosters) { $groups += 'Booster' }
        if ($CloseChatApps) { $groups += 'Chat' }
        Invoke-SessionCleanup -Groups $groups -Keep $KeepApps -Force:$ForceClose -WhatIf:$WhatIfPreference
    }
    'Restore' {
        if (-not $BackupPath) { throw 'Specify -BackupPath with the .clixml path printed by Apply, or choose Restore in the menu.' }
        if (-not $WhatIfPreference) { Assert-Administrator }
        Restore-Settings -Path $BackupPath -WhatIf:$WhatIfPreference
    }
}
