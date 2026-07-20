BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    $script:logRoot = Join-Path $TestDrive 'Logs'
    New-Item -Path (Join-Path $script:logRoot 'Profile') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $script:logRoot 'ODFC') -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot 'fixtures\Profile-20260710.log') `
        -Destination (Join-Path $script:logRoot 'Profile\Profile-20260710.log')

    $script:longAgo = Get-Date -Year 2020 -Month 1 -Day 1
}

Describe 'Get-FslLogError' {

    It 'returns only ERROR entries by default' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries.Count | Should -Be 2
        $entries | ForEach-Object { $_.Level | Should -Be 'ERROR' }
    }

    It 'includes WARN entries with -IncludeWarnings' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo -IncludeWarnings)
        $entries.Count | Should -Be 3
        @($entries | Where-Object Level -eq 'WARN').Count | Should -Be 1
    }

    It 'extracts the error code from the level marker' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries[0].ErrorCode | Should -Be '0x00000020'
    }

    It 'handles HRESULT-form codes in the marker' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries[1].ErrorCode | Should -Be '0x80070003'
    }

    It 'parses the WARN marker with its space after the colon' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo -IncludeWarnings)
        $warn = $entries | Where-Object Level -eq 'WARN'
        $warn.ErrorCode | Should -Be '0x00000020'
    }

    It 'derives the entry date from the log file name' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries[0].Timestamp.Date | Should -Be ([datetime]'2026-07-10').Date
        $entries[0].Timestamp.Hour | Should -Be 7
    }

    It 'strips the bracket prefix from the message' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries[0].Message | Should -Match '^Failed to open virtual disk'
        $entries[0].Message | Should -Not -Match '\[tid:'
    }

    It 'records file and line number for every entry' {
        $entries = @(Get-FslLogError -Path $script:logRoot -After $script:longAgo)
        $entries[0].File | Should -Match 'Profile-20260710\.log$'
        $entries[0].LineNumber | Should -BeGreaterThan 0
    }

    It 'respects the After filter against entry timestamps' {
        @(Get-FslLogError -Path $script:logRoot -After ([datetime]'2026-07-11')).Count | Should -Be 0
    }

    It 'filters by component' {
        @(Get-FslLogError -Path $script:logRoot -Component ODFC -After $script:longAgo).Count | Should -Be 0
        @(Get-FslLogError -Path $script:logRoot -Component Profile -After $script:longAgo).Count | Should -Be 2
    }

    It 'warns instead of throwing when the log path does not exist' {
        $warnings = @()
        Get-FslLogError -Path (Join-Path $TestDrive 'nope') -WarningVariable warnings -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        $warnings.Count | Should -BeGreaterThan 0
    }

    Context 'benign noise classification' {

        BeforeAll {
            $script:noiseRoot = Join-Path $TestDrive 'NoiseLogs'
            New-Item -Path (Join-Path $script:noiseRoot 'Profile') -ItemType Directory -Force | Out-Null
            # Real-world shapes from a German-locale host: the FSLogix message body
            # is English, only the Windows error text in parentheses is localized.
            @(
                '[08:00:01.123][tid:00001348.00001c9c][ERROR:00000057]      Failed to query activity id for session 4 (Falscher Parameter.)'
                '[08:00:02.456][tid:00001348.00001c9c][ERROR:00000005]      Import group policy DataStore key failed (Zugriff verweigert)'
                '[08:00:02.700][tid:00001348.00001c9c][ERROR:00000005]      Import group policy Status key failed (Zugriff verweigert)'
                '[08:00:03.789][tid:00001348.00001c9c][ERROR:00000005]      Failed to attach VHD (Access is denied.)'
            ) | Set-Content -Path (Join-Path $script:noiseRoot 'Profile\Profile-20260719.log')
        }

        It 'flags known noise messages as Benign regardless of localized error text' {
            $entries = @(Get-FslLogError -Path $script:noiseRoot -After $script:longAgo)
            @($entries | Where-Object Benign).Count | Should -Be 3
            ($entries | Where-Object Message -like 'Failed to query activity id*').Benign | Should -BeTrue
            # The GPO import fails once per key (DataStore, Status, Sid, ...);
            # every variant must classify as noise, not just DataStore.
            $gpo = @($entries | Where-Object Message -like 'Import group policy*')
            $gpo.Count | Should -Be 2
            $gpo | ForEach-Object { $_.Benign | Should -BeTrue }
        }

        It 'leaves real errors unflagged even when they share the error code' {
            $entries = @(Get-FslLogError -Path $script:noiseRoot -After $script:longAgo)
            ($entries | Where-Object Message -like 'Failed to attach VHD*').Benign | Should -BeFalse
        }
    }

    Context 'midnight rollover and fraction-width tolerance' {

        BeforeAll {
            $script:rolloverRoot = Join-Path $TestDrive 'RolloverLogs'
            New-Item -Path (Join-Path $script:rolloverRoot 'Profile') -ItemType Directory -Force | Out-Null
            # Entries continue past midnight in the file named for the previous day;
            # fraction widths deliberately vary (1, 3 and 5 digits).
            @(
                '[23:50:00.1][tid:00000d30.00004c04][ERROR:00000020]  Failed before midnight'
                '[00:30:00.123][tid:00000d30.00004c04][ERROR:00000021]  Failed after midnight'
                '[01:15:00.12345][tid:00000d30.00004c04][ERROR:00000005]  Failed later still'
            ) | Set-Content -Path (Join-Path $script:rolloverRoot 'Profile\Profile-20260710.log')
        }

        It 'rolls entries written after midnight into the next day' {
            $entries = @(Get-FslLogError -Path $script:rolloverRoot -After ([datetime]'2020-01-01'))
            $entries.Count | Should -Be 3
            $entries[0].Timestamp.Date | Should -Be ([datetime]'2026-07-10').Date
            $entries[1].Timestamp.Date | Should -Be ([datetime]'2026-07-11').Date
            $entries[2].Timestamp.Date | Should -Be ([datetime]'2026-07-11').Date
        }

        It 'keeps after-midnight entries inside the After window' {
            $entries = @(Get-FslLogError -Path $script:rolloverRoot -After ([datetime]'2026-07-11'))
            $entries.Count | Should -Be 2
        }

        It 'parses 1-5 digit fractional seconds' {
            $entries = @(Get-FslLogError -Path $script:rolloverRoot -After ([datetime]'2020-01-01'))
            $entries[0].Timestamp.Hour | Should -Be 23
            $entries[2].Timestamp.Hour | Should -Be 1
        }
    }
}
