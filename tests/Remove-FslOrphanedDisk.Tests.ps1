BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    function New-OrphanFixture {
        param([string]$Root, [string]$FolderName)
        $folder = Join-Path $Root $FolderName
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $disk = Join-Path $folder ('Profile_{0}.VHDX' -f ($FolderName -split '_')[0])
        'x' * 2048 | Set-Content -Path $disk
        $disk
    }

    function New-OrphanInput {
        param([string]$Disk, [string]$State = 'Orphaned', [string]$UserName = 'gone.user')
        [pscustomobject]@{
            PSTypeName = 'FSLogixDoctor.OrphanedDisk'
            Disk       = $Disk
            Folder     = Split-Path $Disk -Parent
            UserName   = $UserName
            SizeGB     = 0.1
            State      = $State
            Detail     = 'test'
        }
    }
}

Describe 'Remove-FslOrphanedDisk' {

    It 'removes nothing with -WhatIf' {
        $disk = New-OrphanFixture -Root (Join-Path $TestDrive 'whatif') -FolderName 'gone.user_S-1-5-21-1'
        New-OrphanInput -Disk $disk | Remove-FslOrphanedDisk -WhatIf | Out-Null
        Test-Path $disk | Should -BeTrue
    }

    It 'deletes only Orphaned disks and cleans the empty container folder' {
        $root = Join-Path $TestDrive 'delete'
        $orphanDisk = New-OrphanFixture -Root $root -FolderName 'gone.user_S-1-5-21-1'
        $okDisk = New-OrphanFixture -Root $root -FolderName 'active.user_S-1-5-21-2'
        $result = @(
            (New-OrphanInput -Disk $orphanDisk),
            (New-OrphanInput -Disk $okDisk -State 'OK' -UserName 'active.user')
        ) | Remove-FslOrphanedDisk -Confirm:$false
        @($result).Count | Should -Be 1
        $result[0].Action | Should -Be 'Deleted'
        Test-Path $orphanDisk | Should -BeFalse
        Test-Path (Split-Path $orphanDisk -Parent) | Should -BeFalse
        Test-Path $okDisk | Should -BeTrue
    }

    It 'never touches Disabled or Unknown disks' {
        $root = Join-Path $TestDrive 'states'
        $disabledDisk = New-OrphanFixture -Root $root -FolderName 'disabled.user_S-1-5-21-3'
        $unknownDisk = New-OrphanFixture -Root $root -FolderName 'unknown.user_S-1-5-21-4'
        $result = @(
            (New-OrphanInput -Disk $disabledDisk -State 'Disabled'),
            (New-OrphanInput -Disk $unknownDisk -State 'Unknown')
        ) | Remove-FslOrphanedDisk -Confirm:$false
        @($result) | Should -BeNullOrEmpty
        Test-Path $disabledDisk | Should -BeTrue
        Test-Path $unknownDisk | Should -BeTrue
    }

    It 'archives instead of deleting with -ArchivePath' {
        $root = Join-Path $TestDrive 'archive-src'
        $archive = Join-Path $TestDrive 'archive-dst'
        $disk = New-OrphanFixture -Root $root -FolderName 'gone.user_S-1-5-21-5'
        $result = @(New-OrphanInput -Disk $disk | Remove-FslOrphanedDisk -ArchivePath $archive -Confirm:$false)
        $result[0].Action | Should -Be 'Archived'
        Test-Path $disk | Should -BeFalse
        Test-Path $result[0].Destination | Should -BeTrue
        $result[0].Destination | Should -Match 'gone\.user_S-1-5-21-5'
    }

    It 'warns when the disk file is missing' {
        $warnings = @()
        New-OrphanInput -Disk (Join-Path $TestDrive 'nope\missing.VHDX') |
            Remove-FslOrphanedDisk -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        $warnings.Count | Should -BeGreaterThan 0
    }
}
