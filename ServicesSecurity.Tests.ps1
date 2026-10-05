# Service/security backends are mocked. This file never changes real services,
# Defender, firewall, core isolation, firmware, drivers or registry settings.
. (Join-Path $PSScriptRoot 'Gaming-Optimizer.ps1')

Describe 'Reviewed service changes and exact recovery' {
    BeforeEach {
        $script:Journal=$null;$script:JournalPath=$null
        $script:BackupRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:FakeService=[pscustomobject]@{
            Name='MapsBroker';DisplayName='Test service';StartMode='Auto';Status='Running'
            Running=$true;Type=16;Dependents=@()
            DelayedAutoStart=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}
        }
        Mock Get-ManagedServiceState {
            param($Name)
            if ($Name -ne 'MapsBroker') { return $null }
            $script:FakeService | Select-Object *
        }
        Mock Set-ManagedServiceStartup { param($Name,$StartMode) $script:FakeService.StartMode=$StartMode }
        Mock Set-ManagedServiceRunning {
            param($Name,$Running)
            $script:FakeService.Running=$Running
            if ($Running) { $script:FakeService.Status='Running' } else { $script:FakeService.Status='Stopped' }
        }
        Mock Set-RegistryState {
            param($Path,$Name,$State)
            if ($Name -ne 'DelayedAutoStart') { throw 'Unexpected registry write in service fixture' }
            $script:FakeService.DelayedAutoStart=$State
        }
    }
    It 'has no audio, input, networking, gaming, security or core OS services in its list' {
        $names=@(Get-ServiceCatalog | ForEach-Object { $_.Name })
        foreach ($name in @('Audiosrv','AudioEndpointBuilder','Dhcp','Dnscache','WlanSvc','BFE','mpssvc',
            'hidserv','PlugPlay','bthserv','BTAGService','BthAvctpSvc','XboxGipSvc','GamingServices',
            'XblAuthManager','XblGameSave','WinDefend','SecurityHealthService','RpcSs','SysMain')) {
            ($names -contains $name) | Should Be $false
            { Assert-ManagedServiceName $name } | Should Throw
        }
    }
    It 'saves startup, delayed-start and running state before disabling and restores them' {
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        Set-BackedService -Entry $entry
        $script:FakeService.StartMode | Should Be 'Disabled'
        $script:FakeService.Running | Should Be $false
        $saved=Import-Clixml -LiteralPath $script:JournalPath
        $saved.ServiceChanges[0].Before.StartMode | Should Be 'Auto'
        $saved.ServiceChanges[0].Before.Running | Should Be $true
        Restore-Settings -Path $script:JournalPath
        $script:FakeService.StartMode | Should Be 'Auto'
        $script:FakeService.Running | Should Be $true
        $script:FakeService.DelayedAutoStart.Value | Should Be 1
        $script:Journal.ServiceChanges[0].Status | Should Be 'Restored'
    }
    It 'restores an originally stopped service without starting it' {
        $script:FakeService.StartMode='Manual';$script:FakeService.Running=$false;$script:FakeService.Status='Stopped'
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        Set-BackedService -Entry $entry
        Restore-Settings -Path $script:JournalPath
        $script:FakeService.StartMode | Should Be 'Manual'
        $script:FakeService.Running | Should Be $false
        Assert-MockCalled Set-ManagedServiceRunning -Times 0 -Exactly -Scope It -ParameterFilter { $Running }
    }
    It 'preserves services required by any service outside the reviewed list' {
        $script:FakeService.Dependents=@('Audiosrv')
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        $entry.Decision | Should Be 'Preserve'
        Set-BackedService -Entry $entry
        Assert-MockCalled Set-ManagedServiceStartup -Times 0 -Exactly -Scope It
    }
    It 'skips a service whose state changed after preview' {
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        $script:FakeService.StartMode='Manual'
        { Set-BackedService -Entry $entry } | Should Throw
        Assert-MockCalled Set-ManagedServiceStartup -Times 0 -Exactly -Scope It
    }
    It 'can recover when startup was disabled but stopping failed' {
        Mock Set-ManagedServiceRunning { throw 'Simulated service stop failure' }
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        { Set-BackedService -Entry $entry } | Should Throw
        $script:Journal.ServiceChanges[0].Status | Should Be 'Failed'
        $script:FakeService.StartMode | Should Be 'Disabled'
        Mock Set-ManagedServiceRunning {}
        Restore-Settings -Path $script:JournalPath
        $script:FakeService.StartMode | Should Be 'Auto'
        $script:Journal.ServiceChanges[0].Status | Should Be 'Restored'
    }
    It 'does not change services if the backup cannot be saved' {
        Mock Save-Journal { throw 'Simulated disk error' }
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        { Set-BackedService -Entry $entry } | Should Throw
        Assert-MockCalled Set-ManagedServiceStartup -Times 0 -Exactly -Scope It
    }
    It 'does not change services or create backups during preview' {
        $entry=@(Get-ServicePlan | Where-Object Name -eq 'MapsBroker')[0]
        Set-BackedService -Entry $entry -WhatIf
        Assert-MockCalled Set-ManagedServiceStartup -Times 0 -Exactly -Scope It
        (Test-Path -LiteralPath $script:BackupRoot) | Should Be $false
    }
}

