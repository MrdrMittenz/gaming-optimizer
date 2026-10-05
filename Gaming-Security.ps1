# Supported local settings only. No tamper bypass, driver removal, firmware changes,
# security-service destruction, exclusions, or Windows Security page hiding.

function Get-DefenderSettingCatalog {
    @(
        [pscustomobject]@{Name='DisableRealtimeMonitoring';Value=$true;Label='Defender real-time monitoring'},
        [pscustomobject]@{Name='DisableBehaviorMonitoring';Value=$true;Label='Defender behavior monitoring'},
        [pscustomobject]@{Name='DisableIOAVProtection';Value=$true;Label='Defender downloaded-file scanning'},
        [pscustomobject]@{Name='DisableScriptScanning';Value=$true;Label='Defender script scanning'},
        [pscustomobject]@{Name='DisableBlockAtFirstSeen';Value=$true;Label='Defender block at first sight'},
        [pscustomobject]@{Name='MAPSReporting';Value=0;Label='Defender cloud reporting'},
        [pscustomobject]@{Name='SubmitSamplesConsent';Value=2;Label='Defender automatic sample submission'},
        [pscustomobject]@{Name='PUAProtection';Value=0;Label='Defender potentially unwanted app blocking'},
        [pscustomobject]@{Name='EnableControlledFolderAccess';Value=0;Label='Controlled folder access'},
        [pscustomobject]@{Name='EnableNetworkProtection';Value=0;Label='Defender network protection'}
    )
}

