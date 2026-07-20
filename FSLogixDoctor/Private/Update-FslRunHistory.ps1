function Update-FslRunHistory {
    <#
    .SYNOPSIS
        Persists a diagnostic run to the history folder and diffs it against the
        previous run of the same scope: current findings are tagged New/Persisting
        (with a consecutive-run counter), and Critical/Warning findings that
        disappeared come back as synthetic 'Resolved' Info findings.

        Findings match across runs on Category|Check|Target - messages carry
        volatile counters and are deliberately not part of the identity.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper that only runs after the caller explicitly opted in via -HistoryPath; writing the history file is its entire purpose.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]]$Finding = @(),

        [Parameter(Mandatory)]
        [string]$HistoryPath,

        [Parameter(Mandatory)]
        [string]$Scope
    )

    if (-not (Test-Path -LiteralPath $HistoryPath)) {
        New-Item -ItemType Directory -Path $HistoryPath -Force | Out-Null
    }

    # One history stream per scope (host or sorted fleet list), so alternating
    # between different targets never produces bogus diffs.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $scopeHash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Scope)))).Replace('-', '').Substring(0, 10).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    $previous = $null
    $previousFile = Get-ChildItem -LiteralPath $HistoryPath -Filter ("run-{0}-*.json" -f $scopeHash) -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($previousFile) {
        try { $previous = Get-Content -LiteralPath $previousFile.FullName -Raw | ConvertFrom-Json }
        catch { Write-Warning ("History file '{0}' could not be read - continuing without a diff." -f $previousFile.Name) }
    }

    $prevMap = @{}
    if ($previous -and $previous.Findings) {
        foreach ($prevFinding in $previous.Findings) {
            $prevMap[('{0}|{1}|{2}' -f $prevFinding.Category, $prevFinding.Check, $prevFinding.Target)] = $prevFinding
        }
    }

    $output = New-Object System.Collections.Generic.List[object]
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($currentFinding in $Finding) {
        $key = '{0}|{1}|{2}' -f $currentFinding.Category, $currentFinding.Check, $currentFinding.Target
        $persistCount = 1
        $status = ''
        if ($prevMap.ContainsKey($key)) {
            $status = 'Persisting'
            $persistCount = [int]$prevMap[$key].PersistCount + 1
            $prevMap.Remove($key)
        }
        elseif ($previous) {
            $status = 'New'
        }
        Add-Member -InputObject $currentFinding -NotePropertyName ChangeStatus -NotePropertyValue $status -Force

        # Only alert-worthy findings get the annotation - Pass/Info stay quiet.
        if ($previous -and $currentFinding.Severity -in @('Critical', 'Warning')) {
            if ($status -eq 'New') {
                $currentFinding.Message += ' (New since the last run.)'
            }
            elseif ($persistCount -gt 1) {
                $currentFinding.Message += (" (Persisting - seen in {0} consecutive runs.)" -f $persistCount)
            }
        }

        $records.Add([pscustomobject]@{
                Category     = [string]$currentFinding.Category
                Check        = [string]$currentFinding.Check
                Severity     = [string]$currentFinding.Severity
                Target       = [string]$currentFinding.Target
                Message      = [string]$currentFinding.Message
                PersistCount = $persistCount
            })
        $output.Add($currentFinding)
    }

    # Whatever alert-worthy finding is left in the previous map has disappeared.
    if ($previous) {
        foreach ($leftKey in @($prevMap.Keys)) {
            $gone = $prevMap[$leftKey]
            if ([string]$gone.Severity -notin @('Critical', 'Warning')) { continue }
            $oldMessage = [string]$gone.Message
            if ($oldMessage.Length -gt 160) { $oldMessage = $oldMessage.Substring(0, 160) + '...' }
            $resolvedFinding = New-FslFinding -Category ([string]$gone.Category) -Check ([string]$gone.Check) -Severity Info -Target ([string]$gone.Target) `
                -Message ("Resolved since the last run: the previous {0} finding is gone. Was: {1}" -f $gone.Severity, $oldMessage)
            Add-Member -InputObject $resolvedFinding -NotePropertyName ChangeStatus -NotePropertyValue 'Resolved' -Force
            $output.Add($resolvedFinding)
        }
    }

    $runRecord = [pscustomobject]@{
        Scope     = $Scope
        Timestamp = (Get-Date).ToString('o')
        Findings  = $records
    }
    $fileName = 'run-{0}-{1}.json' -f $scopeHash, (Get-Date -Format 'yyyyMMdd-HHmmssfff')
    $runRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $HistoryPath $fileName) -Encoding UTF8

    $output
}
