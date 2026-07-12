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

            [pscustomobject]@{
                PSTypeName     = 'FSLogixDoctor.EventSummary'
                ComputerName   = $computer
                EventId        = [int]$group.Name
                Count          = $group.Count
                Level          = ($sorted | Select-Object -Last 1).LevelDisplayName
                LevelValue     = $mostSevereLevel
                Meaning        = $meaning
                Recommendation = $recommendation
                FirstSeen      = ($sorted | Select-Object -First 1).TimeCreated
                LastSeen       = ($sorted | Select-Object -Last 1).TimeCreated
                SampleMessage  = $sample
            }
        }
    }
}
