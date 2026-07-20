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
        $html | Should -Match '(?s)<div class="tile critical hot"><div class="num">2</div>'
        $html | Should -Match '(?s)<div class="tile warning hot"><div class="num">1</div>'
        # Zero counts render muted, never with a color accent.
        $html | Should -Match '(?s)<div class="tile info zero"><div class="num">0</div>'
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
        $html | Should -Match '<h2>Configuration<span class="count">'
        $html | Should -Match '<h2>EventLog<span class="count">'
    }

    It 'honors -WhatIf without writing a file' {
        $path = Join-Path $TestDrive 'whatif.html'
        @(New-TestFinding) | New-FslReport -Path $path -WhatIf
        Test-Path $path | Should -BeFalse
    }

    Context 'fleet-aware rendering' {

        It 'derives the default title from the single target host' {
            $path = Join-Path $TestDrive 'title-single.html'
            @(New-TestFinding) | New-FslReport -Path $path | Out-Null
            (Get-Content $path -Raw) | Should -Match '<title>FSLogix Health Report - LAB-SH-01</title>'
        }

        It 'uses a fleet title and host chips when findings span multiple hosts' {
            $path = Join-Path $TestDrive 'title-fleet.html'
            $findings = @(
                New-TestFinding -Severity Warning
                New-TestFinding -Severity Pass
            )
            $findings[1].Target = 'LAB-SH-02'
            $findings | New-FslReport -Path $path | Out-Null
            $html = Get-Content $path -Raw
            $html | Should -Match '<title>FSLogix Fleet Report - 2 hosts</title>'
            $html | Should -Match 'hostchip"><span class="sev warning"><span class="glyph">[^<]+</span></span>LAB-SH-01'
            $html | Should -Match 'hostchip"><span class="sev pass"><span class="glyph">[^<]+</span></span>LAB-SH-02'
        }

        It 'derives hosts only from host-like targets - shares and users never become chips' {
            $path = Join-Path $TestDrive 'hosts-filtered.html'
            $findings = @(
                New-TestFinding -Severity Warning
                New-TestFinding -Severity Pass
                New-TestFinding -Severity Warning -Category 'ProfileStore'
                New-TestFinding -Severity Warning -Category 'SessionState'
            )
            $findings[1].Target = 'LAB-SH-02'
            $findings[2].Target = '\\fs01\fslogix$'
            $findings[3].Target = 'LAB\mmuster'
            $findings | New-FslReport -Path $path | Out-Null
            $html = Get-Content $path -Raw
            $html | Should -Match '<title>FSLogix Fleet Report - 2 hosts</title>'
            $chipRow = ([regex]::Match($html, '<div class="hosts">.*?</div>')).Value
            $chipRow | Should -Match 'LAB-SH-01'
            $chipRow | Should -Match 'LAB-SH-02'
            $chipRow | Should -Not -Match 'fslogix\$'
            $chipRow | Should -Not -Match 'mmuster'
        }

        It 'falls back to raw targets when no host-like targets exist' {
            $path = Join-Path $TestDrive 'hosts-fallback.html'
            $storeFinding = New-TestFinding -Severity Warning -Category 'ProfileStore'
            $storeFinding.Target = '\\fs01\fslogix$'
            @($storeFinding) | New-FslReport -Path $path | Out-Null
            (Get-Content $path -Raw) | Should -Match '<title>FSLogix Health Report - '
        }

        It 'omits host chips for single-host reports' {
            $path = Join-Path $TestDrive 'chips-single.html'
            @(New-TestFinding) | New-FslReport -Path $path | Out-Null
            # The .hostchip CSS class is always in the stylesheet; only the
            # rendered chip markup must be absent.
            (Get-Content $path -Raw) | Should -Not -Match '<span class="hostchip'
        }
    }

    Context 'action items and readability' {

        It 'lists Critical and Warning findings in the action items section' {
            $path = Join-Path $TestDrive 'actions.html'
            @(
                New-TestFinding -Severity Critical
                New-TestFinding -Severity Pass
            ) | New-FslReport -Path $path | Out-Null
            $html = Get-Content $path -Raw
            $html | Should -Match '<h2>Action items<span class="count">1</span></h2>'
            $html | Should -Match '(?s)<h2>Action items<span.*Do the thing'
        }

        It 'omits the action items section when nothing needs a human' {
            $path = Join-Path $TestDrive 'no-actions.html'
            @(New-TestFinding -Severity Pass) | New-FslReport -Path $path | Out-Null
            # The verdict sub line legitimately says '0 action items'; only the
            # heading and its table must be absent.
            (Get-Content $path -Raw) | Should -Not -Match '<h2>Action items'
        }

        It 'collapses long messages behind a details element' {
            $path = Join-Path $TestDrive 'collapse.html'
            $longMessage = ('This curated meaning is deliberately verbose. ' * 12)
            @(New-TestFinding -Message $longMessage) | New-FslReport -Path $path | Out-Null
            (Get-Content $path -Raw) | Should -Match '<details class="msg"><summary>'
        }

        It 'keeps short messages as plain divs' {
            $path = Join-Path $TestDrive 'no-collapse.html'
            @(New-TestFinding -Message 'Short and sweet.') | New-FslReport -Path $path | Out-Null
            (Get-Content $path -Raw) | Should -Not -Match '<details class="msg">'
        }

        It 'shows the look-back window in the header when provided' {
            $path = Join-Path $TestDrive 'lookback.html'
            @(New-TestFinding) | New-FslReport -Path $path -LookbackHours 8 | Out-Null
            (Get-Content $path -Raw) | Should -Match 'last 8h window'
        }
    }
}
