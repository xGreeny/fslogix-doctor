BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Get-FslEventSummary' {

    Context 'with events in the Operational channel' {

        BeforeAll {
            $script:now = Get-Date

            Mock Get-WinEvent -ModuleName FSLogixDoctor { @() }
            Mock Get-WinEvent -ModuleName FSLogixDoctor -ParameterFilter {
                $FilterHashtable.LogName -eq 'Microsoft-FSLogix-Apps/Operational'
            } {
                @(
                    # LevelDisplayName deliberately localized (German) to pin the
                    # locale-independence of the classification path.
                    [pscustomobject]@{ Id = 26; Level = 2; LevelDisplayName = 'Fehler'; TimeCreated = $script:now.AddMinutes(-30); Message = 'Failed to attach VHD for user LAB\jdoe' }
                    [pscustomobject]@{ Id = 26; Level = 2; LevelDisplayName = 'Fehler'; TimeCreated = $script:now.AddMinutes(-10); Message = 'Failed to attach VHD for user LAB\mmuster' }
                    [pscustomobject]@{ Id = 31; Level = 3; LevelDisplayName = 'Warnung'; TimeCreated = $script:now.AddMinutes(-5); Message = 'VHD size is close to its maximum' }
                )
            }
        }

        It 'buckets events by ID with counts' {
            $summary = @(Get-FslEventSummary)
            $summary.Count | Should -Be 2
            ($summary | Where-Object EventId -eq 26).Count | Should -Be 2
            ($summary | Where-Object EventId -eq 31).Count | Should -Be 1
        }

        It 'sorts buckets by count descending' {
            $summary = @(Get-FslEventSummary)
            $summary[0].EventId | Should -Be 26
        }

        It 'tracks first and last occurrence' {
            $bucket = @(Get-FslEventSummary) | Where-Object EventId -eq 26
            $bucket.FirstSeen | Should -BeLessThan $bucket.LastSeen
        }

        It 'includes a sample message' {
            $bucket = @(Get-FslEventSummary) | Where-Object EventId -eq 26
            $bucket.SampleMessage | Should -Match 'Failed to attach'
        }

        It 'carries the computer name on every bucket' {
            @(Get-FslEventSummary) | ForEach-Object { $_.ComputerName | Should -Be $env:COMPUTERNAME }
        }

        It 'exposes the numeric level so classification is locale-independent' {
            $summary = @(Get-FslEventSummary)
            ($summary | Where-Object EventId -eq 26).LevelValue | Should -Be 2
            ($summary | Where-Object EventId -eq 31).LevelValue | Should -Be 3
        }

        It 'exposes distinct messages per bucket with counts' {
            $bucket = @(Get-FslEventSummary) | Where-Object EventId -eq 26
            # The two attach failures differ in the user name, so they stay
            # distinct patterns.
            @($bucket.TopMessages).Count | Should -Be 2
            $bucket.TopMessages | ForEach-Object { $_ | Should -Match '^1x Failed to attach VHD' }
        }
    }

    Context 'generic-error buckets carrying known-benign noise' {

        BeforeAll {
            $script:now = Get-Date
            Mock Get-WinEvent -ModuleName FSLogixDoctor { @() }
            Mock Get-WinEvent -ModuleName FSLogixDoctor -ParameterFilter {
                $FilterHashtable.LogName -eq 'Microsoft-FSLogix-Apps/Operational'
            } {
                @(
                    [pscustomobject]@{ Id = 26; Level = 2; LevelDisplayName = 'Fehler'; TimeCreated = $script:now.AddMinutes(-20); Message = 'Failed to query activity id for session 1 (Falscher Parameter.)' }
                    [pscustomobject]@{ Id = 26; Level = 2; LevelDisplayName = 'Fehler'; TimeCreated = $script:now.AddMinutes(-15); Message = 'Failed to query activity id for session 7 (Falscher Parameter.)' }
                    [pscustomobject]@{ Id = 26; Level = 2; LevelDisplayName = 'Fehler'; TimeCreated = $script:now.AddMinutes(-10); Message = 'Failed to attach VHD for user LAB\jdoe' }
                )
            }
        }

        It 'counts benign occurrences separately per bucket' {
            $bucket = @(Get-FslEventSummary) | Where-Object EventId -eq 26
            $bucket.Count | Should -Be 3
            $bucket.BenignCount | Should -Be 2
        }

        It 'collapses numeric noise so message variants group together' {
            $bucket = @(Get-FslEventSummary) | Where-Object EventId -eq 26
            @($bucket.TopMessages).Count | Should -Be 2
            $bucket.TopMessages[0] | Should -Match '^2x Failed to query activity id'
        }
    }

    Context 'without matching events' {

        BeforeAll {
            Mock Get-WinEvent -ModuleName FSLogixDoctor { @() }
        }

        It 'returns nothing' {
            @(Get-FslEventSummary) | Should -BeNullOrEmpty
        }
    }
}
