function Invoke-FslDiagnostic {
    <#
    .SYNOPSIS
        Runs the full FSLogixDoctor diagnostic on a session host and answers the
        question 'why are profiles failing here?' in one command.
    .DESCRIPTION
        Combines every FSLogixDoctor check into one read-only run:

          1. Environment    - install state, service, version
          2. Configuration  - Test-FslConfiguration rule set
          3. SessionState   - per-session Status/Reason/Error, translated
          4. LogFile        - recent errors from the FSLogix text logs, decoded
          5. EventLog       - FSLogix event channels, bucketed and explained

        Returns FSLogixDoctor.Finding objects and optionally renders them into a
        self-contained HTML report (-ReportPath).

        Two safeguards keep noise from drowning out real problems: messages that
        match the known-benign noise database (Data\BenignPatterns.psd1) are
        reported as Info instead of Critical, and when every recorded session
        attached cleanly, remaining Critical log/event findings are downgraded to
        Warning because no user-visible impact exists yet.
    .PARAMETER Hours
        Look-back window for log and event analysis. Defaults to 24.
    .PARAMETER LogPath
        Root of the FSLogix log directory. Defaults to %ProgramData%\FSLogix\Logs.
    .PARAMETER IncludeWarnings
        Also surface WARN-level log lines, not only errors.
    .PARAMETER ReportPath
        When set, additionally writes the HTML report to this path.
    .PARAMETER PassThru
        Emit the finding objects even when -ReportPath is used.
    .EXAMPLE
        Invoke-FslDiagnostic

        Full diagnostic of the local session host, findings on the pipeline.
    .EXAMPLE
        Invoke-FslDiagnostic -Hours 4 -ReportPath C:\Temp\fslogix-report.html
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [string]$LogPath = (Join-Path $env:ProgramData 'FSLogix\Logs'),

        [switch]$IncludeWarnings,

        [string]$ReportPath,

        [switch]$PassThru
    )

    $after = (Get-Date).AddHours(-1 * $Hours)
    $findings = New-Object System.Collections.Generic.List[object]

    # 1 + 2: Environment and configuration (Test-FslConfiguration covers both).
    Write-Verbose 'Checking install state and configuration...'
    foreach ($finding in (Test-FslConfiguration)) { $findings.Add($finding) }

    # 3: Per-session state.
    Write-Verbose 'Reading per-session profile state...'
    $sessions = @(Get-FslSessionState -WarningAction SilentlyContinue)
    $unhealthy = @($sessions | Where-Object { -not $_.Healthy })
    foreach ($session in $unhealthy) {
        $label = $session.Account
        if (-not $label) { $label = $session.Sid }
        $findings.Add((New-FslFinding -Category SessionState -Check 'Session attach state' -Severity Warning -Target $label `
                    -Message ("Last attach did not complete cleanly: Status={0} ({1}), Reason={2} ({3})." -f $session.Status, $session.StatusText, $session.Reason, $session.ReasonText) `
                    -Evidence ("Error: {0} - {1}" -f $session.Error, $session.ErrorText) `
                    -Recommendation 'Correlate with Get-FslLogError around the login time of this user.'))
    }
    if ($sessions.Count -gt 0 -and $unhealthy.Count -eq 0) {
        $findings.Add((New-FslFinding -Category SessionState -Check 'Session attach state' -Severity Pass `
                    -Message ("All {0} recorded session(s) attached cleanly." -f $sessions.Count)))
    }

    # When every recorded session attached cleanly, log/event errors have no
    # visible user impact (yet); Critical log/event findings are downgraded to
    # Warning below so real outages stand out from service-level noise.
    $allSessionsHealthy = ($sessions.Count -gt 0 -and $unhealthy.Count -eq 0)
    $correlationNote = 'Downgraded from Critical: all recorded sessions attached cleanly, so no user impact is visible yet.'

    # 4: Log file errors, grouped by error code.
    Write-Verbose ("Parsing FSLogix logs since {0}..." -f $after)
    $logParams = @{ Path = $LogPath; After = $after; WarningAction = 'SilentlyContinue' }
    if ($IncludeWarnings) { $logParams['IncludeWarnings'] = $true }
    $logEntries = @(Get-FslLogError @logParams)

    foreach ($group in ($logEntries | Group-Object ErrorCode | Sort-Object Count -Descending)) {
        $codeLabel = $group.Name
        if (-not $codeLabel) { $codeLabel = 'no code' }

        # The same error code can carry both real failures and known-benign noise
        # (e.g. 0x00000005 for real ACL problems AND the harmless GPO DataStore
        # import); classify per message, not per code.
        $benign = @($group.Group | Where-Object { $_.Benign })
        $alertable = @($group.Group | Where-Object { -not $_.Benign })

        if ($alertable.Count -eq 0) {
            $breakdown = (@(Get-FslMessageBreakdown -Message @($group.Group | ForEach-Object Message)) -join ' | ')
            $reasons = (@($group.Group | ForEach-Object { (Test-FslBenignMessage -Message $_.Message).Reason } | Select-Object -Unique) -join ' ')
            $findings.Add((New-FslFinding -Category LogFile -Check ("Log errors ({0})" -f $codeLabel) -Severity Info `
                        -Message ("{0}x in the last {1}h: [{2}] every occurrence matches a known-benign noise pattern - no action needed. {3}" -f $group.Count, $Hours, $codeLabel, $reasons) `
                        -Evidence ("Messages: {0}" -f $breakdown)))
            continue
        }

        # Mixed bucket: the alert-worthy messages lead the evidence, never the
        # noise - one real failure must not hide behind 60x of known chatter.
        $alertBreakdown = (@(Get-FslMessageBreakdown -Message @($alertable | ForEach-Object Message) -Top 5) -join ' | ')

        $sample = $alertable | Select-Object -Last 1
        $severity = 'Warning'
        $meaning = ''
        $recommendation = ''
        $helpUri = ''
        $groupHasError = (@($alertable | Where-Object Level -eq 'ERROR').Count -gt 0)
        if ($group.Name) {
            $decoded = Get-FslErrorCode -Code $group.Name
            if ($decoded) {
                $meaning = $decoded.Meaning
                $recommendation = (@($decoded.Fixes) -join ' ')
                # Curated codes are escalated only when the alert-worthy lines
                # contain ERROR-level entries; several curated codes are documented
                # as benign at WARN level (e.g. 0x00000002 at a user's first
                # sign-in).
                if ($decoded.InDatabase -and $groupHasError) { $severity = 'Critical' }
                $helpUri = [string]$decoded.Source
            }
        }

        $message = ("{0}x in the last {1}h: [{2}] {3}" -f $alertable.Count, $Hours, $codeLabel, $meaning).Trim()
        if ($benign.Count -gt 0) {
            $message += (" (Plus {0} known-benign noise line(s) with the same code, excluded from this count.)" -f $benign.Count)
        }
        if ($severity -eq 'Critical' -and $allSessionsHealthy) {
            $severity = 'Warning'
            $message += ' ' + $correlationNote
        }
        $findings.Add((New-FslFinding -Category LogFile -Check ("Log errors ({0})" -f $codeLabel) -Severity $severity `
                    -Message $message `
                    -Evidence ("Alert-worthy: {0}. Sample: {1} ({2}:{3})" -f $alertBreakdown, $sample.Message, $sample.File, $sample.LineNumber) `
                    -Recommendation $recommendation -HelpUri $helpUri))
    }
    if ($logEntries.Count -eq 0) {
        $findings.Add((New-FslFinding -Category LogFile -Check 'Log errors' -Severity Pass `
                    -Message ("No errors in the FSLogix logs in the last {0} hours." -f $Hours)))
    }

    # 5: Event log summary.
    Write-Verbose 'Summarizing FSLogix event logs...'
    $eventSummaries = @(Get-FslEventSummary -After $after -MinimumLevel Warning -WarningAction SilentlyContinue)
    foreach ($summary in $eventSummaries) {
        $count = [int]$summary.Count
        $benignCount = 0
        if ($null -ne $summary.PSObject.Properties['BenignCount']) { $benignCount = [int]$summary.BenignCount }

        $evidence = ("Last seen {0}. Sample: {1}" -f $summary.LastSeen, $summary.SampleMessage)
        if ($null -ne $summary.PSObject.Properties['TopMessages'] -and @($summary.TopMessages).Count -gt 0) {
            $evidence = ("Last seen {0}. Messages: {1}" -f $summary.LastSeen, (@($summary.TopMessages) -join ' | '))
        }

        if ($count -gt 0 -and $benignCount -ge $count) {
            $findings.Add((New-FslFinding -Category EventLog -Check ("Event {0}" -f $summary.EventId) -Severity Info -Target $summary.ComputerName `
                        -Message ("{0}x event {1}: every occurrence matches a known-benign noise pattern - no action needed." -f $count, $summary.EventId) `
                        -Evidence $evidence))
            continue
        }

        # Mixed bucket: lead the evidence with the alert-worthy messages so a
        # single real failure never hides behind the noise counts.
        if ($benignCount -gt 0 -and $null -ne $summary.PSObject.Properties['AlertMessages'] -and @($summary.AlertMessages).Count -gt 0) {
            $evidence = ("Last seen {0}. Alert-worthy: {1}. Plus {2}x known-benign noise." -f $summary.LastSeen, (@($summary.AlertMessages) -join ' | '), $benignCount)
        }

        $severity = 'Warning'
        # Classify on the numeric level (1=Critical, 2=Error) - LevelDisplayName
        # is localized and must never be used for logic.
        if ($null -ne $summary.LevelValue -and [int]$summary.LevelValue -le 2) { $severity = 'Critical' }
        # A curated database entry may pin the severity (housekeeping events such
        # as event 29 'Orphaned OST' are logged as Warning but only carry an FYI).
        $curatedSeverity = $null
        if ($null -ne $summary.PSObject.Properties['CuratedSeverity']) { $curatedSeverity = [string]$summary.CuratedSeverity }
        if ($curatedSeverity -in @('Pass', 'Info', 'Warning', 'Critical')) { $severity = $curatedSeverity }
        $message = ("{0}x event {1}: {2}" -f $count, $summary.EventId, $summary.Meaning)
        if ($benignCount -gt 0) {
            $message += (" ({0} of {1} occurrences match known-benign noise patterns.)" -f $benignCount, $count)
        }
        if ($severity -eq 'Critical' -and $allSessionsHealthy) {
            $severity = 'Warning'
            $message += ' ' + $correlationNote
        }
        $findings.Add((New-FslFinding -Category EventLog -Check ("Event {0}" -f $summary.EventId) -Severity $severity -Target $summary.ComputerName `
                    -Message $message `
                    -Evidence $evidence `
                    -Recommendation $summary.Recommendation))
    }
    if ($eventSummaries.Count -eq 0) {
        $findings.Add((New-FslFinding -Category EventLog -Check 'FSLogix events' -Severity Pass `
                    -Message ("No warning or error events in the FSLogix channels in the last {0} hours." -f $Hours)))
    }

    # Output: report and/or pipeline.
    $severityOrder = @{ 'Critical' = 0; 'Warning' = 1; 'Info' = 2; 'Pass' = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Category, Check)

    if ($ReportPath) {
        $report = $sorted | New-FslReport -Path $ReportPath
        Write-Verbose ("Report written to {0}" -f $report.FullName)
        if (-not $PassThru) {
            return $report
        }
    }
    $sorted
}
