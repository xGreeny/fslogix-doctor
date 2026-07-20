BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    function New-OstFixture {
        param([string]$Root)
        $outlook = Join-Path $Root 'AppData\Local\Microsoft\Outlook'
        New-Item -Path $outlook -ItemType Directory -Force | Out-Null
        $old = Join-Path $outlook 'old-mailbox.ost'
        $older = Join-Path $outlook 'older-mailbox.ost'
        $active = Join-Path $outlook 'user@contoso.ch.ost'
        'x' * 1024 | Set-Content -Path $old
        'x' * 1024 | Set-Content -Path $older
        'x' * 1024 | Set-Content -Path $active
        (Get-Item $older).LastWriteTime = (Get-Date).AddDays(-90)
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item $active).LastWriteTime = Get-Date
        $outlook
    }
}

Describe 'Remove-FslOrphanedOst' {

    It 'removes nothing with -WhatIf' {
        $root = Join-Path $TestDrive 'profile-whatif'
        $outlook = New-OstFixture -Root $root
        Remove-FslOrphanedOst -Path $root -WhatIf | Out-Null
        @(Get-ChildItem $outlook -Filter '*.ost').Count | Should -Be 3
    }

    It 'keeps the newest OST and removes the older ones' {
        $root = Join-Path $TestDrive 'profile-clean'
        $outlook = New-OstFixture -Root $root
        $result = @(Remove-FslOrphanedOst -Path $root -Confirm:$false)
        @($result | Where-Object Removed).Count | Should -Be 2
        $remaining = @(Get-ChildItem $outlook -Filter '*.ost')
        $remaining.Count | Should -Be 1
        $remaining[0].Name | Should -Be 'user@contoso.ch.ost'
    }

    It 'honors -KeepNewest' {
        $root = Join-Path $TestDrive 'profile-keep2'
        $outlook = New-OstFixture -Root $root
        $result = @(Remove-FslOrphanedOst -Path $root -KeepNewest 2 -Confirm:$false)
        @($result | Where-Object Removed).Count | Should -Be 1
        @(Get-ChildItem $outlook -Filter '*.ost').Count | Should -Be 2
    }

    It 'accepts the Outlook folder directly and reports freed size' {
        $root = Join-Path $TestDrive 'profile-direct'
        $outlook = New-OstFixture -Root $root
        $result = @(Remove-FslOrphanedOst -Path $outlook -Confirm:$false)
        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.SizeMB | Should -BeGreaterOrEqual 0 }
    }

    It 'skips locked files with a warning instead of failing' {
        $root = Join-Path $TestDrive 'profile-locked'
        $outlook = New-OstFixture -Root $root
        $lockedPath = Join-Path $outlook 'old-mailbox.ost'
        $stream = [System.IO.File]::Open($lockedPath, 'Open', 'Read', 'None')
        try {
            $warnings = @()
            $result = @(Remove-FslOrphanedOst -Path $root -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result | Where-Object { -not $_.Removed }).Count | Should -Be 1
            ($result | Where-Object { -not $_.Removed }).Reason | Should -Match 'In use'
            $warnings.Count | Should -BeGreaterThan 0
        }
        finally {
            $stream.Close()
        }
    }

    It 'warns when no OST files exist' {
        $empty = Join-Path $TestDrive 'profile-empty'
        New-Item -Path $empty -ItemType Directory -Force | Out-Null
        $warnings = @()
        Remove-FslOrphanedOst -Path $empty -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        $warnings.Count | Should -BeGreaterThan 0
    }
}
