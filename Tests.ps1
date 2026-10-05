# Run: Invoke-Pester .\Tests.ps1
# Uses a random temporary HKCU key and Pester's temporary file directory.
# Never applies the optimizer to Windows, closes apps or touches real startup entries.
$optimizerPath = Join-Path $PSScriptRoot 'Gaming-Optimizer.ps1'
. $optimizerPath

Describe 'Gaming Optimizer scope and compatibility' {
    It 'parses with Windows PowerShell 5.1' {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($optimizerPath,[ref]$tokens,[ref]$errors)
        $errors.Count | Should Be 0
    }
    It 'keeps audio, USB, controller, security and launcher processes outside cleanup' {
        $names = @(Get-AppCatalog | ForEach-Object { $_.Processes })
        foreach ($name in @('audiodg','steam','steamwebhelper','ts3client_win64',
            'EpicGamesLauncher','EADesktop','UbisoftConnect','MsMpEng','lghub','iCUE',
            'RazerAppEngine','Razer Synapse','MSIAfterburner','DS4Windows','reWASD')) {
            ($names -contains $name) | Should Be $false
        }
    }
    It 'keeps Store, gaming dependencies and audio packages outside background restrictions' {
        $names = @(Get-BackgroundAppNames)
        foreach ($name in @('Microsoft.WindowsStore','Microsoft.GamingServices',
            'Microsoft.GamingApp','Microsoft.XboxIdentityProvider','Microsoft.VCLibs.140.00',
            'DolbyLaboratories.DolbyAccess','Microsoft.XboxDevices')) {
            ($names -contains $name) | Should Be $false
        }
    }
    It 'limits the GameDVR policy to supported Windows 10 editions' {
        @(Get-BaseSettings ([pscustomobject]@{Build=19045;Edition='Professional'}) | Where-Object Name -eq 'AllowGameDVR').Count | Should Be 1
        @(Get-BaseSettings ([pscustomobject]@{Build=26200;Edition='Professional'}) | Where-Object Name -eq 'AllowGameDVR').Count | Should Be 0
        @(Get-BaseSettings ([pscustomobject]@{Build=19045;Edition='Core'}) | Where-Object Name -eq 'AllowGameDVR').Count | Should Be 0
    }
    It 'rejects restore targets outside the precise allowlist' {
        Test-RestoreTarget 'HKLM:\SYSTEM\CurrentControlSet\Services\Audiosrv' 'Start' | Should Be $false
        Test-RestoreTarget 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'RazerAppEngine' | Should Be $false
        Test-RestoreTarget 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'Overwolf' | Should Be $true
    }
    It 'contains no uninstall, driver removal, exclusions or boot alteration commands' {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($optimizerPath,[ref]$tokens,[ref]$errors)
        $commands = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() })
        foreach ($name in @('Remove-AppxPackage','Remove-AppxProvisionedPackage',
            'Add-MpPreference','bcdedit','Disable-ScheduledTask')) {
            ($commands -contains $name) | Should Be $false
        }
    }
}

