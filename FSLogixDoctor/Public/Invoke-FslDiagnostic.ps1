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
    .PARAMETER ComputerName
        Fleet mode: run the diagnostic on one or more session hosts via
        PowerShell remoting and aggregate the results. FSLogixDoctor must be
        installed on each target (Install-Module FSLogixDoctor). Findings that
        are identical across hosts (typically configuration drift) are merged
        into one finding listing every affected host; host-specific findings
        stay separate. Unreachable hosts become Critical 'Fleet connectivity'
        findings instead of aborting the run.
    .PARAMETER AsSummary
        Return one FSLogixDoctor.Summary object (severity counts, worst
        severity, monitoring-friendly ExitCode, plus the findings) instead of
        the raw finding stream.
    .PARAMETER AsJson
        Like -AsSummary, but returns the summary serialized as JSON - made for
        RMM/monitoring sensors (PRTG, Zabbix, scheduled tasks).
    .PARAMETER HistoryPath
        Opt-in run history (the module stays read-only unless you ask): each run
        is written as JSON to this folder and diffed against the previous run of
        the same scope. Findings get a ChangeStatus (New/Persisting/Resolved),
        alert-worthy messages are annotated ('New since the last run', 'seen in
        N consecutive runs'), vanished Critical/Warning findings come back as
        'Resolved' Info findings, and the summary/report gain change counts.
    .PARAMETER IncludeProfileStore
        Also scan the profile store: containers at >=85% of their maximum size
        become Warnings (>=95% Critical - FSLogix's own event 33 only fires
        below 200 MB free), and structural anomalies (leftover/multi-disk
        folders) become findings. Uses the local VHDLocations unless
        -ProfileStorePath is given. In fleet mode the scan runs once from the
        coordinating machine, not per host.
    .PARAMETER ProfileStorePath
        Profile share path(s) for the store scan; implies -IncludeProfileStore.
    .EXAMPLE
        Invoke-FslDiagnostic

        Full diagnostic of the local session host, findings on the pipeline.
    .EXAMPLE
        Invoke-FslDiagnostic -Hours 4 -ReportPath C:\Temp\fslogix-report.html
    .EXAMPLE
        Invoke-FslDiagnostic -ComputerName avd-0, avd-1 -ReportPath .\fleet.html

        Fleet diagnostic of two session hosts, merged into one report.
    .EXAMPLE
        $r = Invoke-FslDiagnostic -AsSummary; exit $r.ExitCode

        Monitoring wrapper: exit 0 = healthy, 1 = warnings, 2 = critical.
    .EXAMPLE
        Invoke-FslDiagnostic -HistoryPath C:\ProgramData\FSLogixDoctor\History -ProfileStorePath \\fs01\fslogix$

        Daily driver: store capacity included, and every finding says whether
        it is new, persisting or resolved compared to yesterday.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [string]$LogPath = (Join-Path $env:ProgramData 'FSLogix\Logs'),

        [switch]$IncludeWarnings,

        [string]$ReportPath,

        [switch]$PassThru,

        [string[]]$ComputerName = @(),

        [switch]$AsSummary,

        [switch]$AsJson,

        [string]$HistoryPath,

        [switch]$IncludeProfileStore,

        [string[]]$ProfileStorePath = @()
    )

    $findings = New-Object System.Collections.Generic.List[object]

    # --- Fleet mode: fan out via PowerShell remoting, merge, then fall through
    # to the shared output section. Each host runs the normal single-host path.
    if (@($ComputerName).Count -gt 0) {
        foreach ($computer in $ComputerName) {
            $hostFindings = @()
            if ($computer -in @($env:COMPUTERNAME, 'localhost', '.')) {
                Write-Verbose ("Fleet: running locally on {0}..." -f $env:COMPUTERNAME)
                $hostFindings = @(Invoke-FslDiagnostic -Hours $Hours -LogPath $LogPath -IncludeWarnings:$IncludeWarnings)
            }
            else {
                Write-Verbose ("Fleet: running remotely on {0}..." -f $computer)
                try {
                    $remoteFindings = @(Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
                            Import-Module FSLogixDoctor -ErrorAction Stop
                            Invoke-FslDiagnostic -Hours $using:Hours -IncludeWarnings:$using:IncludeWarnings
                        })
                    # Rebuild as clean local finding objects - Invoke-Command
                    # tacks PSComputerName/RunspaceId metadata onto everything
                    # it returns, which pollutes the merged output.
                    $hostFindings = @($remoteFindings | ForEach-Object {
                            New-FslFinding -Category ([string]$_.Category) -Check ([string]$_.Check) -Severity ([string]$_.Severity) `
                                -Target ([string]$_.Target) -Message ([string]$_.Message) -Evidence ([string]$_.Evidence) `
                                -Recommendation ([string]$_.Recommendation) -HelpUri ([string]$_.HelpUri)
                        })
                }
                catch {
                    $hostFindings = @(New-FslFinding -Category Environment -Check 'Fleet connectivity' -Severity Critical -Target $computer `
                            -Message ("Could not run the diagnostic on '{0}': {1}" -f $computer, $_.Exception.Message) `
                            -Recommendation 'Verify PowerShell remoting is enabled on the target (Enable-PSRemoting) and that FSLogixDoctor is installed there: Install-Module FSLogixDoctor.')
                }
            }
            foreach ($hostFinding in $hostFindings) { $findings.Add($hostFinding) }
        }

        $merged = @(Merge-FslFleetFinding -Finding $findings.ToArray())
        $findings = New-Object System.Collections.Generic.List[object]
        foreach ($mergedFinding in $merged) { $findings.Add($mergedFinding) }

        # Fleet mode compares findings; two hosts with different raw settings,
        # each unremarkable on its own, only surface via the drift check.
        if (@($ComputerName).Count -gt 1) {
            Write-Verbose 'Comparing core FSLogix settings across the fleet...'
            foreach ($driftFinding in @(Get-FslFleetConfigDrift -ComputerName $ComputerName)) { $findings.Add($driftFinding) }
        }
    }
    else {
        foreach ($localFinding in @(Invoke-FslLocalDiagnostic -Hours $Hours -LogPath $LogPath -IncludeWarnings:$IncludeWarnings)) {
            $findings.Add($localFinding)
        }
    }

    # Opt-in profile store scan - runs once (on the coordinating machine in
    # fleet mode), not per host.
    if ($IncludeProfileStore -or @($ProfileStorePath | Where-Object { $_ }).Count -gt 0) {
        Write-Verbose 'Scanning the profile store...'
        foreach ($storeFinding in @(Get-FslProfileStoreFinding -Path $ProfileStorePath)) { $findings.Add($storeFinding) }
    }

    # Opt-in run history: tag New/Persisting, resurface vanished alerts as
    # Resolved, persist this run for the next diff.
    if ($HistoryPath) {
        $historyScope = $env:COMPUTERNAME
        if (@($ComputerName).Count -gt 0) { $historyScope = ((@($ComputerName) | Sort-Object) -join ',') }
        $tracked = @(Update-FslRunHistory -Finding $findings.ToArray() -HistoryPath $HistoryPath -Scope $historyScope)
        $findings = New-Object System.Collections.Generic.List[object]
        foreach ($trackedFinding in $tracked) { $findings.Add($trackedFinding) }
    }

    # Output: report, summary/JSON and/or pipeline.
    $severityOrder = @{ 'Critical' = 0; 'Warning' = 1; 'Info' = 2; 'Pass' = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Category, Check)

    if ($ReportPath) {
        $report = $sorted | New-FslReport -Path $ReportPath -LookbackHours $Hours
        Write-Verbose ("Report written to {0}" -f $report.FullName)
        if (-not $PassThru -and -not $AsSummary -and -not $AsJson) {
            return $report
        }
    }

    if ($AsSummary -or $AsJson) {
        $counts = @{}
        foreach ($severityName in @('Critical', 'Warning', 'Info', 'Pass')) {
            $counts[$severityName] = @($sorted | Where-Object Severity -eq $severityName).Count
        }
        # Worst severity maps to a monitoring-friendly exit code:
        # 0 = healthy (Pass/Info only), 1 = warnings, 2 = critical.
        $worst = 'None'
        $exitCode = 0
        if ($counts['Critical'] -gt 0) { $worst = 'Critical'; $exitCode = 2 }
        elseif ($counts['Warning'] -gt 0) { $worst = 'Warning'; $exitCode = 1 }
        elseif ($counts['Info'] -gt 0) { $worst = 'Info' }
        elseif ($counts['Pass'] -gt 0) { $worst = 'Pass' }

        $summaryObject = [pscustomobject]@{
            PSTypeName    = 'FSLogixDoctor.Summary'
            Target        = ((@($sorted | ForEach-Object { [string]$_.Target } | Select-Object -Unique | Sort-Object)) -join ', ')
            GeneratedAt   = Get-Date
            CriticalCount = $counts['Critical']
            WarningCount  = $counts['Warning']
            InfoCount     = $counts['Info']
            PassCount     = $counts['Pass']
            WorstSeverity = $worst
            ExitCode      = $exitCode
            NewCount      = @($sorted | Where-Object { $null -ne $_.PSObject.Properties['ChangeStatus'] -and $_.ChangeStatus -eq 'New' -and $_.Severity -in @('Critical', 'Warning') }).Count
            ResolvedCount = @($sorted | Where-Object { $null -ne $_.PSObject.Properties['ChangeStatus'] -and $_.ChangeStatus -eq 'Resolved' }).Count
            Findings      = $sorted
        }
        if ($AsJson) {
            return ($summaryObject | ConvertTo-Json -Depth 5)
        }
        return $summaryObject
    }

    $sorted
}
