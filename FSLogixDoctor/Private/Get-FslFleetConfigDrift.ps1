function Get-FslFleetConfigDrift {
    <#
    .SYNOPSIS
        Compares the core FSLogix Profiles registry values across fleet hosts
        and emits one Warning finding per drifting value. Fleet mode compares
        findings, not raw settings - two hosts with different SizeInMBs, each
        unremarkable on its own, only surface here.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComputerName
    )

    $keys = @(
        'Enabled', 'VHDLocations', 'CCDLocations', 'SizeInMBs', 'IsDynamic', 'VolumeType',
        'DeleteLocalProfileWhenVHDShouldApply', 'PreventLoginWithFailure', 'PreventLoginWithTempProfile',
        'LockedRetryCount', 'LockedRetryInterval', 'FlipFlopProfileDirectoryName'
    )

    $perHost = [ordered]@{}
    foreach ($computer in $ComputerName) {
        $values = $null
        try {
            if ($computer -in @($env:COMPUTERNAME, 'localhost', '.')) {
                $values = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction Stop
            }
            else {
                $values = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
                    Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            # Unreachable hosts are already reported by the fleet loop.
            continue
        }
        $perHost[$computer] = $values
    }
    if ($perHost.Keys.Count -lt 2) { return }

    $driftCount = 0
    foreach ($key in $keys) {
        $valueByHost = [ordered]@{}
        foreach ($computer in $perHost.Keys) {
            $raw = $null
            if ($perHost[$computer]) { $raw = $perHost[$computer].$key }
            $display = '<not set>'
            if ($null -ne $raw -and @($raw).Count -gt 0) { $display = (@($raw) -join ';') }
            $valueByHost[$computer] = $display
        }
        $distinct = @($valueByHost.Values | Select-Object -Unique)
        if ($distinct.Count -gt 1) {
            $driftCount++
            New-FslFinding -Category Configuration -Check 'Configuration drift' -Severity Warning `
                -Target (@($perHost.Keys) -join ', ') `
                -Message ("Registry value '{0}' differs across the fleet - the same user gets different behavior depending on the host." -f $key) `
                -Evidence ((@($valueByHost.Keys) | ForEach-Object { '{0}={1}' -f $_, $valueByHost[$_] }) -join ' | ') `
                -Recommendation 'Align the value across all session hosts (golden image, GPO or deployment script) unless the difference is deliberate.' `
                -HelpUri 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings'
        }
    }
    if ($driftCount -eq 0) {
        New-FslFinding -Category Configuration -Check 'Configuration drift' -Severity Pass `
            -Target (@($perHost.Keys) -join ', ') `
            -Message ("The {0} core FSLogix settings are identical across {1} hosts." -f $keys.Count, $perHost.Keys.Count)
    }
}
