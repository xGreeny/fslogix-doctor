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
        [string]$Scope,

        # Per-container store measurements of THIS run; persisted with the run
        # record and compared against the oldest retained run for the capacity
        # forecast.
        [AllowEmptyCollection()]
        [object[]]$StoreMetric = @(),

        [ValidateRange(1, 3650)]
        [int]$RetentionDays = 90
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

    $scopeFiles = @(Get-ChildItem -LiteralPath $HistoryPath -Filter ("run-{0}-*.json" -f $scopeHash) -File -ErrorAction SilentlyContinue |
            Sort-Object Name)
    $previous = $null
    $previousFile = $scopeFiles | Select-Object -Last 1
    if ($previousFile) {
        try { $previous = Get-Content -LiteralPath $previousFile.FullName -Raw | ConvertFrom-Json }
        catch { Write-Warning ("History file '{0}' could not be read - continuing without a diff." -f $previousFile.Name) }
    }

    # Capacity-forecast baseline: the OLDEST retained run that carries store
    # metrics - a long measurement window keeps the growth rate stable.
    $baseline = $null
    foreach ($scopeFile in $scopeFiles) {
        try { $candidate = Get-Content -LiteralPath $scopeFile.FullName -Raw | ConvertFrom-Json }
        catch { continue }
        if ($candidate.StoreMetrics -and @($candidate.StoreMetrics).Count -gt 0) { $baseline = $candidate; break }
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

    # Capacity forecast: compare this run's store metrics against the oldest
    # retained run. Requires at least a day of history so hourly sensor runs
    # never produce noise rates; forecast findings are recomputed every run
    # and deliberately not persisted.
    if (@($StoreMetric).Count -gt 0 -and $baseline -and $baseline.StoreMetrics) {
        $baselineTime = $null
        try { $baselineTime = [datetime]::Parse([string]$baseline.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
        catch { $baselineTime = $null }
        $deltaDays = 0.0
        if ($baselineTime) { $deltaDays = ((Get-Date) - $baselineTime).TotalDays }
        if ($deltaDays -ge 1) {
            $baselineByDisk = @{}
            foreach ($oldMetric in $baseline.StoreMetrics) { $baselineByDisk[[string]$oldMetric.Disk] = $oldMetric }
            foreach ($currentMetric in $StoreMetric) {
                $oldMetric = $baselineByDisk[[string]$currentMetric.Disk]
                if (-not $oldMetric) { continue }
                if ([double]$currentMetric.PercentOfMax -le 0) { continue }
                $growthGB = [double]$currentMetric.SizeGB - [double]$oldMetric.SizeGB
                if ($growthGB -le 0) { continue }
                $ratePerDay = $growthGB / $deltaDays
                if ($ratePerDay -le 0.01) { continue }
                $maxGB = [double]$currentMetric.SizeGB / ([double]$currentMetric.PercentOfMax / 100)
                $daysToFull = ($maxGB - [double]$currentMetric.SizeGB) / $ratePerDay
                if ($daysToFull -gt 30) { continue }
                $severity = 'Warning'
                if ($daysToFull -le 7) { $severity = 'Critical' }
                $label = [string]$currentMetric.UserName
                if (-not $label) { $label = [string]$currentMetric.Disk }
                $output.Add((New-FslFinding -Category ProfileStore -Check 'Capacity forecast' -Severity $severity -Target $label `
                            -Message ("Container grows ~{0} GB/day; at the current rate it reaches its maximum in ~{1} day(s) (currently {2}% of {3} GB)." -f [math]::Round($ratePerDay, 2), [math]::Round($daysToFull), $currentMetric.PercentOfMax, [math]::Round($maxGB, 1)) `
                            -Evidence ("Disk: {0}. Grew {1} GB over the last {2} day(s)." -f $currentMetric.Disk, [math]::Round($growthGB, 2), [math]::Round($deltaDays, 1)) `
                            -Recommendation 'Free space inside the profile (Remove-FslOrphanedOst, OneDrive cache, temp data) or raise the VHDX maximum before sign-ins fail - and check what is growing (Outlook OST, Teams cache).'))
            }
        }
    }

    $metricRecords = @()
    foreach ($metric in $StoreMetric) {
        if (-not $metric.Disk) { continue }
        $metricRecords += [pscustomobject]@{
            Disk         = [string]$metric.Disk
            UserName     = [string]$metric.UserName
            SizeGB       = [double]$metric.SizeGB
            PercentOfMax = [double]$metric.PercentOfMax
        }
    }
    $runRecord = [pscustomobject]@{
        Scope        = $Scope
        Timestamp    = (Get-Date).ToString('o')
        Findings     = $records
        StoreMetrics = $metricRecords
    }
    $fileName = 'run-{0}-{1}.json' -f $scopeHash, (Get-Date -Format 'yyyyMMdd-HHmmssfff')
    $runRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $HistoryPath $fileName) -Encoding UTF8

    # Built-in retention: rotate run files past the window (all scopes).
    Get-ChildItem -LiteralPath $HistoryPath -Filter 'run-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-1 * $RetentionDays) |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $output
}
