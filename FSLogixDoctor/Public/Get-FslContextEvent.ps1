function Get-FslContextEvent {
    <#
    .SYNOPSIS
        Queries the curated profile-related events from the Windows logs AROUND
        FSLogix (User Profile Service, NTFS, disk) - the places FSLogix findings
        used to send you to manually.
    .DESCRIPTION
        Reads the curated context-event database (Data\ContextEvents.psd1) and
        queries each entry's channel for its event ID within the window,
        filtering by provider (the same ID exists under several providers in
        Application/System). Returns one bucket per event kind and computer,
        enriched with the curated meaning, causes-derived recommendation and a
        digit-collapsed message breakdown.

        Deliberately a short curated list, not a log dump: temp-profile chain
        (1511/1515), handle leaks at logoff (1530), undeletable profiles (1533),
        filesystem corruption (NTFS 55) and disk-level I/O trouble (7/153).
    .PARAMETER ComputerName
        One or more hosts to query. Defaults to the local machine.
    .PARAMETER After
        Only consider events newer than this timestamp. Defaults to the last 24 hours.
    .EXAMPLE
        Get-FslContextEvent -After (Get-Date).AddHours(-8)
    .EXAMPLE
        Invoke-FslDiagnostic

        Invoke-FslDiagnostic queries the context events automatically and
        correlates them with the FSLogix findings.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [datetime]$After = (Get-Date).AddHours(-24)
    )

    $table = Get-FslDataTable -Name ContextEvents

    foreach ($computer in $ComputerName) {
        foreach ($entry in $table.Events) {
            $events = @()
            try {
                $getParams = @{
                    FilterHashtable = @{ LogName = [string]$entry.LogName; Id = [int]$entry.Id; StartTime = $After }
                    ErrorAction     = 'Stop'
                }
                if ($computer -ne $env:COMPUTERNAME) { $getParams['ComputerName'] = $computer }
                $events = @(Get-WinEvent @getParams)
            }
            catch {
                # Locale-independent detection of the 'no events match' case.
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { continue }
                Write-Warning ("Could not query '{0}' for event {1} on '{2}': {3}" -f $entry.LogName, $entry.Id, $computer, $_.Exception.Message)
                continue
            }

            # The same ID exists under several providers; only the curated one counts.
            $events = @($events | Where-Object { [string]$_.ProviderName -like [string]$entry.ProviderPattern })
            if ($events.Count -eq 0) { continue }

            $sorted = @($events | Sort-Object TimeCreated)
            $sample = ($sorted | Select-Object -Last 1).Message
            if ($sample -and $sample.Length -gt 400) { $sample = $sample.Substring(0, 400) + '...' }
            $messages = @($sorted | ForEach-Object { $_.Message })

            [pscustomobject]@{
                PSTypeName     = 'FSLogixDoctor.ContextEvent'
                ComputerName   = $computer
                Key            = [string]$entry.Key
                Label          = [string]$entry.Label
                Channel        = [string]$entry.LogName
                Provider       = [string](($sorted | Select-Object -First 1).ProviderName)
                EventId        = [int]$entry.Id
                Count          = $sorted.Count
                Severity       = [string]$entry.Severity
                Meaning        = [string]$entry.Meaning
                Recommendation = (@($entry.Fixes) -join ' ')
                FirstSeen      = ($sorted | Select-Object -First 1).TimeCreated
                LastSeen       = ($sorted | Select-Object -Last 1).TimeCreated
                SampleMessage  = $sample
                TopMessages    = @(Get-FslMessageBreakdown -Message $messages)
            }
        }
    }
}
