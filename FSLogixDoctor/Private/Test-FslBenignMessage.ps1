function Test-FslBenignMessage {
    <#
    .SYNOPSIS
        Matches a log or event message against the known-benign noise patterns
        (Data\BenignPatterns.psd1). Returns the matching entry with its reason,
        or $null when the message is alert-worthy.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return $null }

    $table = Get-FslDataTable -Name BenignPatterns
    foreach ($entry in $table.Patterns) {
        if ($Message -like $entry.Pattern) {
            return [pscustomobject]@{
                PSTypeName = 'FSLogixDoctor.BenignMatch'
                Pattern    = $entry.Pattern
                Reason     = $entry.Reason
            }
        }
    }
    $null
}
