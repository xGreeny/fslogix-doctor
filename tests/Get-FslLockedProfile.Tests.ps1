BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Get-FslLockedProfile' {

    BeforeAll {
        Mock Get-SmbOpenFile -ModuleName FSLogixDoctor {
            @(
                [pscustomobject]@{ Path = 'D:\Shares\fslogix\S-1-5-21-1-2-3-1001_jdoe\Profile_jdoe.vhdx'; ClientUserName = 'LAB\jdoe'; ClientComputerName = '10.0.0.11'; SessionId = 101; FileId = 4001; Locks = 1 }
                [pscustomobject]@{ Path = 'D:\Shares\fslogix\S-1-5-21-1-2-3-1002_mmuster\Profile_mmuster.vhd'; ClientUserName = 'LAB\mmuster'; ClientComputerName = '10.0.0.12'; SessionId = 102; FileId = 4002; Locks = 0 }
                [pscustomobject]@{ Path = 'D:\Shares\docs\quarterly.xlsx'; ClientUserName = 'LAB\boss'; ClientComputerName = '10.0.0.13'; SessionId = 103; FileId = 4003; Locks = 0 }
            )
        }
    }

    It 'returns only VHD/VHDX handles' {
        $locked = @(Get-FslLockedProfile)
        $locked.Count | Should -Be 2
        $locked | ForEach-Object { $_.Path | Should -Match '\.vhdx?$' }
    }

    It 'reports who holds the handle' {
        $locked = @(Get-FslLockedProfile)
        $locked[0].HeldByUser | Should -Be 'LAB\jdoe'
        $locked[0].HeldByComputer | Should -Be '10.0.0.11'
    }

    It 'includes a copy-paste release instruction referencing the FileId' {
        $locked = @(Get-FslLockedProfile)
        $locked[0].ReleaseInstruction | Should -Match 'Close-SmbOpenFile -FileId 4001'
        $locked[0].ReleaseInstruction | Should -Match '-Confirm'
    }

    It 'filters handles with -PathFilter' {
        $locked = @(Get-FslLockedProfile -PathFilter '*jdoe*')
        $locked.Count | Should -Be 1
        $locked[0].HeldByUser | Should -Be 'LAB\jdoe'
    }
}
