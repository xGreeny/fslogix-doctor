function Remove-FslOrphanedDisk {
    <#
    .SYNOPSIS
        Deletes (or archives) container disks whose owner no longer exists - the
        explicit, WhatIf-first cleanup companion to Get-FslOrphanedDisk.
    .DESCRIPTION
        Takes Get-FslOrphanedDisk output from the pipeline and acts ONLY on
        disks classified as 'Orphaned' (the account no longer exists). Disks in
        any other state - OK, Disabled, Unknown - are skipped: a disabled account
        may come back, and Unknown is by definition not a safe delete.

        With -ArchivePath the disk is moved instead of deleted, preserving the
        container folder name - the cautious first step before reclaiming the
        space for good. Empty container folders are removed after the disk is
        gone. Honors -WhatIf/-Confirm (ConfirmImpact High) and reports one
        result object per disk.
    .PARAMETER InputObject
        Objects from Get-FslOrphanedDisk (need State, Disk, UserName, SizeGB).
    .PARAMETER ArchivePath
        Move the disks here (into a subfolder named after the container folder)
        instead of deleting them.
    .EXAMPLE
        Get-FslOrphanedDisk -Path \\fs01\fslogix$ | Where-Object State -eq 'Orphaned' |
            Remove-FslOrphanedDisk -WhatIf

        Shows exactly which disks would be removed, touches nothing.
    .EXAMPLE
        Get-FslOrphanedDisk -Path \\fs01\fslogix$ | Remove-FslOrphanedDisk -ArchivePath \\fs01\archive$ -Confirm:$false

        Archives every confirmed-orphaned disk; everything else is skipped.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject]$InputObject,

        [string]$ArchivePath
    )

    process {
        $state = [string]$InputObject.State
        $diskPath = [string]$InputObject.Disk
        if ($state -ne 'Orphaned') {
            Write-Verbose ("Skipping '{0}': State is '{1}' - only Orphaned disks are removed." -f $diskPath, $state)
            return
        }
        if (-not $diskPath -or -not (Test-Path -LiteralPath $diskPath)) {
            Write-Warning ("Disk '{0}' not found - skipped." -f $diskPath)
            return
        }

        $action = 'Delete orphaned container disk'
        if ($ArchivePath) { $action = ("Archive orphaned container disk to '{0}'" -f $ArchivePath) }

        $performed = 'Skipped'
        $destination = ''
        if ($PSCmdlet.ShouldProcess($diskPath, $action)) {
            try {
                if ($ArchivePath) {
                    $folderName = Split-Path (Split-Path $diskPath -Parent) -Leaf
                    $targetDir = Join-Path $ArchivePath $folderName
                    if (-not (Test-Path -LiteralPath $targetDir)) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                    $destination = Join-Path $targetDir (Split-Path $diskPath -Leaf)
                    Move-Item -LiteralPath $diskPath -Destination $destination -Force -ErrorAction Stop
                    $performed = 'Archived'
                }
                else {
                    Remove-Item -LiteralPath $diskPath -Force -ErrorAction Stop
                    $performed = 'Deleted'
                }

                # Remove the container folder once it holds nothing else.
                $parent = Split-Path $diskPath -Parent
                if ((Test-Path -LiteralPath $parent) -and @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                    Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Warning ("Could not remove '{0}': {1}" -f $diskPath, $_.Exception.Message)
                $performed = 'Failed'
            }
        }

        [pscustomobject]@{
            PSTypeName  = 'FSLogixDoctor.DiskCleanup'
            Disk        = $diskPath
            UserName    = [string]$InputObject.UserName
            SizeGB      = $InputObject.SizeGB
            Action      = $performed
            Destination = $destination
        }
    }
}
