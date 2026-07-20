BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Get-FslContextEvent' {

    Context 'with profile-related events in the surrounding logs' {

        BeforeAll {
            $script:now = Get-Date
            Mock Get-WinEvent -ModuleName FSLogixDoctor { throw 'unexpected query' }
            Mock Get-WinEvent -ModuleName FSLogixDoctor -ParameterFilter {
                $FilterHashtable.LogName -eq 'Application' -and $FilterHashtable.Id -eq 1511
            } {
                @(
                    [pscustomobject]@{ Id = 1511; ProviderName = 'Microsoft-Windows-User Profiles Service'; TimeCreated = $script:now.AddHours(-2); Message = 'Windows cannot find the local profile and is logging you on with a temporary profile.' }
                    # Same ID from another provider must be filtered out.
                    [pscustomobject]@{ Id = 1511; ProviderName = 'SomeOtherApp'; TimeCreated = $script:now.AddHours(-1); Message = 'unrelated 1511' }
                )
            }
            Mock Get-WinEvent -ModuleName FSLogixDoctor -ParameterFilter {
                $FilterHashtable.Id -ne 1511
            } {
                throw [System.Exception]::new('no events')
            }
        }

        It 'buckets curated events and filters by provider' {
            $events = @(Get-FslContextEvent -WarningAction SilentlyContinue)
            $bucket = @($events | Where-Object Key -eq 'ProfSvc:1511')
            $bucket.Count | Should -Be 1
            $bucket[0].Count | Should -Be 1
            $bucket[0].TopMessages[0] | Should -Match 'temporary profile'
        }

        It 'carries the curated severity and label' {
            $bucket = @(Get-FslContextEvent -WarningAction SilentlyContinue) | Where-Object Key -eq 'ProfSvc:1511'
            $bucket.Severity | Should -Be 'Critical'
            $bucket.Label | Should -Be 'User Profile Service'
            $bucket.Channel | Should -Be 'Application'
        }
    }

    Context 'without matching events' {

        BeforeAll {
            Mock Get-WinEvent -ModuleName FSLogixDoctor { @() }
        }

        It 'returns nothing and stays silent' {
            @(Get-FslContextEvent -WarningAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }
}
