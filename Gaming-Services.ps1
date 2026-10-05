# Internal helpers. Loaded by Gaming-Optimizer.ps1; never run service changes here.

function Get-ServiceCatalog {
    # Deliberately small, exact allowlist. Dependent services precede their parents.
    @(
        [pscustomobject]@{Name='Fax';Benefit='Prevents the unused fax service starting.';Tradeoff='Fax sending and receiving unavailable.'},
        [pscustomobject]@{Name='WMPNetworkSvc';Benefit='Removes legacy media-library sharing work.';Tradeoff='Windows Media Player DLNA sharing unavailable; local audio still works.'},
        [pscustomobject]@{Name='MapsBroker';Benefit='Prevents offline-map management work.';Tradeoff='Downloaded/offline Windows maps unavailable.'},
        [pscustomobject]@{Name='RetailDemo';Benefit='Prevents retail demonstration features running.';Tradeoff='Store demonstration mode unavailable.'},
        [pscustomobject]@{Name='DiagTrack';Benefit='Reduces diagnostic collection and transmission from this service.';Tradeoff='Connected diagnostic/feedback features reduced; this is not all Windows telemetry.'},
        [pscustomobject]@{Name='WSearch';Benefit='Removes background file-indexing work while disabled.';Tradeoff='Indexed file/Outlook searches can be slower or unavailable.'},
        [pscustomobject]@{Name='Spooler';Benefit='Prevents unused print-spooling work.';Tradeoff='Printing, including Print to PDF, unavailable.'}
    )
}

function Assert-ManagedServiceName {
    param([string]$Name)
    if (@(Get-ServiceCatalog | ForEach-Object { $_.Name }) -notcontains $Name) {
        throw "Service '$Name' is outside the reviewed list and cannot be changed."
    }
}

function Get-ManagedServiceState {
    param([string]$Name)
    Assert-ManagedServiceName $Name
    $controller = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $controller) { return $null }
    $info = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
    if ($null -eq $info) { throw "Could not read configuration for $Name." }
    [pscustomobject]@{
        Name=$Name; DisplayName=$controller.DisplayName
        StartMode=[string]$info.StartMode; Status=$controller.Status.ToString()
        Running=($controller.Status -eq 'Running'); Type=[int]$controller.ServiceType
        DelayedAutoStart=(Get-RegistryState "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" 'DelayedAutoStart')
        Dependents=@($controller.DependentServices | ForEach-Object { $_.Name })
    }
}

function Get-ServicePlan {
    param([string[]]$Keep = @())
    $catalog = @(Get-ServiceCatalog)
    $allowed = @($catalog | Where-Object { $Keep -notcontains $_.Name } | ForEach-Object { $_.Name })
    foreach ($item in $catalog) {
        $state = Get-ManagedServiceState $item.Name
        $decision = 'Disable'; $reason = $item.Benefit
        if ($Keep -contains $item.Name) { $decision='Preserve'; $reason='Requested service exception.' }
        elseif ($null -eq $state) { $decision='Not installed'; $reason='No change needed.' }
        elseif ($state.StartMode -eq 'Disabled' -and -not $state.Running) { $decision='Already disabled'; $reason='No new performance benefit from changing this again.' }
        elseif (($state.Type -band 48) -eq 0) { $decision='Preserve'; $reason='This is not an ordinary Win32 service.' }
        elseif ($state.Status -notin @('Running','Stopped') -or $state.StartMode -notin @('Auto','Manual')) {
            $decision='Preserve'; $reason='Transitional or unusual service state; no automatic change.'
        } elseif (@($state.Dependents | Where-Object { $allowed -notcontains $_ }).Count -gt 0) {
            $decision='Preserve'; $reason='A service outside the disable list depends on it: ' + ($state.Dependents -join ', ')
        }
        [pscustomobject]@{Name=$item.Name;State=$state;Decision=$decision;Reason=$reason;Benefit=$item.Benefit;Tradeoff=$item.Tradeoff}
    }
}

function Test-ServiceStateEqual {
    param($Left,$Right)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    ($Left.StartMode -eq $Right.StartMode -and $Left.Status -eq $Right.Status -and
        (Test-StateEqual $Left.DelayedAutoStart $Right.DelayedAutoStart))
}

function Set-ManagedServiceStartup {
    param([string]$Name, [ValidateSet('Auto','Manual','Disabled')][string]$StartMode)
    Assert-ManagedServiceName $Name
    $types = @{Auto='Automatic';Manual='Manual';Disabled='Disabled'}
    Set-Service -Name $Name -StartupType $types[$StartMode] -ErrorAction Stop
}

function Set-ManagedServiceRunning {
    param([string]$Name,[bool]$Running)
    Assert-ManagedServiceName $Name
    $controller = Get-Service -Name $Name -ErrorAction Stop
    if ($Running -and $controller.Status -ne 'Running') {
        $controller.Start()
        $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running,[TimeSpan]::FromSeconds(10))
    } elseif (-not $Running -and $controller.Status -ne 'Stopped') {
        # Never use Force: an unreviewed dependent must not be stopped indirectly.
        if (@($controller.DependentServices | Where-Object { $_.Status -ne 'Stopped' }).Count -gt 0) {
            throw "$Name still has active dependent services. It was not stopped."
        }
        $controller.Stop()
        $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(10))
    }
}

