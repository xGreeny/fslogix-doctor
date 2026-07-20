BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Get-FslErrorCode' {

    It 'decodes a curated code given as hex string' {
        $result = Get-FslErrorCode -Code '0x00000020'
        $result.Code | Should -Be '0x00000020'
        $result.Name | Should -Be 'ERROR_SHARING_VIOLATION'
        $result.InDatabase | Should -BeTrue
        $result.Meaning | Should -Not -BeNullOrEmpty
        @($result.Fixes).Count | Should -BeGreaterThan 0
    }

    It 'accepts an integer code' {
        (Get-FslErrorCode -Code 32).Code | Should -Be '0x00000020'
    }

    It 'accepts a decimal string code' {
        (Get-FslErrorCode -Code '32').Code | Should -Be '0x00000020'
    }

    It 'accepts short hex without zero padding' {
        (Get-FslErrorCode -Code '0x20').Code | Should -Be '0x00000020'
    }

    It 'accepts a symbolic name' {
        $result = Get-FslErrorCode -Code 'ERROR_SHARING_VIOLATION'
        $result.Code | Should -Be '0x00000020'
        $result.InDatabase | Should -BeTrue
    }

    It 'normalizes negative Int32 HRESULTs via two''s complement' {
        $result = Get-FslErrorCode -Code (-2147024891)  # 0x80070005 as signed Int32
        $result.Code | Should -Be '0x80070005'
        $result.Name | Should -Be 'E_ACCESSDENIED'
        $result.InDatabase | Should -BeTrue
    }

    It 'accepts a negative decimal string' {
        (Get-FslErrorCode -Code '-2147024891').Code | Should -Be '0x80070005'
    }

    It 'resolves the E_ACCESSDENIED symbolic name' {
        (Get-FslErrorCode -Code 'E_ACCESSDENIED').Code | Should -Be '0x80070005'
    }

    It 'unwraps HRESULT-form codes in the Win32 fallback' {
        $result = Get-FslErrorCode -Code '0x80070057'  # HRESULT of ERROR_INVALID_PARAMETER, not curated
        $result.InDatabase | Should -BeFalse
        $result.Meaning | Should -Match 'HRESULT form of Win32 code 87'
    }

    It 'is case-insensitive for symbolic names' {
        (Get-FslErrorCode -Code 'error_sharing_violation').Code | Should -Be '0x00000020'
    }

    It 'decodes the compaction shrink-failure code 0x0000A418' {
        $decoded = Get-FslErrorCode -Code '0x0000A418'
        $decoded.InDatabase | Should -BeTrue
        $decoded.Meaning | Should -Match 'volume with errors'
    }

    It 'falls back to the Win32 message for unknown codes' {
        $result = Get-FslErrorCode -Code '0x000004D3'  # 1235 = ERROR_REQUEST_ABORTED, unlikely to be curated
        $result.InDatabase | Should -BeFalse
        $result.Meaning | Should -Match 'not in the curated'
    }

    It 'warns instead of throwing on an unknown symbolic name' {
        $warnings = @()
        Get-FslErrorCode -Code 'ERROR_DOES_NOT_EXIST_XYZ' -WarningVariable warnings -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        $warnings.Count | Should -BeGreaterThan 0
    }

    It 'supports pipeline input from Get-FslLogError-shaped objects' {
        $entry = [pscustomobject]@{ ErrorCode = '0x00000020' }
        $result = $entry | Get-FslErrorCode
        $result.Code | Should -Be '0x00000020'
    }

    It 'lists the whole database with -ListAvailable' {
        $all = Get-FslErrorCode -ListAvailable
        $all.Count | Should -BeGreaterThan 10
        $all | ForEach-Object { $_.InDatabase | Should -BeTrue }
    }
}
