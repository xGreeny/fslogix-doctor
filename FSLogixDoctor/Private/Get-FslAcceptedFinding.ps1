function Get-FslAcceptedFinding {
    <#
    .SYNOPSIS
        Loads the accepted-findings list: deliberate, documented deviations
        (JSON array of { Check, Target, Reason, ExpiresOn }) that the
        diagnostic downgrades to Info instead of alerting forever. Returns
        only valid, unexpired entries; a missing file is simply an empty list.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $entries = @()
    try {
        $entries = @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning ("Accepted-findings file '{0}' could not be read: {1}" -f $Path, $_.Exception.Message)
        return
    }

    foreach ($entry in $entries) {
        if (-not $entry.Check -or -not $entry.Reason) {
            Write-Warning 'Accepted-findings entry skipped - Check and Reason are required.'
            continue
        }
        if ($entry.ExpiresOn) {
            $expiry = $null
            try { $expiry = [datetime]::Parse([string]$entry.ExpiresOn, [System.Globalization.CultureInfo]::InvariantCulture) }
            catch { $expiry = $null }
            if ($expiry -and $expiry -lt (Get-Date).Date) { continue }
        }
        $entry
    }
}