function Set-BackedService {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($Entry,[string[]]$Keep = @())
    Assert-ManagedServiceName $Entry.Name
    if ($Entry.Decision -ne 'Disable') { return }
    $current = Get-ManagedServiceState $Entry.Name
    if (-not (Test-ServiceStateEqual $current $Entry.State)) {
        throw "$($Entry.Name) changed since the preview; skipped. Review a fresh plan."
    }
    $allowed = @(Get-ServiceCatalog | Where-Object { $Keep -notcontains $_.Name } | ForEach-Object { $_.Name })
    if (@($current.Dependents | Where-Object { $allowed -notcontains $_ }).Count -gt 0) {
        throw "A new dependent requires $($Entry.Name); skipped."
    }
    if (-not $PSCmdlet.ShouldProcess($Entry.Name,'Disable startup and stop this optional service')) { return }
    Start-Journal
    if ($script:Journal.PSObject.Properties.Name -notcontains 'ServiceChanges') {
        $script:Journal | Add-Member NoteProperty ServiceChanges @()
    }
    $existing = @($script:Journal.ServiceChanges | Where-Object { $_.Name -eq $Entry.Name })
    if ($existing.Count -gt 0) { $change=$existing[0]; $change.Status='Pending' }
    else {
        $change=[pscustomobject]@{Name=$Entry.Name;Before=$current;Status='Pending';Error=$null}
        $script:Journal.ServiceChanges=@($script:Journal.ServiceChanges)+$change
    }
    Save-Journal
    try {
        Set-ManagedServiceStartup $Entry.Name 'Disabled'
        Set-ManagedServiceRunning $Entry.Name $false
        $after=Get-ManagedServiceState $Entry.Name
        if ($after.StartMode -ne 'Disabled' -or $after.Status -ne 'Stopped') { throw 'Service did not reach the requested state.' }
        $change.Status='Applied'; $change.Error=$null
    } catch {
        $change.Status='Failed'; $change.Error=$_.Exception.Message
        Save-Journal
        throw
    }
    Save-Journal
    Write-Host "Disabled service: $($Entry.Name)" -ForegroundColor Green
}

function Test-ServiceJournal {
    param($Journal)
    if ($Journal.PSObject.Properties.Name -notcontains 'ServiceChanges') { return }
    foreach ($entry in @($Journal.ServiceChanges)) {
        Assert-ManagedServiceName $entry.Name
        if ($entry.Before.StartMode -notin @('Auto','Manual','Disabled') -or
            $entry.Before.Status -notin @('Running','Stopped') -or $entry.Before.Running -isnot [bool]) {
            throw 'Invalid service backup state.'
        }
        $delay = $entry.Before.DelayedAutoStart
        if ($delay.Exists -isnot [bool] -or ($delay.Exists -and $delay.Kind -ne 'DWord')) {
            throw 'Invalid delayed-start backup state.'
        }
    }
}

function Restore-Services {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if ($script:Journal.PSObject.Properties.Name -notcontains 'ServiceChanges') { return }
    $entries=@($script:Journal.ServiceChanges); [array]::Reverse($entries)
    foreach ($entry in $entries) {
        if ($entry.Status -eq 'Restored') { continue }
        try {
            Assert-ManagedServiceName $entry.Name
            $current=Get-ManagedServiceState $entry.Name
            if ($null -eq $current) { throw 'The service is no longer installed.' }
            if ($current.StartMode -notin @('Disabled',$entry.Before.StartMode) -or
                $current.Status -notin @('Running','Stopped') -or
                -not (Test-StateEqual $current.DelayedAutoStart $entry.Before.DelayedAutoStart)) {
                throw 'Configuration changed after disabling; left untouched.'
            }
            if (-not $entry.Before.Running -and $current.Running) {
                throw 'The initially stopped service is now running; left untouched.'
            }
            if ($PSCmdlet.ShouldProcess($entry.Name,'Restore original service startup and running state')) {
                Set-ManagedServiceStartup $entry.Name $entry.Before.StartMode
                # Set-Service does not set delayed automatic start; restore its exact original value.
                Set-RegistryState "HKLM:\SYSTEM\CurrentControlSet\Services\$($entry.Name)" 'DelayedAutoStart' $entry.Before.DelayedAutoStart
                Set-ManagedServiceRunning $entry.Name $entry.Before.Running
                if (-not (Test-ServiceStateEqual (Get-ManagedServiceState $entry.Name) $entry.Before)) {
                    throw 'Service restore verification failed.'
                }
                $entry.Status='Restored'; Save-Journal
                Write-Host "Restored service: $($entry.Name)" -ForegroundColor Green
            }
        } catch { Write-Warning "Service $($entry.Name) needs attention: $($_.Exception.Message)" }
    }
}