Describe 'Backup, preview and restore with isolated registry fixtures' {
    BeforeEach {
        $script:TestKey = 'HKCU:\SOFTWARE\GamingOptimizerTest_' + [guid]::NewGuid().ToString('N')
        $null = New-Item -Path $script:TestKey
        $script:Journal = $null; $script:JournalPath = $null
        $script:BackupRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        # Restore's production allowlist is tested above. Integration tests only
        # permit this single randomly generated fixture key.
        Mock Test-RestoreTarget { param($Path,$Name) $Path -eq $script:TestKey }
    }
    AfterEach {
        if ($script:TestKey -match '^HKCU:\\SOFTWARE\\GamingOptimizerTest_[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $script:TestKey -ErrorAction SilentlyContinue
        }
    }
    It 'makes no registry or backup changes during WhatIf' {
        Set-BackedSetting $script:TestKey 'Preview' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Preview fixture' -WhatIf
        (Get-RegistryState $script:TestKey 'Preview').Exists | Should Be $false
        ($null -eq $script:Journal) | Should Be $true
        (Test-Path -LiteralPath $script:BackupRoot) | Should Be $false
    }
    It 'saves the original before mutation and does not duplicate an already-set value' {
        $wanted = [pscustomobject]@{Exists=$true;Kind='DWord';Value=1}
        Set-BackedSetting $script:TestKey 'Setting' $wanted 'Fixture'
        Set-BackedSetting $script:TestKey 'Setting' $wanted 'Fixture again'
        $saved = Import-Clixml -LiteralPath $script:JournalPath
        @($saved.Changes).Count | Should Be 1
        $saved.Changes[0].Before.Exists | Should Be $false
        $saved.Changes[0].Status | Should Be 'Applied'
        (Test-StateEqual (Get-RegistryState $script:TestKey 'Setting') $wanted) | Should Be $true
    }
    It 'removes a previously absent value when restored and tolerates a repeated restore' {
        Set-BackedSetting $script:TestKey 'NewValue' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture'
        $backup = $script:JournalPath
        Restore-Settings -Path $backup
        Restore-Settings -Path $backup
        (Get-RegistryState $script:TestKey 'NewValue').Exists | Should Be $false
        (Import-Clixml -LiteralPath $backup).Changes[0].Status | Should Be 'Restored'
    }
    It 'restores exact data and types including unexpanded startup strings' {
        $states = @(
            [pscustomobject]@{Exists=$true;Kind='DWord';Value=7},
            [pscustomobject]@{Exists=$true;Kind='QWord';Value=[long]4294967296},
            [pscustomobject]@{Exists=$true;Kind='String';Value=''},
            [pscustomobject]@{Exists=$true;Kind='ExpandString';Value='%TEMP%\Example.exe --quiet'},
            [pscustomobject]@{Exists=$true;Kind='Binary';Value=[byte[]]@(0,2,128,255)},
            [pscustomobject]@{Exists=$true;Kind='MultiString';Value=[string[]]@('First','Second')}
        )
        for ($i=0; $i -lt $states.Count; $i++) {
            Set-RegistryState $script:TestKey "Type$i" $states[$i]
            Set-BackedSetting $script:TestKey "Type$i" ([pscustomobject]@{Exists=$false;Kind=$null;Value=$null}) 'Disable fixture startup value'
        }
        Restore-Settings -Path $script:JournalPath
        for ($i=0; $i -lt $states.Count; $i++) {
            (Test-StateEqual (Get-RegistryState $script:TestKey "Type$i") $states[$i]) | Should Be $true
        }
    }
    It 'preserves a value changed after Apply and reports the conflict' {
        Set-BackedSetting $script:TestKey 'Conflict' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture'
        Set-RegistryState $script:TestKey 'Conflict' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=9})
        Restore-Settings -Path $script:JournalPath -WarningVariable warnings
        (Get-RegistryState $script:TestKey 'Conflict').Value | Should Be 9
        ($warnings -join ' ') | Should Match 'Changed since Apply'
        (Import-Clixml -LiteralPath $script:JournalPath).Changes[0].Status | Should Be 'Applied'
    }
    It 'restores a pending journal entry after a simulated interruption' {
        Set-BackedSetting $script:TestKey 'Interrupted' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture'
        $script:Journal.Changes[0].Status = 'Pending'
        Save-Journal
        Restore-Settings -Path $script:JournalPath
        (Get-RegistryState $script:TestKey 'Interrupted').Exists | Should Be $false
    }
    It 'previews restore without touching either registry or journal' {
        Set-BackedSetting $script:TestKey 'PreviewRestore' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture'
        $hash = (Get-FileHash -LiteralPath $script:JournalPath).Hash
        Restore-Settings -Path $script:JournalPath -WhatIf
        (Get-RegistryState $script:TestKey 'PreviewRestore').Value | Should Be 1
        (Get-FileHash -LiteralPath $script:JournalPath).Hash | Should Be $hash
    }
    It 'refuses an unrelated-user journal without changing the registry' {
        Set-BackedSetting $script:TestKey 'Owner' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture'
        $script:Journal.UserSid = 'S-1-0-0'
        Save-Journal
        { Restore-Settings -Path $script:JournalPath } | Should Throw
        (Get-RegistryState $script:TestKey 'Owner').Value | Should Be 1
    }
    It 'fails before mutation if the original cannot be saved' {
        Mock Save-Journal { throw 'Simulated disk error' }
        { Set-BackedSetting $script:TestKey 'NoBackup' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1}) 'Fixture' } | Should Throw
        (Get-RegistryState $script:TestKey 'NoBackup').Exists | Should Be $false
    }
}

Describe 'Background policy preserves unrelated app choices' {
    BeforeEach {
        Mock Get-WindowsInfo { [pscustomobject]@{Build=26200;Edition='Professional'} }
        Mock Get-BackgroundCandidates { @([pscustomobject]@{Name='Microsoft.BingNews';PackageFamilyName='News_fixture'}) }
        Mock Get-RegistryState { [pscustomobject]@{Exists=$false;Kind=$null;Value=$null} }
        Mock Set-BackedSetting {}
    }
    It 'merges existing denials instead of replacing them' {
        Mock Get-RegistryState { [pscustomobject]@{Exists=$true;Kind='MultiString';Value=@('Existing_fixture')} } -ParameterFilter { $Name -eq 'LetAppsRunInBackground_ForceDenyTheseApps' }
        Set-BackgroundPolicy
        Assert-MockCalled Set-BackedSetting -Times 1 -Exactly -Scope It -ParameterFilter {
            $Name -eq 'LetAppsRunInBackground_ForceDenyTheseApps' -and
            $Desired.Value -contains 'Existing_fixture' -and $Desired.Value -contains 'News_fixture'
        }
    }
    It 'skips policy changes on Windows Home' {
        Mock Get-WindowsInfo { [pscustomobject]@{Build=26200;Edition='Core'} }
        Set-BackgroundPolicy
        Assert-MockCalled Set-BackedSetting -Times 0 -Exactly -Scope It
    }
    It 'skips apps with explicit allow exceptions' {
        Mock Get-RegistryState { [pscustomobject]@{Exists=$true;Kind='MultiString';Value=@('News_fixture')} } -ParameterFilter { $Name -eq 'LetAppsRunInBackground_ForceAllowTheseApps' }
        Set-BackgroundPolicy
        Assert-MockCalled Set-BackedSetting -Times 0 -Exactly -Scope It
    }
    It 'preserves an existing global forced policy' {
        Mock Get-RegistryState { [pscustomobject]@{Exists=$true;Kind='DWord';Value=1} } -ParameterFilter { $Name -eq 'LetAppsRunInBackground' }
        Set-BackgroundPolicy
        Assert-MockCalled Set-BackedSetting -Times 0 -Exactly -Scope It
    }
}

