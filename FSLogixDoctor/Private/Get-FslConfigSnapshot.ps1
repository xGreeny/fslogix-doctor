function Get-FslConfigSnapshot {
    <#
    .SYNOPSIS
        Reads the live FSLogix configuration into a plain hashtable snapshot.
    .DESCRIPTION
        Collects the Profiles and ODFC registry settings, install/service state and
        (when available) Microsoft Defender path exclusions. Test-FslConfiguration
        evaluates such a snapshot, which keeps the rule logic unit-testable against
        fixture snapshots.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]]$ProfilesKeyPath = @(
            # Policies hive first: per Windows policy precedence it wins over the
            # local key, and the merge below is first-path-wins.
            'HKLM:\SOFTWARE\Policies\FSLogix\Profiles'
            'HKLM:\SOFTWARE\FSLogix\Profiles'
        ),

        [string[]]$OdfcKeyPath = @(
            'HKLM:\SOFTWARE\Policies\FSLogix\ODFC'
            'HKLM:\SOFTWARE\FSLogix\ODFC'
        ),

        [string[]]$LoggingKeyPath = @('HKLM:\SOFTWARE\FSLogix\Logging'),

        [string[]]$AppsKeyPath = @('HKLM:\SOFTWARE\FSLogix\Apps')
    )

    if ((-not [Environment]::Is64BitProcess) -and [Environment]::Is64BitOperatingSystem) {
        Write-Warning 'This is a 32-bit PowerShell process on 64-bit Windows: WOW64 redirection hides HKLM:\SOFTWARE\FSLogix and the results below will look like FSLogix is unconfigured. Run from 64-bit PowerShell.'
    }

    $readKey = {
        param([string[]]$paths)
        $merged = $null
        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            if ($null -eq $merged) { $merged = @{} }
            $item = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
            if ($null -eq $item) { continue }
            foreach ($property in $item.PSObject.Properties) {
                if ($property.Name -like 'PS*') { continue }
                # First path in the list wins (policy/GPO precedence order).
                if (-not $merged.ContainsKey($property.Name)) {
                    $merged[$property.Name] = $property.Value
                }
            }
        }
        $merged
    }

    $defenderExclusions = $null
    if (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue) {
        try {
            $defenderExclusions = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
        }
        catch {
            Write-Verbose "Could not read Defender exclusions: $($_.Exception.Message)"
        }
    }

    @{
        ComputerName       = $env:COMPUTERNAME
        Install            = Get-FslInstallInfo
        Profiles           = & $readKey $ProfilesKeyPath
        Odfc               = & $readKey $OdfcKeyPath
        Logging            = & $readKey $LoggingKeyPath
        Apps               = & $readKey $AppsKeyPath
        DefenderExclusions = $defenderExclusions
        VhdLocationsOnline = $null # pre-fill in fixture snapshots to skip live path probing
    }
}
