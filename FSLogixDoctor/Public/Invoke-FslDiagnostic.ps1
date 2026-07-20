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

        [switch]$AsJson
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
    }
    else {
        foreach ($localFinding in @(Invoke-FslLocalDiagnostic -Hours $Hours -LogPath $LogPath -IncludeWarnings:$IncludeWarnings)) {
            $findings.Add($localFinding)
        }
    }

    # Output: report, summary/JSON and/or pipeline.
    $severityOrder = @{ 'Critical' = 0; 'Warning' = 1; 'Info' = 2; 'Pass' = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Category, Check)

    if ($ReportPath) {
        $report = $sorted | New-FslReport -Path $ReportPath
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
            Findings      = $sorted
        }
        if ($AsJson) {
            return ($summaryObject | ConvertTo-Json -Depth 5)
        }
        return $summaryObject
    }

    $sorted
}
