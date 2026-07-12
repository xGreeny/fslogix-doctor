function ConvertTo-FslLocationList {
    <#
    .SYNOPSIS
        Normalizes a VHDLocations/CCDLocations registry value into a clean list.
    .NOTES
        The value arrives as REG_MULTI_SZ (string[]) or as REG_SZ where multiple
        entries are semicolon-delimited (the documented GPO/ADMX form) - both
        shapes must yield one path per element.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return @() }

    $result = @()
    foreach ($item in @($Value)) {
        foreach ($part in (([string]$item) -split ';')) {
            $trimmed = $part.Trim()
            if ($trimmed) { $result += $trimmed }
        }
    }
    $result
}
