function Invoke-FslLocalDiagnostic {
    <#
    .SYNOPSIS
        Runs the single-host diagnostic pipeline (configuration, sessions, logs,
        events, plus the session-state correlation) and returns the unsorted
        findings. Shared by Invoke-FslDiagnostic for the local and fleet paths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [string]$LogPath = (Join-Path $env:ProgramData 'FSLogix\Logs'),

        [switch]$IncludeWarnings
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

    # Same correlation for the share-reachability probe: sessions that are
    # attached right now from the 'unreachable' share contradict an outage.
    # Only applies when TCP 445 answered - a closed SMB port stays Critical
    # because the attached sessions may predate a real network break.
    if ($allSessionsHealthy) {
        $probeFindings = @($findings | Where-Object { $_.Check -eq 'VHDLocations reachable' -and $_.Severity -eq 'Critical' -and $_.Evidence -like '*TCP 445*is open*' })
        foreach ($probeFinding in $probeFindings) {
            if ($probeFinding.Evidence -like '*remote (WinRM) session*') {
                # Fleet mode: the second hop is blocked by design; with healthy
                # sessions this is expected mechanics, not even a warning.
                $probeFinding.Severity = 'Info'
                $probeFinding.Message += (" Downgraded to Info: {0} session(s) are attached, TCP 445 is open and the probe ran in a remote session where the second hop to the file server is blocked by Kerberos - expected in fleet mode." -f $sessions.Count)
            }
            else {
                $probeFinding.Severity = 'Warning'
                $probeFinding.Message += (" Downgraded from Critical: {0} session(s) are currently attached from this location and TCP 445 is open - the probing account likely lacks share permissions (typical for Azure Files identity-based auth), not an outage." -f $sessions.Count)
            }
        }
    }

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

        # Name the channel so a follow-up Get-WinEvent does not have to guess
        # between Operational and Admin.
        $lastSeenLabel = ("Last seen {0}" -f $summary.LastSeen)
        if ($null -ne $summary.PSObject.Properties['Channel'] -and $summary.Channel) {
            $lastSeenLabel += (" in {0}" -f $summary.Channel)
        }

        $evidence = ("{0}. Sample: {1}" -f $lastSeenLabel, $summary.SampleMessage)
        if ($null -ne $summary.PSObject.Properties['TopMessages'] -and @($summary.TopMessages).Count -gt 0) {
            $evidence = ("{0}. Messages: {1}" -f $lastSeenLabel, (@($summary.TopMessages) -join ' | '))
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
            $evidence = ("{0}. Alert-worthy: {1}. Plus {2}x known-benign noise." -f $lastSeenLabel, (@($summary.AlertMessages) -join ' | '), $benignCount)
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

    # 6: Curated context events from the surrounding Windows logs (User Profile
    # Service, NTFS, disk) - and correlate them with the FSLogix findings above
    # so symptom and cause land in one place instead of two log worlds.
    Write-Verbose 'Checking the surrounding Windows event logs...'
    $contextEvents = @(Get-FslContextEvent -After $after -WarningAction SilentlyContinue)
    $hasAttachTrouble = ($unhealthy.Count -gt 0 -or
        @($findings | Where-Object { $_.Category -in @('LogFile', 'EventLog') -and $_.Severity -in @('Critical', 'Warning') }).Count -gt 0)
    $hasVolumeTrouble = (@($findings | Where-Object { $_.Check -like '*0x0000A418*' -or $_.Check -eq 'Event 33' }).Count -gt 0)

    foreach ($contextEvent in $contextEvents) {
        $message = ("{0}x event {1} in the {2} log: {3}" -f $contextEvent.Count, $contextEvent.EventId, $contextEvent.Channel, $contextEvent.Meaning)
        if ($contextEvent.EventId -in @(1511, 1515) -and $contextEvent.Key -like 'ProfSvc*') {
            if ($hasAttachTrouble) {
                $message += ' Correlates with the FSLogix findings in this report: the temporary profile is the visible symptom, the attach failure above is the likely cause.'
            }
            else {
                $message += ' No matching FSLogix attach failure in this window - the temp profile may stem from a non-FSLogix local profile problem.'
            }
        }
        elseif ($contextEvent.Key -in @('Ntfs:55', 'Disk:7') -and $hasVolumeTrouble) {
            $message += ' Independent confirmation of the container volume-error findings (ErrCode 42008 / event 33) in this report.'
        }
        $findings.Add((New-FslFinding -Category ContextEvents -Check ("{0} event {1}" -f $contextEvent.Label, $contextEvent.EventId) -Severity $contextEvent.Severity -Target $contextEvent.ComputerName `
                    -Message $message `
                    -Evidence ("Last seen {0} in {1}. Messages: {2}" -f $contextEvent.LastSeen, $contextEvent.Channel, (@($contextEvent.TopMessages) -join ' | ')) `
                    -Recommendation $contextEvent.Recommendation))
    }
    if ($contextEvents.Count -eq 0) {
        $findings.Add((New-FslFinding -Category ContextEvents -Check 'Context events' -Severity Pass `
                    -Message ("No profile-related events in the surrounding Windows logs (User Profile Service, NTFS, disk) in the last {0} hours." -f $Hours)))
    }

    $findings
}
