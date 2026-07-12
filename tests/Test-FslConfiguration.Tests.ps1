BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    function New-Snapshot {
        param([hashtable]$Overrides = @{})
        $snapshot = @{
            ComputerName       = 'LAB-SH-01'
            Install            = [pscustomobject]@{ Installed = $true; ServiceStatus = 'Running'; Version = '2.9.8884.27471' }
            Profiles           = @{
                Enabled                              = 1
                VHDLocations                         = '\\lab-fs01\fslogix$'
                SizeInMBs                            = 30000
                IsDynamic                            = 1
                VolumeType                           = 'vhdx'
                DeleteLocalProfileWhenVHDShouldApply = 1
                PreventLoginWithFailure              = 1
                PreventLoginWithTempProfile          = 1
            }
            Odfc               = $null
            Logging            = @{ LoggingEnabled = 2; LogFileKeepingPeriod = 14 }
            Apps               = @{}
            DefenderExclusions = @('\\lab-fs01\fslogix$')
            VhdLocationsOnline = @{ '\\lab-fs01\fslogix$' = $true }
        }
        foreach ($key in $Overrides.Keys) { $snapshot[$key] = $Overrides[$key] }
        $snapshot
    }
}

Describe 'Test-FslConfiguration' {

    It 'produces no Critical or Warning findings for a healthy snapshot' {
        $findings = @(Test-FslConfiguration -ConfigSnapshot (New-Snapshot))
        @($findings | Where-Object Severity -in @('Critical', 'Warning')) | Should -BeNullOrEmpty
        @($findings | Where-Object Severity -eq 'Pass').Count | Should -BeGreaterThan 0
    }

    It 'reports Critical and stops when FSLogix is not installed' {
        $snapshot = New-Snapshot -Overrides @{ Install = [pscustomobject]@{ Installed = $false; ServiceStatus = $null; Version = $null } }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        $findings.Count | Should -Be 1
        $findings[0].Severity | Should -Be 'Critical'
        $findings[0].Check | Should -Be 'FSLogix installed'
    }

    It 'flags a stopped frxsvc service as Critical' {
        $snapshot = New-Snapshot -Overrides @{ Install = [pscustomobject]@{ Installed = $true; ServiceStatus = 'Stopped'; Version = '2.9' } }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'FSLogix service running' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'flags a missing Profiles key as Critical' {
        $findings = @(Test-FslConfiguration -ConfigSnapshot (New-Snapshot -Overrides @{ Profiles = $null }))
        @($findings | Where-Object { $_.Check -eq 'Profiles configured' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'flags Enabled=0 as Critical' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.Enabled = 0
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Profiles enabled' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'flags missing VHDLocations and CCDLocations as Critical' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.Remove('VHDLocations')
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'VHDLocations defined' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'flags VHDLocations plus CCDLocations together as Critical (invalid per Microsoft)' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.CCDLocations = 'type=smb,name=lab,connectionString=\\lab-fs01\ccd$'
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'VHDLocations vs CCDLocations' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'flags an unreachable VHD location as Critical' {
        $snapshot = New-Snapshot -Overrides @{ VhdLocationsOnline = @{ '\\lab-fs01\fslogix$' = $false } }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'VHDLocations reachable' -and $_.Severity -eq 'Critical' }).Count | Should -Be 1
    }

    It 'splits semicolon-delimited REG_SZ VHDLocations into individual paths' {
        $snapshot = New-Snapshot -Overrides @{
            VhdLocationsOnline = @{ '\\lab-fs01\fslogix$' = $true; '\\lab-fs02\fslogix$' = $true }
            DefenderExclusions = @('\\lab-fs01\fslogix$', '\\lab-fs02\fslogix$')
        }
        $snapshot.Profiles.VHDLocations = '\\lab-fs01\fslogix$;\\lab-fs02\fslogix$'
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'VHDLocations reachable' -and $_.Severity -eq 'Pass' }).Count | Should -Be 2
        @($findings | Where-Object Severity -eq 'Critical') | Should -BeNullOrEmpty
    }

    It 'warns when failure masking is fully disabled' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.PreventLoginWithFailure = 0
        $snapshot.Profiles.PreventLoginWithTempProfile = 0
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Failure masking' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'warns about local profile collisions when DeleteLocalProfileWhenVHDShouldApply=0' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.DeleteLocalProfileWhenVHDShouldApply = 0
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Local profile collision' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'warns when VolumeType is left at the vhd default' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.Remove('VolumeType')
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'VolumeType' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'warns about excessive locked-retry windows' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.LockedRetryCount = 30
        $snapshot.Profiles.LockedRetryInterval = 10
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        $finding = @($findings | Where-Object { $_.Check -eq 'Locked-container retry time' -and $_.Severity -eq 'Warning' })
        $finding.Count | Should -Be 1
        $finding[0].Message | Should -Match '300 seconds'
    }

    It 'warns when LockedRetryCount is zero' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.LockedRetryCount = 0
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Locked-container retry time' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'flags the obsolete ConcurrentUserSessions value' {
        $snapshot = New-Snapshot
        $snapshot.Profiles.ConcurrentUserSessions = 1
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object Check -eq 'Obsolete setting').Count | Should -Be 1
    }

    It 'warns when Profile and ODFC containers share VHDLocations' {
        $snapshot = New-Snapshot -Overrides @{ Odfc = @{ Enabled = 1; VHDLocations = '\\lab-fs01\fslogix$' } }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Profile/ODFC overlap' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'warns when text logging is disabled' {
        $snapshot = New-Snapshot -Overrides @{ Logging = @{ LoggingEnabled = 0 } }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Text logging' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'warns when profile locations are missing from Defender exclusions' {
        $snapshot = New-Snapshot -Overrides @{ DefenderExclusions = @('C:\SomethingElse') }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Antivirus exclusions' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'does not count a subfolder-only exclusion as covering the whole location' {
        $snapshot = New-Snapshot -Overrides @{ DefenderExclusions = @('\\lab-fs01\fslogix$\subfolder-only') }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Antivirus exclusions' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'does not let a string-prefix exclusion cover a longer share name' {
        $snapshot = New-Snapshot -Overrides @{ DefenderExclusions = @('\\lab-fs01\fslogix') }  # note: no $ suffix
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Antivirus exclusions' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
    }

    It 'accepts a parent-folder exclusion as covering a nested location' {
        $snapshot = New-Snapshot -Overrides @{ DefenderExclusions = @('\\lab-fs01\fslogix$') }
        $snapshot.Profiles.VHDLocations = '\\lab-fs01\fslogix$\profiles'
        $snapshot.VhdLocationsOnline = @{ '\\lab-fs01\fslogix$\profiles' = $true }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object { $_.Check -eq 'Antivirus exclusions' -and $_.Severity -eq 'Pass' }).Count | Should -Be 1
    }

    It 'skips the Defender check gracefully when exclusions are unreadable' {
        $snapshot = New-Snapshot -Overrides @{ DefenderExclusions = $null }
        $findings = @(Test-FslConfiguration -ConfigSnapshot $snapshot)
        @($findings | Where-Object Check -eq 'Antivirus exclusions') | Should -BeNullOrEmpty
    }
}
