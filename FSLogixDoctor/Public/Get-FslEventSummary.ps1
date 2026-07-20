function Get-FslEventSummary {
    <#
    .SYNOPSIS
        Summarizes FSLogix events from the Windows event logs, bucketed by event ID
        and translated via the curated event database.
    .DESCRIPTION
        Queries the FSLogix event channels (Operational and Admin), groups the events
        by ID and enriches each bucket with the plain-English explanation from
        Data\EventIds.psd1. Ideal for spotting login-storm patterns across a host.
    .PARAMETER ComputerName
        One or more session hosts to query. Defaults to the local machine.
    .PARAMETER After
        Only consider events newer than this timestamp. Defaults to the last 24 hours.
    .PARAMETER MinimumLevel
        'Error' returns only error events, 'Warning' also warnings (default),
        'Information' everything.
    .EXAMPLE
        Get-FslEventSummary -After (Get-Date).AddHours(-8)
    .EXAMPLE
        Get-FslEventSummary -ComputerName avd-sh-01, avd-sh-02 -MinimumLevel Error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [datetime]$After = (Get-Date).AddHours(-24),

        [ValidateSet('Error', 'Warning', 'Information')]
        [string]$MinimumLevel = 'Warning',

        [switch]$IncludeCloudCache
    )

    $eventTable = Get-FslDataTable -Name EventIds

    # Event level values: 1=Critical, 2=Error, 3=Warning, 4=Information
    $maxLevel = switch ($MinimumLevel) {
        'Error' { 2 }
        'Warning' { 3 }
        'Information' { 4 }
    }

    $channels = @('Microsoft-FSLogix-Apps/Operational', 'Microsoft-FSLogix-Apps/Admin')
    if ($IncludeCloudCache) {
        $channels += @('Microsoft-FSLogix-CloudCache/Operational', 'Microsoft-FSLogix-CloudCache/Admin')
    }

    foreach ($computer in $ComputerName) {
        $events = @()
        foreach ($channel in $channels) {
            $filter = @{
                LogName   = $channel
                StartTime = $After
                Level     = @(1..$maxLevel)
            }
            try {
                $getParams = @{ FilterHashtable = $filter; ErrorAction = 'Stop' }
                if ($computer -ne $env:COMPUTERNAME) { $getParams['ComputerName'] = $computer }
                $events += @(Get-WinEvent @getParams)
            }
            catch {
                # Locale-independent detection of the 'no events match' case.
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                    Write-Verbose "No matching events in '$channel' on '$computer'."
                }
                else {
                    Write-Warning "Could not query '$channel' on '$computer': $($_.Exception.Message)"
                }
            }
        }

        foreach ($group in ($events | Group-Object Id | Sort-Object Count -Descending)) {
            $eventId = [string]$group.Name
            $known = $null
            if ($eventTable.ContainsKey($eventId)) { $known = $eventTable[$eventId] }

            $sorted = @($group.Group | Sort-Object TimeCreated)
            $sample = ($sorted | Select-Object -Last 1).Message
            if ($sample -and $sample.Length -gt 400) { $sample = $sample.Substring(0, 400) + '...' }

            # LevelDisplayName is localized ('Fehler' on German Windows) - keep it
            # for display only and carry the numeric level for classification
            # (1=Critical, 2=Error, 3=Warning, 4=Information). Use the most severe
            # level present in the bucket; ignore 0 (LogAlways).
            $levelValues = @($sorted | ForEach-Object { [int]$_.Level } | Where-Object { $_ -gt 0 })
            $mostSevereLevel = 4
            if ($levelValues.Count -gt 0) {
                $mostSevereLevel = ($levelValues | Measure-Object -Minimum).Minimum
            }

            $meaning = 'Not in the curated FSLogixDoctor event database.'
            $recommendation = ''
            if ($known) {
                $meaning = $known.Meaning
                $recommendation = ($known.Fixes -join ' ')
            }

            # Generic-error IDs (notably event 26) reuse one ID for many different
            # messages; classify each message so known-benign noise can be told
            # apart from real failures. AlertMessages carries only the
            # alert-worthy breakdown - in a mixed bucket the one real message
            # must never drown in the noise counts.
            $messages = @($sorted | ForEach-Object { $_.Message })
            $benignCount = 0
            $alertRaw = New-Object System.Collections.Generic.List[string]
            foreach ($messageText in $messages) {
                if (-not $messageText) { continue }
                if (Test-FslBenignMessage -Message $messageText) { $benignCount++ }
                else { $alertRaw.Add($messageText) }
            }
            $topMessages = @(Get-FslMessageBreakdown -Message $messages)
            $alertMessages = @(Get-FslMessageBreakdown -Message $alertRaw.ToArray() -Top 5)

            # A curated entry may pin the severity (e.g. housekeeping events that
            # Windows logs as Warning but that only carry an FYI).
            $curatedSeverity = $null
            if ($known -and $known.ContainsKey('Severity')) { $curatedSeverity = [string]$known.Severity }

            [pscustomobject]@{
                PSTypeName      = 'FSLogixDoctor.EventSummary'
                ComputerName    = $computer
                EventId         = [int]$group.Name
                Count           = $group.Count
                BenignCount     = $benignCount
                Level           = ($sorted | Select-Object -Last 1).LevelDisplayName
                LevelValue      = $mostSevereLevel
                CuratedSeverity = $curatedSeverity
                Meaning         = $meaning
                Recommendation  = $recommendation
                FirstSeen       = ($sorted | Select-Object -First 1).TimeCreated
                LastSeen        = ($sorted | Select-Object -Last 1).TimeCreated
                SampleMessage   = $sample
                TopMessages     = $topMessages
                AlertMessages   = $alertMessages
            }
        }
    }
}
