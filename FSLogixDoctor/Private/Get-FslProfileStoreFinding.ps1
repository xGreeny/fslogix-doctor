function Get-FslProfileStoreFinding {
    <#
    .SYNOPSIS
        Opt-in profile-store checks for Invoke-FslDiagnostic: scans the profile
        share(s) with Get-FslProfileReport and turns capacity risks (>=85% of
        maximum Warning, >=95% Critical) and structural anomalies (leftover
        folders, multi-disk folders) into findings. FSLogix's own event 33 only
        fires below 200 MB free - this check warns weeks earlier.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Path = @(),

        # Auto-detected scans skip unreachable stores quietly (verbose only);
        # explicitly requested scans keep reporting a Warning finding.
        [switch]$SkipUnreachable,

        # Disk paths from event-33 findings: a container that FSLogix reports
        # as nearly full but the store sees far below 85% is the classic
        # 'VHDX resized without extending the partition inside' case.
        [AllowEmptyCollection()]
        [string[]]$CrossCheckPath = @()
    )

    $storePaths = @($Path | Where-Object { $_ })
    if ($storePaths.Count -eq 0) {
        try {
            $profilesKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction Stop
            $storePaths = @(ConvertTo-FslLocationList -Value $profilesKey.VHDLocations)
        }
        catch { $storePaths = @() }
    }
    if ($storePaths.Count -eq 0) {
        Write-Warning 'Profile store scan requested, but no path was given and no local VHDLocations were found - pass -ProfileStorePath explicitly.'
        return
    }

    foreach ($storePath in $storePaths) {
        $disks = @()
        try {
            $disks = @(Get-FslProfileReport -Path $storePath -ErrorAction Stop)
        }
        catch {
            if ($SkipUnreachable) {
                Write-Verbose ("Auto store scan skipped for '{0}': {1}" -f $storePath, $_.Exception.Message)
            }
            else {
                New-FslFinding -Category ProfileStore -Check 'Profile store scan' -Severity Warning -Target $storePath `
                    -Message ("Could not scan profile store '{0}': {1}" -f $storePath, $_.Exception.Message) `
                    -Recommendation 'Verify the account running the diagnostic can browse the share (on Azure Files: Storage File Data SMB Share Elevated Contributor).'
            }
            continue
        }

        $flagged = $false

        foreach ($disk in ($disks | Where-Object { $null -ne $_.PercentOfMax -and [double]$_.PercentOfMax -ge 85 })) {
            $flagged = $true
            $severity = 'Warning'
            if ([double]$disk.PercentOfMax -ge 95) { $severity = 'Critical' }
            $label = [string]$disk.UserName
            if (-not $label) { $label = Split-Path ([string]$disk.Folder) -Leaf }
            New-FslFinding -Category ProfileStore -Check 'Container capacity' -Severity $severity -Target $label `
                -Message ("Container is at {0}% of its maximum size ({1} GB used). FSLogix's own warning (event 33) only fires below 200 MB free - act before sign-ins fail." -f $disk.PercentOfMax, $disk.SizeGB) `
                -Evidence ("Disk: {0}. Last modified {1}." -f $disk.Disk, $disk.LastModified) `
                -Recommendation 'Free space inside the profile first (Remove-FslOrphanedOst for stale Outlook caches, OneDrive cache, temp data); if that is not enough, raise the VHDX maximum with the user signed out (Resize-VHD, then extend the partition inside) - SizeInMBs only affects newly created containers.' `
                -HelpUri 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings'
        }

        foreach ($anomalyGroup in ($disks | Where-Object { $_.Anomaly } | Group-Object Folder)) {
            $flagged = $true
            $first = $anomalyGroup.Group | Select-Object -First 1
            $groupSize = [math]::Round((($anomalyGroup.Group | Measure-Object SizeGB -Sum).Sum), 1)
            New-FslFinding -Category ProfileStore -Check 'Profile store anomaly' -Severity Warning -Target (Split-Path ([string]$anomalyGroup.Name) -Leaf) `
                -Message ([string]$first.Anomaly) `
                -Evidence ("Folder: {0} ({1} GB across {2} disk(s), last modified {3})." -f $anomalyGroup.Name, $groupSize, $anomalyGroup.Group.Count, $first.LastModified) `
                -Recommendation 'Verify, then clean up: Get-FslOrphanedDisk classifies ownerless disks against the identity infrastructure; Remove-FslOrphanedDisk archives or deletes confirmed leftovers (WhatIf-first).'
        }

        foreach ($checkPath in $CrossCheckPath) {
            $crossMatch = $disks | Where-Object { [string]$_.Disk -eq $checkPath -and $null -ne $_.PercentOfMax -and [double]$_.PercentOfMax -lt 85 } |
                Select-Object -First 1
            if ($crossMatch) {
                $flagged = $true
                $crossLabel = [string]$crossMatch.UserName
                if (-not $crossLabel) { $crossLabel = Split-Path ([string]$crossMatch.Folder) -Leaf }
                New-FslFinding -Category ProfileStore -Check 'Resize incomplete' -Severity Warning -Target $crossLabel `
                    -Message ("Event 33 reports this container below 200 MB free, but the store sees it at only {0}% of its maximum - the classic sign that the VHDX was resized without extending the partition INSIDE." -f $crossMatch.PercentOfMax) `
                    -Evidence ("Disk: {0} ({1} GB)." -f $crossMatch.Disk, $crossMatch.SizeGB) `
                    -Recommendation 'With the user signed out: Mount-VHD, Resize-Partition to the supported maximum, dismount. Event 33 stops at the next logon once the volume inside actually has room.'
            }
        }

        if (-not $flagged) {
            New-FslFinding -Category ProfileStore -Check 'Profile store' -Severity Pass -Target $storePath `
                -Message ("Scanned {0} container(s) on '{1}': no capacity or structural findings." -f $disks.Count, $storePath)
        }

        # Metrics travel alongside the findings (separated by PSTypeName) so
        # the caller can persist them for the capacity forecast.
        $diskMetrics = @()
        foreach ($disk in $disks) {
            if (-not $disk.Disk -or $null -eq $disk.PercentOfMax) { continue }
            $diskMetrics += [pscustomobject]@{
                Disk         = [string]$disk.Disk
                UserName     = [string]$disk.UserName
                SizeGB       = [double]$disk.SizeGB
                PercentOfMax = [double]$disk.PercentOfMax
            }
        }
        [pscustomobject]@{
            PSTypeName = 'FSLogixDoctor.StoreMetric'
            StorePath  = [string]$storePath
            Disks      = $diskMetrics
        }
    }
}
