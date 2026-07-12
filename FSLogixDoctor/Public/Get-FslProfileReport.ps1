function Get-FslProfileReport {
    <#
    .SYNOPSIS
        Scans an FSLogix profile share and reports size, age and anomalies per
        container disk - without mounting anything.
    .DESCRIPTION
        Walks the standard FSLogix folder layout (<share>\<SID>_<username> or
        flip-flopped <username>_<SID>) and reports every VHD/VHDX it finds:
        file size, percent of the configured maximum, last-use age, and structural
        anomalies such as multiple disks in one folder or disks outside the naming
        convention.

        The scan is deliberately read-only and never mounts a disk: mounting an
        in-use production container can corrupt it. File size of a dynamic disk is
        a conservative lower bound of the space used inside it.
    .PARAMETER Path
        UNC path or local path of the profile share to scan.
    .PARAMETER MaximumSizeMB
        The configured container size limit (SizeInMBs) used to compute PercentOfMax.
        Defaults to the local FSLogix configuration when available, else 30000.
    .PARAMETER StaleDays
        Number of days without modification after which a disk is flagged stale.
        Defaults to 90.
    .EXAMPLE
        Get-FslProfileReport -Path \\fs01\fslogix$
    .EXAMPLE
        Get-FslProfileReport -Path \\fs01\fslogix$ | Where-Object Stale | Measure-Object SizeGB -Sum
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [int]$MaximumSizeMB = 0,

        [int]$StaleDays = 90
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Profile share path '$Path' not found or not reachable."
    }

    if ($MaximumSizeMB -le 0) {
        $MaximumSizeMB = 30000
        # Policies hive wins over the local key, matching FSLogix precedence.
        foreach ($configKey in @('HKLM:\SOFTWARE\Policies\FSLogix\Profiles', 'HKLM:\SOFTWARE\FSLogix\Profiles')) {
            $localConfig = Get-ItemProperty -LiteralPath $configKey -ErrorAction SilentlyContinue
            if ($localConfig -and $localConfig.SizeInMBs -gt 0) {
                $MaximumSizeMB = [int]$localConfig.SizeInMBs
                break
            }
        }
    }

    $now = Get-Date
    $sidPattern = 'S-1-\d+(?:-\d+)+'

    foreach ($folder in (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        $sid = $null
        $userName = $null
        if ($folder.Name -match "^(?<sid>$sidPattern)_(?<user>.+)$") {
            # Default layout: <SID>_<username>
            $sid = $Matches['sid']
            $userName = $Matches['user']
        }
        elseif ($folder.Name -match "^(?<user>.+)_(?<sid>$sidPattern)$") {
            # FlipFlopProfileDirectoryName=1 layout: <username>_<SID>
            $sid = $Matches['sid']
            $userName = $Matches['user']
        }

        $folderFiles = Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -ErrorAction SilentlyContinue
        $disks = @($folderFiles | Where-Object { $_.Extension -in @('.vhd', '.vhdx') })

        if ($disks.Count -eq 0) {
            [pscustomobject]@{
                PSTypeName   = 'FSLogixDoctor.ProfileDisk'
                Folder       = $folder.FullName
                Disk         = $null
                UserName     = $userName
                Sid          = $sid
                SizeGB       = 0
                PercentOfMax = 0
                LastModified = $folder.LastWriteTime
                AgeDays      = [int]($now - $folder.LastWriteTime).TotalDays
                Stale        = (($now - $folder.LastWriteTime).TotalDays -gt $StaleDays)
                DiskCount    = 0
                Anomaly      = 'Folder contains no container disk (leftover from a failed create or a manual cleanup).'
            }
            continue
        }

        foreach ($disk in $disks) {
            $anomalies = @()
            if ($null -eq $sid) {
                $anomalies += 'Folder name does not match FSLogix naming convention.'
            }
            if ($disks.Count -gt 1) {
                $anomalies += "Folder contains $($disks.Count) disks - possible leftover from a re-created profile."
            }

            $sizeGB = [math]::Round($disk.Length / 1GB, 2)
            $percent = 0
            if ($MaximumSizeMB -gt 0) {
                $percent = [math]::Round(($disk.Length / 1MB) / $MaximumSizeMB * 100, 1)
            }

            [pscustomobject]@{
                PSTypeName   = 'FSLogixDoctor.ProfileDisk'
                Folder       = $folder.FullName
                Disk         = $disk.FullName
                UserName     = $userName
                Sid          = $sid
                SizeGB       = $sizeGB
                PercentOfMax = $percent
                LastModified = $disk.LastWriteTime
                AgeDays      = [int]($now - $disk.LastWriteTime).TotalDays
                Stale        = (($now - $disk.LastWriteTime).TotalDays -gt $StaleDays)
                DiskCount    = $disks.Count
                Anomaly      = ($anomalies -join ' ')
            }
        }
    }

    # Disks lying directly in the share root violate the expected layout.
    $rootFiles = Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue
    $rootDisks = @($rootFiles | Where-Object { $_.Extension -in @('.vhd', '.vhdx') })
    foreach ($rootDisk in $rootDisks) {
        [pscustomobject]@{
            PSTypeName   = 'FSLogixDoctor.ProfileDisk'
            Folder       = $Path
            Disk         = $rootDisk.FullName
            UserName     = $null
            Sid          = $null
            SizeGB       = [math]::Round($rootDisk.Length / 1GB, 2)
            PercentOfMax = 0
            LastModified = $rootDisk.LastWriteTime
            AgeDays      = [int]($now - $rootDisk.LastWriteTime).TotalDays
            Stale        = (($now - $rootDisk.LastWriteTime).TotalDays -gt $StaleDays)
            DiskCount    = 1
            Anomaly      = 'Disk sits in the share root instead of a per-user folder.'
        }
    }
}
