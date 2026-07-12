function Get-FslErrorCode {
    <#
    .SYNOPSIS
        Decodes an FSLogix error code into meaning, likely causes and recommended fixes.
    .DESCRIPTION
        Looks the code up in the curated FSLogixDoctor error-code database
        (Data\ErrorCodes.psd1). Accepts hex strings ('0x00000020'), decimal strings
        ('32'), integers (32) and symbolic names ('ERROR_SHARING_VIOLATION').

        Codes that are not in the curated database fall back to the generic Win32
        error message, so any code appearing in an FSLogix log line can be decoded.
    .PARAMETER Code
        The error code to decode. Also accepts pipeline input, including the
        ErrorCode property of Get-FslLogError output.
    .PARAMETER ListAvailable
        Lists every code in the curated database.
    .EXAMPLE
        Get-FslErrorCode 0x00000020

        Explains the classic 'profile already attached elsewhere' sharing violation.
    .EXAMPLE
        Get-FslLogError -Newest 1 | Get-FslErrorCode

        Decodes every error code found in the newest FSLogix Profile log.
    .LINK
        https://github.com/xGreeny/fslogix-doctor/blob/main/docs/error-codes.md
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ListAvailable', Justification = 'The switch selects its parameter set; the value itself is not read.')]
    [CmdletBinding(DefaultParameterSetName = 'Lookup')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Lookup', Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ErrorCode')]
        [object]$Code,

        [Parameter(ParameterSetName = 'List', Mandatory)]
        [switch]$ListAvailable
    )

    begin {
        $table = Get-FslDataTable -Name ErrorCodes

        $newResult = {
            param([string]$key, [hashtable]$entry, [bool]$inDatabase)
            [pscustomobject]@{
                PSTypeName = 'FSLogixDoctor.ErrorCode'
                Code       = $key
                Name       = $entry.Name
                Meaning    = $entry.Meaning
                Causes     = @($entry.Causes)
                Fixes      = @($entry.Fixes)
                Source     = $entry.Source
                InDatabase = $inDatabase
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'List') {
            foreach ($key in ($table.Keys | Sort-Object)) {
                & $newResult $key $table[$key] $true
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -ne 'Lookup') { return }

        # Whole objects arriving via ValueFromPipeline shadow by-property binding;
        # unwrap anything that carries an ErrorCode or Code property (e.g. output
        # of Get-FslLogError).
        $value = $Code
        if ($value -is [psobject] -and $value -isnot [string] -and $value -isnot [ValueType]) {
            if ($value.PSObject.Properties['ErrorCode']) { $value = $value.ErrorCode }
            elseif ($value.PSObject.Properties['Code']) { $value = $value.Code }
        }
        if ($null -eq $value -or ([string]$value).Trim() -eq '') {
            Write-Verbose 'Skipping pipeline object without an error code.'
            return
        }

        $key = ConvertTo-FslErrorKey -Code $value

        if ($table.ContainsKey($key)) {
            & $newResult $key $table[$key] $true
            return
        }

        # Symbolic name given: search the database by Name.
        if ($key -notmatch '^0x[0-9A-F]{8}$') {
            $match = $table.GetEnumerator() | Where-Object { $_.Value.Name -eq $key } | Select-Object -First 1
            if ($match) {
                & $newResult $match.Key $match.Value $true
                return
            }
            Write-Warning "No FSLogix error code named '$key' found in the database. Try Get-FslErrorCode -ListAvailable."
            return
        }

        # Unknown hex code: fall back to the generic Win32 message. HRESULT-wrapped
        # Win32 codes (0x8007xxxx) carry the Win32 code in the low 16 bits.
        $number = [Convert]::ToUInt32($key.Substring(2), 16)
        $win32Message = $null
        $hresultNote = ''
        # Shift instead of masking: hex literals with the sign bit set (0xFFFF0000,
        # 0x80070000) parse as negative Int32 in PowerShell and break the compare.
        if (($number -shr 16) -eq 0x8007) {
            $hresultNote = ' (HRESULT form of Win32 code {0})' -f ($number -band 0xFFFF)
            $number = $number -band 0xFFFF
        }
        if ($number -le 0xFFFF) {
            $win32Message = (New-Object System.ComponentModel.Win32Exception([int]$number)).Message + $hresultNote
        }
        $meaning = 'Unknown code (not in the curated FSLogix database)'
        if ($win32Message) { $meaning = "Win32: $win32Message (not in the curated FSLogix database)" }
        & $newResult $key @{
            Name    = $null
            Meaning = $meaning
            Causes  = @()
            Fixes   = @('Search the FSLogix logs for surrounding context lines.', 'If you identify this code, please contribute it: https://github.com/xGreeny/fslogix-doctor')
            Source  = $null
        } $false
    }
}
