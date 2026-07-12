function ConvertTo-FslErrorKey {
    <#
    .SYNOPSIS
        Normalizes an error code given as int, hex string, decimal string or symbolic
        name into the canonical lookup key ('0x00000005' or 'ERROR_ACCESS_DENIED').
    .NOTES
        Negative values are treated as signed 32-bit representations of HRESULTs
        (e.g. -2147024891 = 0x80070005, how .NET and event data surface them) and
        are mapped into unsigned space via two's complement.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Code
    )

    $numericValue = $null

    if ($Code -is [byte] -or $Code -is [int16] -or $Code -is [int] -or $Code -is [long] -or
        $Code -is [uint16] -or $Code -is [uint32] -or $Code -is [uint64]) {
        $numericValue = [int64]$Code
    }
    else {
        $text = ([string]$Code).Trim()
        if ($text -match '^0x(?<hex>[0-9a-fA-F]{1,8})$') {
            return '0x{0:X8}' -f [Convert]::ToUInt32($Matches['hex'], 16)
        }
        if ($text -match '^-?[0-9]+$') {
            try {
                $numericValue = [int64]$text
            }
            catch {
                return $text.ToUpperInvariant()
            }
        }
        else {
            # Not numeric: treat as a symbolic name such as ERROR_ACCESS_DENIED.
            return $text.ToUpperInvariant()
        }
    }

    # Two's-complement wrap for negative Int32 HRESULTs; masking also guards
    # against out-of-range positives. Decimal constant on purpose: the hex
    # literal 0xFFFFFFFF parses as Int32 -1 in PowerShell and sign-extends.
    '0x{0:X8}' -f [uint32]($numericValue -band 4294967295)
}
