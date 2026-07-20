function Test-FslConfiguration {
    <#
    .SYNOPSIS
        Sanity-checks the FSLogix configuration of a session host and flags the
        misconfigurations that cause temp profiles, login storms and data loss.
    .DESCRIPTION
        Evaluates the FSLogix install state and the Profiles/ODFC registry settings
        against a curated rule set distilled from real troubleshooting: unreachable
        VHDLocations, masked failures (temp profiles), local-profile collisions,
        double-attach conflicts between Profile and ODFC containers, missing
        antivirus exclusions and more.

        All checks are read-only. Returns FSLogixDoctor.Finding objects.
    .PARAMETER ConfigSnapshot
        A configuration snapshot hashtable. Defaults to the live local configuration;
        pass a fixture snapshot for testing or offline analysis.
    .EXAMPLE
        Test-FslConfiguration

        Checks the local session host.
    .EXAMPLE
        Test-FslConfiguration | Where-Object Severity -in 'Critical','Warning'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [hashtable]$ConfigSnapshot
    )

    if (-not $ConfigSnapshot) {
        $ConfigSnapshot = Get-FslConfigSnapshot
    }

    $target = $ConfigSnapshot.ComputerName
    $configHelp = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings'
    $profiles = $ConfigSnapshot.Profiles
    $odfc = $ConfigSnapshot.Odfc

    # --- Install state -------------------------------------------------------
    $install = $ConfigSnapshot.Install
    if (-not $install -or -not $install.Installed) {
        New-FslFinding -Category Environment -Check 'FSLogix installed' -Severity Critical -Target $target `
            -Message 'The FSLogix service (frxsvc) is not present on this host.' `
            -Recommendation 'Install the FSLogix Apps agent. Download: https://aka.ms/fslogix/download' `
            -HelpUri 'https://learn.microsoft.com/en-us/fslogix/how-to-install-fslogix'
        return
    }

    if ($install.ServiceStatus -ne 'Running') {
        New-FslFinding -Category Environment -Check 'FSLogix service running' -Severity Critical -Target $target `
            -Message ("The FSLogix service (frxsvc) is installed but its state is '{0}'." -f $install.ServiceStatus) `
            -Recommendation 'Start the service and check the Application event log for service crashes: Start-Service frxsvc'
    }
    else {
        New-FslFinding -Category Environment -Check 'FSLogix service running' -Severity Pass -Target $target `
            -Message 'The FSLogix service (frxsvc) is running.' `
            -Evidence ("Version: {0}" -f $install.Version)
    }

    if ($install.Version) {
        # Judge the version against the curated release table instead of
        # 'compare manually'. The table is a shipped snapshot - the finding
        # always names its AsOf date so an aging table stays honest.
        $releaseTable = Get-FslDataTable -Name Releases
        $newestCurated = $null
        try {
            $newestCurated = @($releaseTable.Releases | ForEach-Object { [version]$_.Version } | Sort-Object -Descending)[0]
        }
        catch { $newestCurated = $null }
        $installedVersion = $null
        try { $installedVersion = [version]$install.Version } catch { $installedVersion = $null }

        if ($newestCurated -and $installedVersion -and $installedVersion -lt $newestCurated) {
            New-FslFinding -Category Environment -Check 'FSLogix version' -Severity Warning -Target $target `
                -Message ("Installed FSLogix version {0} is older than the newest curated release {1} (release table as of {2})." -f $install.Version, $newestCurated, $releaseTable.AsOf) `
                -Recommendation 'Update FSLogix during the next maintenance window and review the release notes for fixed issues: https://learn.microsoft.com/en-us/fslogix/overview-release-notes' `
                -HelpUri 'https://learn.microsoft.com/en-us/fslogix/overview-release-notes'
        }
        elseif ($newestCurated -and $installedVersion) {
            New-FslFinding -Category Environment -Check 'FSLogix version' -Severity Info -Target $target `
                -Message ("Installed FSLogix version {0} matches or exceeds the newest curated release (release table as of {1})." -f $install.Version, $releaseTable.AsOf) `
                -Recommendation 'Spot-check the release notes for issues newer than the curated table: https://learn.microsoft.com/en-us/fslogix/overview-release-notes'
        }
        else {
            New-FslFinding -Category Environment -Check 'FSLogix version' -Severity Info -Target $target `
                -Message ("Installed FSLogix version: {0}." -f $install.Version) `
                -Recommendation 'Compare against the current release and known issues: https://learn.microsoft.com/en-us/fslogix/overview-release-notes'
        }
    }

    # --- Profiles configuration ----------------------------------------------
    if (-not $profiles) {
        New-FslFinding -Category Configuration -Check 'Profiles configured' -Severity Critical -Target $target `
            -Message 'No FSLogix Profiles configuration found (HKLM:\SOFTWARE\FSLogix\Profiles is missing or empty).' `
            -Recommendation 'Configure at least Enabled=1 and VHDLocations via GPO, Intune or registry.' `
            -HelpUri $configHelp
        return
    }

    if ($profiles['Enabled'] -ne 1) {
        $enabledValue = '<not set>'
        if ($null -ne $profiles['Enabled']) { $enabledValue = [string]$profiles['Enabled'] }
        New-FslFinding -Category Configuration -Check 'Profiles enabled' -Severity Critical -Target $target `
            -Message 'FSLogix profile containers are not enabled on this host.' `
            -Evidence ("Enabled = {0}" -f $enabledValue) `
            -Recommendation 'Set HKLM:\SOFTWARE\FSLogix\Profiles\Enabled (DWORD) = 1.' `
            -HelpUri $configHelp
    }
    else {
        New-FslFinding -Category Configuration -Check 'Profiles enabled' -Severity Pass -Target $target `
            -Message 'FSLogix profile containers are enabled.'
    }

    # --- VHDLocations / CCDLocations -------------------------------------------
    # Handles REG_MULTI_SZ and semicolon-delimited REG_SZ alike.
    $locations = @(ConvertTo-FslLocationList -Value $profiles['VHDLocations'])
    $usesCloudCache = (@(ConvertTo-FslLocationList -Value $profiles['CCDLocations']).Count -gt 0)

    if ($usesCloudCache -and $locations.Count -gt 0) {
        New-FslFinding -Category Configuration -Check 'VHDLocations vs CCDLocations' -Severity Critical -Target $target `
            -Message 'Both VHDLocations and CCDLocations are set. Per Microsoft the two must not be present at the same time.' `
            -Recommendation 'Remove one of the two: VHDLocations for classic SMB, CCDLocations for Cloud Cache.' `
            -HelpUri $configHelp
    }

    if ($locations.Count -eq 0 -and -not $usesCloudCache) {
        New-FslFinding -Category Configuration -Check 'VHDLocations defined' -Severity Critical -Target $target `
            -Message 'Neither VHDLocations nor CCDLocations is configured - FSLogix has nowhere to store profile containers.' `
            -Recommendation 'Set VHDLocations to the UNC path of your profile share (or CCDLocations for Cloud Cache).' `
            -HelpUri $configHelp
    }
    else {
        foreach ($location in $locations) {
            $online = $null
            if ($ConfigSnapshot.VhdLocationsOnline -is [hashtable] -and $ConfigSnapshot.VhdLocationsOnline.ContainsKey($location)) {
                $online = [bool]$ConfigSnapshot.VhdLocationsOnline[$location]
            }
            else {
                try { $online = Test-Path -Path $location -ErrorAction Stop }
                catch { $online = $false }
            }

            if ($online) {
                New-FslFinding -Category Configuration -Check 'VHDLocations reachable' -Severity Pass -Target $target `
                    -Message ("Profile location '{0}' is reachable." -f $location)
                continue
            }

            # Separate 'network path down' from 'the share denies the probing
            # user': a share that denies THIS account still answers on TCP 445.
            # Typical false-alarm scenario: Azure Files with identity-based auth,
            # where only the AVD users hold the share-level RBAC role and the
            # admin running the diagnostic cannot browse the share at all.
            $shareHost = $null
            if ($location -match '^\\\\(?<sharehost>[^\\]+)') { $shareHost = $Matches['sharehost'] }
            $portOpen = $null
            if ($shareHost) {
                if ($ConfigSnapshot.SmbPortOpen -is [hashtable] -and $ConfigSnapshot.SmbPortOpen.ContainsKey($location)) {
                    $portOpen = [bool]$ConfigSnapshot.SmbPortOpen[$location]
                }
                else {
                    $portOpen = Test-FslSmbPort -ComputerName $shareHost
                }
            }

            # In a remote (WinRM) session the probe CANNOT reach the share even
            # with correct permissions: Kerberos blocks the second hop to the
            # file server. Fleet mode always runs in exactly that situation.
            $inRemoteSession = ($null -ne $PSSenderInfo)
            if ($ConfigSnapshot.ContainsKey('InRemoteSession')) {
                $inRemoteSession = [bool]$ConfigSnapshot.InRemoteSession
            }

            $evidence = 'Note: the check runs in the current user context; the computer account or user may still have differing access.'
            if ($portOpen -eq $true -and $inRemoteSession) {
                $evidence = ("The probe ran inside a remote (WinRM) session, where Kerberos blocks the second hop to the file server - this failure is expected in fleet mode regardless of the account's real permissions. TCP 445 to '{0}' is open. {1}" -f $shareHost, $evidence)
            }
            elseif ($portOpen -eq $true) {
                $evidence = ("TCP 445 to '{0}' is open - the endpoint answers, so this looks like missing share permissions for the probing account '{1}', not a network problem. {2}" -f $shareHost, $env:USERNAME, $evidence)
            }
            elseif ($portOpen -eq $false) {
                $evidence = ("TCP 445 to '{0}' is NOT answering (blocked or offline) - this is a network/endpoint problem, not a permissions issue. {1}" -f $shareHost, $evidence)
            }

            $recommendation = 'Verify DNS, SMB connectivity, share and NTFS permissions for the profile share.'
            $reachHelpUri = 'https://learn.microsoft.com/en-us/fslogix/how-to-configure-storage-permissions'
            if ($shareHost -like '*.file.core.windows.net') {
                $recommendation = 'Azure Files: users need the ''Storage File Data SMB Share Contributor'' RBAC role on the storage account (admins ''Storage File Data SMB Share Elevated Contributor'' to browse), plus working identity-based auth (AD DS or Entra Kerberos) and NTFS ACLs. The probing account needs its own role assignment before this check can succeed.'
                $reachHelpUri = 'https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable'
            }

            New-FslFinding -Category Configuration -Check 'VHDLocations reachable' -Severity Critical -Target $target `
                -Message ("Profile location '{0}' is NOT reachable from this host (as the probing user)." -f $location) `
                -Evidence $evidence `
                -Recommendation $recommendation `
                -HelpUri $reachHelpUri
        }
    }

    # --- Size and disk format -------------------------------------------------
    if ($null -eq $profiles['SizeInMBs']) {
        New-FslFinding -Category Configuration -Check 'SizeInMBs' -Severity Info -Target $target `
            -Message 'SizeInMBs is not set; containers use the FSLogix default maximum size.' `
            -Recommendation 'Set an explicit SizeInMBs that matches your storage planning.' -HelpUri $configHelp
    }
    elseif ([int]$profiles['SizeInMBs'] -lt 5120) {
        New-FslFinding -Category Configuration -Check 'SizeInMBs' -Severity Warning -Target $target `
            -Message ("SizeInMBs is only {0} MB - profiles fill up quickly and a full container behaves like a full C: drive for the user." -f $profiles['SizeInMBs']) `
            -Recommendation 'Plan at least 10-30 GB per user for Office workloads.' -HelpUri $configHelp
    }

    if ($null -ne $profiles['IsDynamic'] -and [int]$profiles['IsDynamic'] -eq 0) {
        New-FslFinding -Category Configuration -Check 'IsDynamic' -Severity Warning -Target $target `
            -Message 'IsDynamic=0: every container is fully allocated at maximum size on the share.' `
            -Recommendation 'Set IsDynamic=1 unless you have a specific storage reason for fixed-size disks.' -HelpUri $configHelp
    }

    # Per Microsoft the DEFAULT VolumeType is vhd, so an unset value also means vhd.
    $volumeType = 'vhd (default)'
    if ($profiles['VolumeType']) { $volumeType = ([string]$profiles['VolumeType']).ToLowerInvariant() }
    if ($volumeType -ne 'vhdx') {
        New-FslFinding -Category Configuration -Check 'VolumeType' -Severity Warning -Target $target `
            -Message ("New containers are created as '{0}'; VHDX is the recommended modern format (more resilient, larger maximum size)." -f $volumeType) `
            -Recommendation 'Set VolumeType=vhdx explicitly. Existing VHD containers can be converted with frx migrate-vhd.' `
            -HelpUri $configHelp
    }

    # --- Failure masking and profile collisions --------------------------------
    if ($null -eq $profiles['DeleteLocalProfileWhenVHDShouldApply'] -or [int]$profiles['DeleteLocalProfileWhenVHDShouldApply'] -eq 0) {
        New-FslFinding -Category Configuration -Check 'Local profile collision' -Severity Warning -Target $target `
            -Message 'DeleteLocalProfileWhenVHDShouldApply=0: an existing local profile blocks the container attach (session Reason=3) and the user silently keeps the local profile.' `
            -Evidence 'This is one of the most common causes of "my settings are gone" tickets on rebuilt or reused hosts.' `
            -Recommendation 'Set DeleteLocalProfileWhenVHDShouldApply=1 after verifying no needed data lives in local profiles.' `
            -HelpUri $configHelp
    }
    else {
        New-FslFinding -Category Configuration -Check 'Local profile collision' -Severity Info -Target $target `
            -Message 'DeleteLocalProfileWhenVHDShouldApply=1: existing local profiles are PERMANENTLY deleted when the container should apply.' `
            -Recommendation 'Correct for most deployments - just be aware of the data-loss semantics when reusing hosts that held real local profiles.' `
            -HelpUri $configHelp
    }

    $preventFailure = ($null -ne $profiles['PreventLoginWithFailure'] -and [int]$profiles['PreventLoginWithFailure'] -eq 1)
    $preventTemp = ($null -ne $profiles['PreventLoginWithTempProfile'] -and [int]$profiles['PreventLoginWithTempProfile'] -eq 1)
    if (-not $preventFailure -and -not $preventTemp) {
        New-FslFinding -Category Configuration -Check 'Failure masking' -Severity Warning -Target $target `
            -Message 'PreventLoginWithFailure=0 and PreventLoginWithTempProfile=0: when the container attach fails, users silently work in a temp/local profile and changes are lost at logoff.' `
            -Evidence 'Correlate with session Reason=7 (temp profile) and [ERROR:...] log lines to find affected users.' `
            -Recommendation 'Set both to 1 in production so attach failures surface immediately instead of costing user data.' `
            -HelpUri $configHelp
    }

    # --- Profile/ODFC double configuration -------------------------------------
    if ($odfc -and $odfc['Enabled'] -eq 1 -and $profiles['Enabled'] -eq 1) {
        $odfcLocations = @(ConvertTo-FslLocationList -Value $odfc['VHDLocations'])
        $overlap = @($locations | Where-Object { $odfcLocations -contains $_ })
        if ($overlap.Count -gt 0) {
            New-FslFinding -Category Configuration -Check 'Profile/ODFC overlap' -Severity Warning -Target $target `
                -Message 'Profile container and ODFC container are both enabled and share the same VHDLocations.' `
                -Evidence ("Overlapping location(s): {0}" -f ($overlap -join ', ')) `
                -Recommendation 'Running both is only supported in specific designs; ODFC data is already inside the profile container by default. Verify this is intentional.' `
                -HelpUri 'https://learn.microsoft.com/en-us/fslogix/concepts-container-types'
        }
    }

    # --- Login-hang tuning ------------------------------------------------------
    # Defaults per Microsoft: LockedRetryCount=12, LockedRetryInterval=5 (60s worst case).
    $retryCount = 12
    if ($null -ne $profiles['LockedRetryCount']) { $retryCount = [int]$profiles['LockedRetryCount'] }
    $retryInterval = 5
    if ($null -ne $profiles['LockedRetryInterval']) { $retryInterval = [int]$profiles['LockedRetryInterval'] }
    $waitSeconds = $retryCount * $retryInterval
    if ($waitSeconds -gt 120) {
        New-FslFinding -Category Configuration -Check 'Locked-container retry time' -Severity Warning -Target $target `
            -Message ("A locked container makes logins hang for up to {0} seconds (LockedRetryCount={1} x LockedRetryInterval={2}s) before failing." -f $waitSeconds, $retryCount, $retryInterval) `
            -Recommendation 'Reduce the retry window so users fail fast instead of staring at a hung login screen.' `
            -HelpUri $configHelp
    }
    elseif ($retryCount -eq 0) {
        New-FslFinding -Category Configuration -Check 'Locked-container retry time' -Severity Warning -Target $target `
            -Message 'LockedRetryCount=0: a transient lock on the container fails the attach immediately (no retries).' `
            -Recommendation 'Keep a small retry budget (default 12 x 5s) to ride out transient SMB locks.' `
            -HelpUri $configHelp
    }

    # --- Stale/obsolete settings --------------------------------------------------
    if ($profiles.ContainsKey('ConcurrentUserSessions')) {
        New-FslFinding -Category Configuration -Check 'Obsolete setting' -Severity Info -Target $target `
            -Message 'ConcurrentUserSessions is set, but Microsoft removed this setting from the product - it has no effect.' `
            -Evidence 'Its presence usually means configuration carried over from an old gold image or GPO.' `
            -Recommendation 'Remove the value to keep the configuration honest.' `
            -HelpUri 'https://learn.microsoft.com/en-us/fslogix/concepts-multi-concurrent-connections'
    }

    # --- Logging configuration -----------------------------------------------------
    $logging = $ConfigSnapshot.Logging
    if ($logging) {
        if ($null -ne $logging['LoggingEnabled'] -and [int]$logging['LoggingEnabled'] -eq 0) {
            New-FslFinding -Category Configuration -Check 'Text logging' -Severity Warning -Target $target `
                -Message 'LoggingEnabled=0: FSLogix writes no text logs, which removes the most important diagnostic source on this host.' `
                -Recommendation 'Set LoggingEnabled=2 (all components).' -HelpUri $configHelp
        }
        if ($null -ne $logging['LogFileKeepingPeriod'] -and [int]$logging['LogFileKeepingPeriod'] -lt 7) {
            New-FslFinding -Category Configuration -Check 'Log retention' -Severity Info -Target $target `
                -Message ("LogFileKeepingPeriod={0} days (default 2) - often too short to investigate incidents reported after a weekend." -f $logging['LogFileKeepingPeriod']) `
                -Recommendation 'Raise to at least 7-14 days (maximum 180).' -HelpUri $configHelp
        }
    }

    # --- Antivirus exclusions ----------------------------------------------------
    if ($ConfigSnapshot.DefenderExclusions -is [array] -and $locations.Count -gt 0) {
        $exclusions = @($ConfigSnapshot.DefenderExclusions | Where-Object { $_ })
        $unexcluded = @()
        foreach ($location in $locations) {
            $covered = $false
            foreach ($exclusion in $exclusions) {
                # Covered only when the location IS the exclusion or lies UNDER it
                # (with a path boundary). An exclusion inside the location covers a
                # subfolder only, and '\\fs01\prof' must not cover '\\fs01\profiles'.
                $exclusionRoot = ([string]$exclusion).TrimEnd('\')
                $locationRoot = $location.TrimEnd('\')
                if ($locationRoot -eq $exclusionRoot -or $locationRoot -like ($exclusionRoot + '\*')) {
                    $covered = $true
                    break
                }
            }
            if (-not $covered) { $unexcluded += $location }
        }
        if ($unexcluded.Count -gt 0) {
            New-FslFinding -Category Configuration -Check 'Antivirus exclusions' -Severity Warning -Target $target `
                -Message 'Profile share paths are not in the Microsoft Defender path exclusions; on-access scanning of container disks degrades logon performance and can cause locks.' `
                -Evidence ("Not excluded: {0}" -f ($unexcluded -join ', ')) `
                -Recommendation 'Add the Microsoft-recommended FSLogix exclusions.' `
                -HelpUri 'https://learn.microsoft.com/en-us/fslogix/overview-prerequisites#configure-antivirus-file-and-folder-exclusions'
        }
        else {
            New-FslFinding -Category Configuration -Check 'Antivirus exclusions' -Severity Pass -Target $target `
                -Message 'All configured profile locations are covered by Defender path exclusions.'
        }
    }
}
