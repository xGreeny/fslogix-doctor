BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    function New-TestFinding {
        param(
            [string]$Severity = 'Warning',
            [string]$Message = 'Something happened',
            [string]$Category = 'Configuration'
        )
        [pscustomobject]@{
            PSTypeName     = 'FSLogixDoctor.Finding'
            Category       = $Category
            Check          = 'Test check'
            Severity       = $Severity
            Target         = 'LAB-SH-01'
            Message        = $Message
            Evidence       = 'Some evidence'
            Recommendation = 'Do the thing'
            HelpUri        = 'https://example.org/docs'
        }
    }
}

Describe 'New-FslReport' {

    It 'writes a self-contained HTML file and returns the FileInfo' {
        $path = Join-Path $TestDrive 'report.html'
        $result = @(New-TestFinding) | New-FslReport -Path $path
        $result | Should -BeOfType [System.IO.FileInfo]
        Test-Path $path | Should -BeTrue
        $html = Get-Content $path -Raw
        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Not -Match '<script src'
    }

    It 'counts findings per severity in the summary tiles' {
        $path = Join-Path $TestDrive 'counts.html'
        $findings = @(
            New-TestFinding -Severity Critical
            New-TestFinding -Severity Critical
            New-TestFinding -Severity Warning
            New-TestFinding -Severity Pass
        )
        $findings | New-FslReport -Path $path | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Match '(?s)<div class="tile critical"><div class="num">2</div>'
        $html | Should -Match '(?s)<div class="tile warning"><div class="num">1</div>'
    }

    It 'shows the Critical verdict when critical findings exist' {
        $path = Join-Path $TestDrive 'verdict.html'
        @(New-TestFinding -Severity Critical) | New-FslReport -Path $path | Out-Null
        (Get-Content $path -Raw) | Should -Match 'Critical issues found'
    }

    It 'shows the Healthy verdict when only Pass/Info findings exist' {
        $path = Join-Path $TestDrive 'healthy.html'
        @(New-TestFinding -Severity Pass) | New-FslReport -Path $path | Out-Null
        (Get-Content $path -Raw) | Should -Match '>Healthy<'
    }

    It 'HTML-encodes finding content to prevent injection' {
        $path = Join-Path $TestDrive 'encoded.html'
        @(New-TestFinding -Message '<script>alert(1)</script> & "quotes"') | New-FslReport -Path $path | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;'
    }

    It 'groups findings by category' {
        $path = Join-Path $TestDrive 'groups.html'
        @(
            New-TestFinding -Category 'Configuration'
            New-TestFinding -Category 'EventLog'
        ) | New-FslReport -Path $path | Out-Null
        $html = Get-Content $path -Raw
        $html | Should -Match '<h2>Configuration</h2>'
        $html | Should -Match '<h2>EventLog</h2>'
    }

    It 'honors -WhatIf without writing a file' {
        $path = Join-Path $TestDrive 'whatif.html'
        @(New-TestFinding) | New-FslReport -Path $path -WhatIf
        Test-Path $path | Should -BeFalse
    }
}