Describe 'Two-action profile lifecycle' {
    BeforeEach {
        $script:TestKey = 'HKCU:\SOFTWARE\GamingOptimizerTest_' + [guid]::NewGuid().ToString('N')
        $null = New-Item -Path $script:TestKey
        $script:ProfileFolder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:BackupRoot = Join-Path $script:ProfileFolder 'Backups'
        $script:ActiveProfilePath = Join-Path $script:ProfileFolder 'ActiveProfile.txt'
        $script:Journal = $null; $script:JournalPath = $null
        Set-RegistryState $script:TestKey 'Setting' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=7})
        Mock Test-RestoreTarget { param($Path,$Name) $Path -eq $script:TestKey }
        Mock Get-BaseSettings { @([pscustomobject]@{Path=$script:TestKey;Name='Setting';Kind='DWord';Value=0;Description='Fixture setting'}) }
        Mock Get-StartupCandidates { @() }
        Mock Get-BackgroundCandidates { @() }
        Mock Get-ServicePlan { @() }
        Mock Get-SessionCandidates { @() }
        Mock Get-SecurityPlan { [pscustomobject]@{Settings=@();Registry=@();Notices=@()} }
        Mock Confirm-GamingPlan { $true }
        Mock Set-BackgroundPolicy {}
        Mock Invoke-SessionCleanup {}
    }
    AfterEach {
        if ($script:TestKey -match '^HKCU:\\SOFTWARE\\GamingOptimizerTest_[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $script:TestKey -ErrorAction SilentlyContinue
        }
    }
    It 'combines all supported steps and automatically restores the original profile' {
        Invoke-DisableAll
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 0
        (Test-Path -LiteralPath $script:ActiveProfilePath) | Should Be $true
        Assert-MockCalled Set-BackgroundPolicy -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-SessionCleanup -Times 1 -Exactly -Scope It -ParameterFilter {
            $Force -and $Groups.Count -eq 4 -and $Groups -contains 'Chat' -and $Groups -contains 'Recorder'
        }
        $originalBackup = $script:JournalPath
        Invoke-EnableAll
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 7
        (Test-Path -LiteralPath $script:ActiveProfilePath) | Should Be $false
        (Test-Path -LiteralPath $originalBackup) | Should Be $true
    }
    It 'keeps the first baseline after repeated disable and drift' {
        Invoke-DisableAll
        $originalBackup = $script:JournalPath
        Invoke-DisableAll
        Set-RegistryState $script:TestKey 'Setting' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=5})
        Invoke-DisableAll
        $script:JournalPath | Should Be $originalBackup
        @($script:Journal.Changes).Count | Should Be 1
        $script:Journal.Changes[0].Before.Value | Should Be 7
        Invoke-EnableAll
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 7
    }
    It 'retains an active backup when re-enable encounters a conflict' {
        Invoke-DisableAll
        Set-RegistryState $script:TestKey 'Setting' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=9})
        Invoke-EnableAll
        (Test-Path -LiteralPath $script:ActiveProfilePath) | Should Be $true
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 9
    }
    It 'creates no profile or report in preview mode' {
        Invoke-DisableAll -WhatIf
        (Test-Path -LiteralPath $script:ProfileFolder) | Should Be $false
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 7
        Assert-MockCalled Invoke-SessionCleanup -Times 1 -Exactly -Scope It
    }
    It 'can re-enable a profile interrupted before its first mutation' {
        Open-AllProfile
        Invoke-EnableAll
        (Test-Path -LiteralPath $script:ActiveProfilePath) | Should Be $false
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 7
    }
    It 'does not use arbitrary older backups when no profile is active' {
        Invoke-EnableAll
        (Test-Path -LiteralPath $script:ProfileFolder) | Should Be $false
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 7
    }
    It 'creates a new baseline for the next disable cycle after re-enabling' {
        Invoke-DisableAll
        $firstBackup = $script:JournalPath
        Invoke-EnableAll
        Set-RegistryState $script:TestKey 'Setting' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=8})
        Invoke-DisableAll
        ($script:JournalPath -ne $firstBackup) | Should Be $true
        Invoke-EnableAll
        (Get-RegistryState $script:TestKey 'Setting').Value | Should Be 8
    }
}
