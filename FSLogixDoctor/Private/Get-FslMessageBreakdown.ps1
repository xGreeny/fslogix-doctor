function Get-FslMessageBreakdown {
    <#
    .SYNOPSIS
        Groups raw log/event messages into distinct patterns (digits collapsed so
        session ids, PIDs and counters do not split groups) and returns the top-N
        as 'countx message' strings for use in finding evidence.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Message = @(),

        [ValidateRange(1, 10)]
        [int]$Top = 3,

        [ValidateRange(40, 400)]
        [int]$MaxLength = 160
    )

    $groups = @($Message |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Group-Object { $_ -replace '\d+', '#' } |
            Sort-Object -Property Count -Descending)

    foreach ($group in ($groups | Select-Object -First $Top)) {
        $sample = [string]($group.Group | Select-Object -First 1)
        if ($sample.Length -gt $MaxLength) { $sample = $sample.Substring(0, $MaxLength) + '...' }
        '{0}x {1}' -f $group.Count, $sample
    }
    if ($groups.Count -gt $Top) {
        '(+{0} more message pattern(s))' -f ($groups.Count - $Top)
    }
}
