function Remove-FslOrphanedOst {
    <#
    .SYNOPSIS
        Deletes orphaned Outlook OST cache files from a profile - the explicit,
        WhatIf-first cleanup companion to FSLogix event 29 ('Orphaned OST
        file(s) found').
    .DESCRIPTION
        OST files are regenerable local caches of an Exchange mailbox; orphaned
        ones (left behind by profile repairs, mailbox migrations or cached-mode
        changes) only bloat the profile container. This command keeps the most
        recently written OST file(s) per folder as the active cache and deletes
        the rest. Files that are locked (in use by Outlook) are skipped with a
        warning, never forced.

        This is the first of the explicit -Fix companions: it is NEVER called
        by Invoke-FslDiagnostic, honors -WhatIf/-Confirm (ConfirmImpact High)
        and reports exactly what it did per file.
    .PARAMETER Path
        Profile root (a live C:\Users\<user> folder while the user is signed
        in, or the root of a mounted container) or the Outlook cache folder
        itself. When the path itself holds no OST files, the well-known
        AppData\Local\Microsoft\Outlook subfolder is used.
    .PARAMETER KeepNewest
        How many of the most recently written OST files to keep per folder.
        Defaults to 1 (the active cache).
    .EXAMPLE
        Remove-FslOrphanedOst -Path C:\Users\jdoe -WhatIf

        Shows which OST files would be deleted, touches nothing.
    .EXAMPLE
        Remove-FslOrphanedOst -Path X:\ -Confirm:$false

        Cleans a container mounted as X:\ (user signed out) without prompting.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(1, 10)]
        [int]$KeepNewest = 1
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Path '$Path' not found."
        return
    }

    $outlookPath = $Path
    if (@(Get-ChildItem -LiteralPath $outlookPath -Filter '*.ost' -File -ErrorAction SilentlyContinue).Count -eq 0) {
        $candidate = Join-Path $Path 'AppData\Local\Microsoft\Outlook'
        if (Test-Path -LiteralPath $candidate) { $outlookPath = $candidate }
    }

    $ostFiles = @(Get-ChildItem -LiteralPath $outlookPath -Filter '*.ost' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
    if ($ostFiles.Count -eq 0) {
        Write-Warning ("No OST files found under '{0}'." -f $outlookPath)
        return
    }

    $orphans = @($ostFiles | Select-Object -Skip $KeepNewest)
    if ($orphans.Count -eq 0) {
        Write-Verbose ("Only {0} OST file(s) present - nothing to clean with KeepNewest={1}." -f $ostFiles.Count, $KeepNewest)
        return
    }

    foreach ($file in $orphans) {
        $sizeMB = [math]::Round($file.Length / 1MB, 1)
        $removed = $false
        $reason = ''
        if ($PSCmdlet.ShouldProcess($file.FullName, ("Delete orphaned OST ({0} MB)" -f $sizeMB))) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removed = $true
            }
            catch {
                $reason = ("In use or not deletable: {0}" -f $_.Exception.Message)
                Write-Warning ("Skipped '{0}': {1}" -f $file.Name, $reason)
            }
        }
        else {
            $reason = 'Skipped (WhatIf or confirmation declined)'
        }

        [pscustomobject]@{
            PSTypeName = 'FSLogixDoctor.OstCleanup'
            File       = $file.FullName
            SizeMB     = $sizeMB
            LastWrite  = $file.LastWriteTime
            Removed    = $removed
            Reason     = $reason
        }
    }
}