Describe 'Security setting recovery and verification' {
    BeforeEach {
        $script:Journal=$null;$script:JournalPath=$null
        $script:BackupRoot=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:FakeSecurity='True'
        $script:SecurityEntry=[pscustomobject]@{Provider='Firewall';Name='Public';Before='True';After='False';Label='Test firewall'}
        Mock Get-SecurityValue { $script:FakeSecurity }
        Mock Set-SecurityValue { param($Provider,$Name,$Value) $script:FakeSecurity=$Value }
        Mock Test-SecurityValueEffective { param($Provider,$Name,$Value) $script:FakeSecurity -eq $Value }
    }
    It 'restores the original security state rather than enabling an arbitrary default' {
        Set-BackedSecuritySetting $script:SecurityEntry
        $script:FakeSecurity | Should Be 'False'
        Restore-Settings -Path $script:JournalPath
        $script:FakeSecurity | Should Be 'True'
        $script:Journal.SecurityChanges[0].Status | Should Be 'Restored'
    }
    It 'records ineffective changes as failed, never as successful disables' {
        Mock Test-SecurityValueEffective { $false }
        { Set-BackedSecuritySetting $script:SecurityEntry } | Should Throw
        $saved=Import-Clixml -LiteralPath $script:JournalPath
        $saved.SecurityChanges[0].Status | Should Be 'Failed'
        $saved.SecurityChanges[0].Before | Should Be 'True'
    }
    It 'makes no security change if the value changed after preview' {
        $script:FakeSecurity='False'
        { Set-BackedSecuritySetting $script:SecurityEntry } | Should Throw
        Assert-MockCalled Set-SecurityValue -Times 0 -Exactly -Scope It
    }
    It 'rejects unknown providers, settings and invalid saved types' {
        { Assert-SecuritySetting 'Defender' 'ExclusionPath' 'C:\' } | Should Throw
        { Assert-SecuritySetting 'Firewall' 'All' 'False' } | Should Throw
        { Assert-SecuritySetting 'Defender' 'DisableRealtimeMonitoring' 'True' } | Should Throw
    }
    It 'does not create backups or change security during preview' {
        Set-BackedSecuritySetting $script:SecurityEntry -WhatIf
        Assert-MockCalled Set-SecurityValue -Times 0 -Exactly -Scope It
        (Test-Path -LiteralPath $script:BackupRoot) | Should Be $false
    }
    It 'does not change security if its snapshot cannot be saved' {
        Mock Save-Journal { throw 'Simulated disk error' }
        { Set-BackedSecuritySetting $script:SecurityEntry } | Should Throw
        Assert-MockCalled Set-SecurityValue -Times 0 -Exactly -Scope It
    }
    It 'refuses a memory-integrity change when a UEFI lock is present' {
        Mock Get-RegistryState { [pscustomobject]@{Exists=$true;Kind='DWord';Value=1} }
        $entry=@(Get-SecurityRegistryCatalog | Where-Object Name -eq 'Enabled')[0]
        { Assert-SecurityRegistryEditable $entry } | Should Throw
    }
}

Describe 'Checklist and confirmation before mutation' {
    BeforeEach {
        $script:EmptyPlan=[pscustomobject]@{Settings=@();Startup=@();BackgroundPackages=@();BackgroundPolicyBefore=@();Services=@();Processes=@();Security=@();Notices=@();Created='fixture'}
        Mock Get-GamingPlan { $script:EmptyPlan }
        Mock Open-AllProfile {}
        Mock Set-BackedSetting {}
        Mock Set-BackedService {}
        Mock Set-BackedSecuritySetting {}
        Mock Set-BackgroundPolicy {}
        Mock Invoke-SessionCleanup {}
    }
    It 'requires an explicit YES after displaying the checklist' {
        Mock Read-Host { '' }
        Confirm-GamingPlan $script:EmptyPlan | Should Be $false
        Mock Read-Host { 'YES' }
        Confirm-GamingPlan $script:EmptyPlan | Should Be $true
    }
    It 'cancellation does not create a profile, close apps or change settings' {
        Mock Confirm-GamingPlan { $false }
        Invoke-DisableAll
        Assert-MockCalled Open-AllProfile -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-BackedService -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-BackedSecuritySetting -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-SessionCleanup -Times 0 -Exactly -Scope It
    }
    It 'displays a simple service checklist without individual service descriptions' {
        $script:EmptyPlan.Services=@([pscustomobject]@{Name='MapsBroker';State=$null;Decision='Disable';Benefit='PRIVATE TEST DESCRIPTION';Tradeoff='PRIVATE TEST TRADEOFF'})
        $text=Get-GamingPlanText $script:EmptyPlan | Out-String
        $text | Should Match '\[x\] Disable service: MapsBroker'
        $text | Should Not Match 'PRIVATE TEST'
        $text | Should Match 'Reducing background CPU'
    }
}
