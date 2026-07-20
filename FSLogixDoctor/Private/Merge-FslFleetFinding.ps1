function Merge-FslFleetFinding {
    <#
    .SYNOPSIS
        Deduplicates identical findings across fleet hosts: same category,
        check, severity, message and evidence collapse into one finding whose
        Target lists every affected host. Host-specific findings (differing
        message or evidence, e.g. log counts) stay separate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]]$Finding = @()
    )

    $groups = $Finding | Group-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.Category, $_.Check, $_.Severity, $_.Message, $_.Evidence }
    foreach ($group in $groups) {
        $targets = @($group.Group | ForEach-Object { [string]$_.Target } | Select-Object -Unique | Sort-Object)
        if ($targets.Count -le 1) {
            $group.Group
            continue
        }
        $first = $group.Group | Select-Object -First 1
        New-FslFinding -Category ([string]$first.Category) -Check ([string]$first.Check) -Severity ([string]$first.Severity) `
            -Target ($targets -join ', ') `
            -Message ("{0} (Affects {1} hosts.)" -f $first.Message, $targets.Count) `
            -Evidence ([string]$first.Evidence) `
            -Recommendation ([string]$first.Recommendation) `
            -HelpUri ([string]$first.HelpUri)
    }
}