function Get-SecurityRegistryCatalog {
    @(
        [pscustomobject]@{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity';Name='Enabled';Kind='DWord';Value=0;Description='Set Memory integrity off (restart required)'},
        [pscustomobject]@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';Name='EnableSmartScreen';Kind='DWord';Value=0;Description='Set Windows SmartScreen off'},
        [pscustomobject]@{Path='HKLM:\SOFTWARE\Policies\Microsoft\Edge';Name='SmartScreenEnabled';Kind='DWord';Value=0;Description='Set Edge SmartScreen off'}
    )
}

function Assert-SecurityRegistryEditable {
    param($Entry)
    if ($Entry.Name -ne 'Enabled') { return }
    foreach ($path in @('HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard',$Entry.Path)) {
        $locked=Get-RegistryState $path 'Locked'
        if ($locked.Exists -and $locked.Value -ne 0) { throw 'Memory integrity has a firmware/UEFI lock; no automatic change.' }
    }
    $policy=Get-RegistryState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'HypervisorEnforcedCodeIntegrity'
    if ($policy.Exists -and $policy.Value -ne 0) { throw 'Memory integrity is policy-managed; no automatic change.' }
}

function Get-SecurityPlan {
    $settings=@();$registry=@();$notices=@()
    $setter=Get-Command Set-MpPreference -ErrorAction SilentlyContinue
    if ($null -eq $setter -or $null -eq (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        $notices+='Defender controls unavailable - protection state not verified by this script'
    } else {
        try {
            $status=Get-MpComputerStatus -ErrorAction Stop
            if ($status.IsTamperProtected) {
                $notices+='Defender/tamper-protected settings: blocked by Tamper Protection'
            } else {
                $preferences=Get-MpPreference -ErrorAction Stop
                foreach ($entry in @(Get-DefenderSettingCatalog)) {
                    if ($setter.Parameters.ContainsKey($entry.Name) -and $preferences.PSObject.Properties.Name -contains $entry.Name) {
                        $before=$preferences.($entry.Name)
                        if ($null -eq $before) { $notices+="$($entry.Label): state unavailable"; continue }
                        if ($entry.Value -is [bool]) { $before=[bool]$before } else { $before=[int]$before }
                        $settings += [pscustomobject]@{Provider='Defender';Name=$entry.Name;Before=$before;After=$entry.Value;Label=$entry.Label}
                    } else { $notices+="$($entry.Label): control unavailable" }
                }
            }
        } catch { $notices+='Defender controls unavailable or access denied - no Defender changes planned' }
    }
    try {
        foreach ($profile in @(Get-NetFirewallProfile -PolicyStore PersistentStore -ErrorAction Stop)) {
            if ($profile.Name -in @('Domain','Private','Public') -and $profile.Enabled.ToString() -in @('True','False')) {
                $settings += [pscustomobject]@{Provider='Firewall';Name=$profile.Name;Before=$profile.Enabled.ToString();After='False';Label="Windows Firewall ($($profile.Name))"}
            }
        }
    } catch { $notices+='Windows Firewall configuration unavailable - no firewall changes planned' }
    foreach ($entry in @(Get-SecurityRegistryCatalog)) {
        try {
            Assert-SecurityRegistryEditable $entry
            if ($entry.Name -eq 'EnableSmartScreen' -and -not (Test-PolicyEdition (Get-WindowsInfo))) {
                $notices+='Windows SmartScreen policy unavailable on this edition'; continue
            }
            $registry += [pscustomobject]@{
                Path=$entry.Path;Name=$entry.Name;Description=$entry.Description
                Before=(Get-RegistryState $entry.Path $entry.Name)
                Desired=[pscustomobject]@{Exists=$true;Kind=$entry.Kind;Value=$entry.Value}
            }
        } catch { $notices+=$_.Exception.Message }
    }
    $notices += @(
        'Tamper Protection: not changeable through normal PowerShell; use Windows Security or its management policy',
        'Third-party antivirus, ASR/Exploit Protection and Smart App Control: not changed',
        'Secure Boot, TPM, disk encryption, sign-in/credential protection and other core-isolation features: preserved'
    )
    [pscustomobject]@{Settings=$settings;Registry=$registry;Notices=$notices}
}

function Assert-SecuritySetting {
    param([string]$Provider,[string]$Name,$Value)
    if ($Provider -eq 'Firewall') {
        if ($Name -notin @('Domain','Private','Public') -or $Value -notin @('True','False')) { throw 'Invalid firewall setting.' }
    } elseif ($Provider -eq 'Defender') {
        $matches=@(Get-DefenderSettingCatalog | Where-Object { $_.Name -eq $Name })
        if ($matches.Count -ne 1) { throw 'Unknown Defender setting.' }
        if ($matches[0].Value -is [bool]) {
            if ($Value -isnot [bool]) { throw 'Invalid Defender boolean.' }
        } elseif ($Value -isnot [int] -or $Value -lt 0 -or $Value -gt 6) { throw 'Invalid Defender enum.' }
    } else { throw 'Unknown security provider.' }
}

function Get-SecurityValue {
    param([string]$Provider,[string]$Name)
    if ($Provider -eq 'Firewall') {
        return (Get-NetFirewallProfile -Name $Name -PolicyStore PersistentStore -ErrorAction Stop).Enabled.ToString()
    }
    $entry=@(Get-DefenderSettingCatalog | Where-Object { $_.Name -eq $Name })[0]
    $value=(Get-MpPreference -ErrorAction Stop).$Name
    if ($entry.Value -is [bool]) { return [bool]$value }
    return [int]$value
}

function Set-SecurityValue {
    param([string]$Provider,[string]$Name,$Value)
    Assert-SecuritySetting $Provider $Name $Value
    if ($Provider -eq 'Firewall') {
        Set-NetFirewallProfile -Name $Name -PolicyStore PersistentStore -Enabled $Value -ErrorAction Stop
        return
    }
    if ((Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected) { throw 'Tamper Protection blocks this change; no bypass attempted.' }
    $arguments=@{ErrorAction='Stop'}; $arguments[$Name]=$Value
    Set-MpPreference @arguments
}

function Test-SecurityValueEffective {
    param([string]$Provider,[string]$Name,$Value)
    if ((Get-SecurityValue $Provider $Name) -ne $Value) { return $false }
    if ($Provider -eq 'Firewall') {
        return ((Get-NetFirewallProfile -Name $Name -PolicyStore ActiveStore -ErrorAction Stop).Enabled.ToString() -eq $Value)
    }
    if ($Name -eq 'DisableRealtimeMonitoring') {
        return ((Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled -eq (-not $Value))
    }
    return $true
}

function Set-BackedSecuritySetting {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($Entry)
    Assert-SecuritySetting $Entry.Provider $Entry.Name $Entry.After
    $current=Get-SecurityValue $Entry.Provider $Entry.Name
    if ($current -ne $Entry.Before) { throw 'Security setting changed since the checklist; skipped.' }
    if ($current -eq $Entry.After) {
        if (-not (Test-SecurityValueEffective $Entry.Provider $Entry.Name $Entry.After)) { throw 'Stored preference is off, but effective protection is still on or policy-controlled.' }
        Write-Host "Already configured off: $($Entry.Label)" -ForegroundColor Green; return
    }
    if (-not $PSCmdlet.ShouldProcess($Entry.Label,'Disable the listed security protection')) { return }
    Start-Journal
    if ($script:Journal.PSObject.Properties.Name -notcontains 'SecurityChanges') {
        $script:Journal | Add-Member NoteProperty SecurityChanges @()
    }
    $existing=@($script:Journal.SecurityChanges | Where-Object { $_.Provider -eq $Entry.Provider -and $_.Name -eq $Entry.Name })
    if ($existing.Count -gt 0) { $change=$existing[0];$change.Status='Pending' }
    else {
        $change=[pscustomobject]@{Provider=$Entry.Provider;Name=$Entry.Name;Before=$current;After=$Entry.After;Status='Pending';Error=$null}
        $script:Journal.SecurityChanges=@($script:Journal.SecurityChanges)+$change
    }
    Save-Journal
    try {
        Set-SecurityValue $Entry.Provider $Entry.Name $Entry.After
        if (-not (Test-SecurityValueEffective $Entry.Provider $Entry.Name $Entry.After)) { throw 'Change blocked, overridden or not effective; protection is not confirmed off.' }
        $change.Status='Applied';$change.Error=$null
    } catch {
        $change.Status='Failed';$change.Error=$_.Exception.Message;Save-Journal;throw
    }
    Save-Journal
    Write-Host "Configured off: $($Entry.Label)" -ForegroundColor Green
}

function Test-SecurityJournal {
    param($Journal)
    if ($Journal.PSObject.Properties.Name -notcontains 'SecurityChanges') { return }
    foreach ($entry in @($Journal.SecurityChanges)) {
        Assert-SecuritySetting $entry.Provider $entry.Name $entry.Before
        Assert-SecuritySetting $entry.Provider $entry.Name $entry.After
    }
}

function Restore-SecuritySettings {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if ($script:Journal.PSObject.Properties.Name -notcontains 'SecurityChanges') { return }
    foreach ($entry in @($script:Journal.SecurityChanges)) {
        if ($entry.Status -eq 'Restored') { continue }
        try {
            $current=Get-SecurityValue $entry.Provider $entry.Name
            if ($current -ne $entry.Before -and $current -ne $entry.After) { throw 'Changed since Disable; preserved.' }
            if ($PSCmdlet.ShouldProcess("$($entry.Provider): $($entry.Name)",'Restore saved security setting')) {
                if ($current -ne $entry.Before) { Set-SecurityValue $entry.Provider $entry.Name $entry.Before }
                if (-not (Test-SecurityValueEffective $entry.Provider $entry.Name $entry.Before)) { throw 'Security restore not effective; manual attention required.' }
                $entry.Status='Restored';Save-Journal
                Write-Host "Restored security setting: $($entry.Name)" -ForegroundColor Green
            }
        } catch { Write-Warning "Security setting $($entry.Name) needs attention: $($_.Exception.Message)" }
    }
}
