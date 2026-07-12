BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Get-FslSessionState' {

    BeforeAll {
        $script:sessionsKey = 'TestRegistry:\FslSessions'
        New-Item -Path $script:sessionsKey -Force | Out-Null

        # Healthy session: everything zero.
        $healthy = New-Item -Path (Join-Path $script:sessionsKey 'S-1-5-21-1111111111-2222222222-3333333333-1001') -Force
        Set-ItemProperty -Path $healthy.PSPath -Name Status -Value 0 -Type DWord
        Set-ItemProperty -Path $healthy.PSPath -Name Reason -Value 0 -Type DWord
        Set-ItemProperty -Path $healthy.PSPath -Name Error -Value 0 -Type DWord

        # Broken session: attach failed with sharing violation.
        $broken = New-Item -Path (Join-Path $script:sessionsKey 'S-1-5-21-1111111111-2222222222-3333333333-1002') -Force
        Set-ItemProperty -Path $broken.PSPath -Name Status -Value 2 -Type DWord
        Set-ItemProperty -Path $broken.PSPath -Name Reason -Value 4 -Type DWord
        Set-ItemProperty -Path $broken.PSPath -Name Error -Value 32 -Type DWord
    }

    It 'returns one object per session key' {
        @(Get-FslSessionState -SessionsKeyPath $script:sessionsKey).Count | Should -Be 2
    }

    It 'marks a zero-state session as healthy' {
        $sessions = Get-FslSessionState -SessionsKeyPath $script:sessionsKey
        $healthy = $sessions | Where-Object Sid -like '*-1001'
        $healthy.Healthy | Should -BeTrue
        $healthy.StatusText | Should -Not -BeNullOrEmpty
        $healthy.StatusText | Should -Not -Match '^Unknown'
    }

    It 'marks a failed session as unhealthy and decodes the error' {
        $sessions = Get-FslSessionState -SessionsKeyPath $script:sessionsKey
        $broken = $sessions | Where-Object Sid -like '*-1002'
        $broken.Healthy | Should -BeFalse
        $broken.Error | Should -Be 32
        $broken.ErrorText | Should -Not -BeNullOrEmpty
    }

    It 'reports the raw SID when the account cannot be resolved' {
        $sessions = Get-FslSessionState -SessionsKeyPath $script:sessionsKey
        $sessions[0].Sid | Should -Match '^S-1-5-21'
    }

    It 'warns instead of throwing when the sessions key is missing' {
        $warnings = @()
        Get-FslSessionState -SessionsKeyPath 'TestRegistry:\DoesNotExist' -WarningVariable warnings -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        $warnings.Count | Should -BeGreaterThan 0
    }

    Context 'differencing-disk states' {

        BeforeAll {
            $script:diffKey = 'TestRegistry:\FslSessionsDiff'
            New-Item -Path $script:diffKey -Force | Out-Null
            $session = New-Item -Path (Join-Path $script:diffKey 'S-1-5-21-1111111111-2222222222-3333333333-1003') -Force
            Set-ItemProperty -Path $session.PSPath -Name Status -Value 300 -Type DWord
            Set-ItemProperty -Path $session.PSPath -Name Reason -Value 0 -Type DWord
            Set-ItemProperty -Path $session.PSPath -Name Error -Value 0 -Type DWord
        }

        It 'treats Status 300 (already attached) as attached and healthy' {
            $session = @(Get-FslSessionState -SessionsKeyPath $script:diffKey)[0]
            $session.Attached | Should -BeTrue
            $session.Healthy | Should -BeTrue
        }
    }
}
