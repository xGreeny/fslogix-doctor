BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    $script:share = Join-Path $TestDrive 'fslogix-share'

    # Default layout: <SID>_<username>
    $jdoe = Join-Path $script:share 'S-1-5-21-1111111111-2222222222-3333333333-1001_jdoe'
    New-Item -Path $jdoe -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $jdoe 'Profile_jdoe.vhdx') -Value ('x' * 4096)

    # Flip-flop layout: <username>_<SID>
    $mmuster = Join-Path $script:share 'mmuster_S-1-5-21-1111111111-2222222222-3333333333-1002'
    New-Item -Path $mmuster -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $mmuster 'Profile_mmuster.vhdx') -Value ('x' * 4096)

    # Empty folder (failed create leftover)
    New-Item -Path (Join-Path $script:share 'S-1-5-21-1111111111-2222222222-3333333333-1003_asmith') -ItemType Directory -Force | Out-Null

    # Two disks in one folder + stale timestamps
    $kbrown = Join-Path $script:share 'S-1-5-21-1111111111-2222222222-3333333333-1004_kbrown'
    New-Item -Path $kbrown -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path $kbrown 'Profile_kbrown.vhdx') -Value ('x' * 4096)
    Set-Content -Path (Join-Path $kbrown 'Profile_kbrown_old.vhd') -Value ('x' * 4096)
    (Get-Item (Join-Path $kbrown 'Profile_kbrown_old.vhd')).LastWriteTime = (Get-Date).AddDays(-200)

    # Disk in the share root
    Set-Content -Path (Join-Path $script:share 'stray.vhdx') -Value ('x' * 4096)

    # Non-container noise that must be ignored
    Set-Content -Path (Join-Path $jdoe 'desktop.ini') -Value 'noise'
}

Describe 'Get-FslProfileReport' {

    It 'throws on an unreachable share path' {
        { Get-FslProfileReport -Path (Join-Path $TestDrive 'missing') } | Should -Throw
    }

    It 'reports every container disk plus empty folders and root strays' {
        $report = @(Get-FslProfileReport -Path $script:share)
        # jdoe + mmuster + empty folder + 2x kbrown + stray root disk
        $report.Count | Should -Be 6
    }

    It 'parses SID and username from the default layout' {
        $disk = @(Get-FslProfileReport -Path $script:share) | Where-Object UserName -eq 'jdoe'
        $disk.Sid | Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-1001'
        $disk.Anomaly | Should -BeNullOrEmpty
    }

    It 'parses SID and username from the flip-flop layout' {
        $disk = @(Get-FslProfileReport -Path $script:share) | Where-Object UserName -eq 'mmuster'
        $disk.Sid | Should -Be 'S-1-5-21-1111111111-2222222222-3333333333-1002'
    }

    It 'flags empty profile folders' {
        $empty = @(Get-FslProfileReport -Path $script:share) | Where-Object DiskCount -eq 0
        $empty.UserName | Should -Be 'asmith'
        $empty.Anomaly | Should -Match 'no container disk'
    }

    It 'flags folders with multiple disks' {
        $multi = @(Get-FslProfileReport -Path $script:share) | Where-Object UserName -eq 'kbrown'
        $multi.Count | Should -Be 2
        $multi[0].DiskCount | Should -Be 2
        $multi[0].Anomaly | Should -Match '2 disks'
    }

    It 'flags stale disks based on StaleDays' {
        $stale = @(Get-FslProfileReport -Path $script:share -StaleDays 90) | Where-Object Stale
        @($stale).Count | Should -BeGreaterThan 0
        @($stale | Where-Object { $_.Disk -like '*kbrown_old*' }).Count | Should -Be 1
    }

    It 'flags disks in the share root' {
        $stray = @(Get-FslProfileReport -Path $script:share) | Where-Object { $_.Disk -like '*stray.vhdx' }
        $stray.Anomaly | Should -Match 'share root'
    }

    It 'computes size and percent of maximum' {
        $disk = @(Get-FslProfileReport -Path $script:share -MaximumSizeMB 100) | Where-Object UserName -eq 'jdoe'
        $disk.SizeGB | Should -BeGreaterOrEqual 0
        $disk.PercentOfMax | Should -BeGreaterOrEqual 0
    }

    It 'ignores non-container files' {
        @(Get-FslProfileReport -Path $script:share) | Where-Object { $_.Disk -like '*desktop.ini' } |
            Should -BeNullOrEmpty
    }
}
