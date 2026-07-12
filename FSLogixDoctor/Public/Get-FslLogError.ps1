function Get-FslLogError {
    <#
    .SYNOPSIS
        Parses FSLogix log files and returns structured warning/error entries.
    .DESCRIPTION
        Reads the FSLogix text logs (default %ProgramData%\FSLogix\Logs), extracts
        WARN/ERROR lines including embedded error codes, and returns one object per
        entry. Pipe the result to Get-FslErrorCode to decode the codes, or into
        New-FslReport via Invoke-FslDiagnostic.
    .PARAMETER Path
        Root log directory. Defaults to %ProgramData%\FSLogix\Logs.
    .PARAMETER Component
        Which log component subfolder(s) to parse. Defaults to Profile and ODFC.
    .PARAMETER After
        Only return entries newer than this timestamp. Defaults to the last 24 hours.
    .PARAMETER Newest
        Only parse the newest N log files per component (after the After filter on
        file write time). Defaults to all matching files.
    .PARAMETER IncludeWarnings
        Include WARN entries in addition to ERROR entries.
    .EXAMPLE
        Get-FslLogError -After (Get-Date).AddHours(-4)
    .EXAMPLE
        Get-FslLogError -IncludeWarnings | Group-Object ErrorCode | Sort-Object Count -Descending
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path = (Join-Path $env:ProgramData 'FSLogix\Logs'),

        [ValidateSet('Profile', 'ODFC', 'All')]
        [string]$Component = 'All',

        [datetime]$After = (Get-Date).AddHours(-24),

        [int]$Newest = 0,

        [switch]$IncludeWarnings
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Log path '$Path' not found. FSLogix is not installed or logging is disabled."
        return
    }

    $folders = @()
    if ($Component -in @('Profile', 'All')) { $folders += 'Profile' }
    if ($Component -in @('ODFC', 'All')) { $folders += 'ODFC' }

    # FSLogix log lines carry a time but no date; the date comes from the file name
    # (e.g. Profile-20260712.log) with the file write date as fallback.
    # Level markers per Microsoft: [WARN: xxxxxxxx] has a space after the colon,
    # [ERROR:xxxxxxxx] does not. Codes are Windows system error codes in hex,
    # sometimes in HRESULT form (8007xxxx).
    $levelPattern = '\[(?<level>ERROR|WARN)(?::\s*(?<code>[0-9a-fA-F]{8}))?\s*\]'
    $timePattern = '^\[(?<time>\d{2}:\d{2}:\d{2}(?:\.\d+)?)\]'
    $inlineCodePattern = '(?<inline>0x[0-9a-fA-F]{8})'

    foreach ($folder in $folders) {
        $folderPath = Join-Path $Path $folder
        if (-not (Test-Path -LiteralPath $folderPath)) { continue }

        $allFiles = Get-ChildItem -LiteralPath $folderPath -Filter '*.log' -File -ErrorAction SilentlyContinue
        $files = @($allFiles | Where-Object { $_.LastWriteTime -ge $After } | Sort-Object LastWriteTime -Descending)
        if ($Newest -gt 0) { $files = @($files | Select-Object -First $Newest) }

        foreach ($file in $files) {
            $fileDate = $file.LastWriteTime.Date
            if ($file.BaseName -match '(?<date>\d{8})') {
                try {
                    $fileDate = [datetime]::ParseExact($Matches['date'], 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
                }
                catch {
                    Write-Verbose "File name '$($file.Name)' contains no parsable date; using last write date."
                }
            }

            $lineNumber = 0
            # Entries written after midnight land in the previous day's file until
            # FSLogix rolls to a new one; when the time-of-day decreases between
            # entries, advance the date by a day.
            $dayOffset = 0
            $lastTimeOfDay = $null
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                $lineNumber++
                if ($line -notmatch $levelPattern) { continue }
                $level = $Matches['level']
                $code = $Matches['code']
                if ($level -eq 'WARN' -and -not $IncludeWarnings) { continue }

                $timestamp = $fileDate
                if ($line -match $timePattern) {
                    $timeText = $Matches['time']
                    $parsed = [datetime]::MinValue
                    # The [string[]] cast is required: without it PS 5.1 binds the
                    # single-format overload and the parse silently fails. FFFFFFF
                    # accepts 1-7 fractional-second digits.
                    $formats = [string[]]@('HH\:mm\:ss.FFFFFFF', 'HH\:mm\:ss')
                    if ([datetime]::TryParseExact($timeText, $formats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                        if ($null -ne $lastTimeOfDay -and $parsed.TimeOfDay -lt $lastTimeOfDay) {
                            $dayOffset++
                        }
                        $lastTimeOfDay = $parsed.TimeOfDay
                        $timestamp = $fileDate.AddDays($dayOffset).Add($parsed.TimeOfDay)
                    }
                    else {
                        Write-Verbose ("Could not parse time '{0}' in {1}:{2}; using the file date." -f $timeText, $file.Name, $lineNumber)
                    }
                }
                if ($timestamp -lt $After) { continue }

                # Strip the bracketed prefix blocks to isolate the message text.
                $message = ($line -replace '^(\[[^\]]*\])+', '').Trim()

                if (-not $code -and $line -match $inlineCodePattern) {
                    $code = $Matches['inline'].Substring(2)
                }
                $normalizedCode = $null
                if ($code) { $normalizedCode = '0x{0}' -f $code.ToUpperInvariant() }

                [pscustomobject]@{
                    PSTypeName = 'FSLogixDoctor.LogEntry'
                    Timestamp  = $timestamp
                    Component  = $folder
                    Level      = $level
                    ErrorCode  = $normalizedCode
                    Message    = $message
                    File       = $file.FullName
                    LineNumber = $lineNumber
                }
            }
        }
    }
}
