BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

    $script:share = Join-Path $TestDrive 'fslogix-share'
    foreach ($user in @('jdoe', 'mmuster')) {
        $index = if ($user -eq 'jdoe') { '1001' } else { '1002' }
        $folder = Join-Path $script:share "S-1-5-21-1111111111-2222222222-3333333333-${index}_$user"
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $folder "Profile_$user.vhdx") -Value ('x' * 2048)
    }
}

Describe 'Get-FslOrphanedDisk' {

    Context 'with a KnownUser allow-list (offline mode)' {

        It 'classifies listed users as OK' {
            $result = Get-FslProfileReport -Path $script:share | Get-FslOrphanedDisk -KnownUser 'jdoe', 'mmuster'
            @($result | Where-Object State -eq 'OK').Count | Should -Be 2
        }

        It 'classifies unlisted users as Orphaned with reclaimable size' {
            $result = @(Get-FslProfileReport -Path $script:share | Get-FslOrphanedDisk -KnownUser 'jdoe')
            $orphan = $result | Where-Object UserName -eq 'mmuster'
            $orphan.State | Should -Be 'Orphaned'
            $orphan.ReclaimableGB | Should -Be $orphan.SizeGB
            ($result | Where-Object UserName -eq 'jdoe').State | Should -Be 'OK'
        }

        It 'classifies disks without a derivable username as Unknown, never Orphaned' {
            $disk = [pscustomobject]@{
                PSTypeName   = 'FSLogixDoctor.ProfileDisk'
                Folder       = 'X:\share'
                Disk         = 'X:\share\stray.vhdx'
                UserName     = $null
                Sid          = $null
                SizeGB       = 25.5
                LastModified = Get-Date
            }
            $result = $disk | Get-FslOrphanedDisk -KnownUser 'jdoe'
            $result.State | Should -Be 'Unknown'
            $result.ReclaimableGB | Should -Be 0
        }
    }

    Context 'with SID translation (default mode)' {

        It 'classifies fabricated SIDs as Orphaned because they never translate' {
            $result = @(Get-FslProfileReport -Path $script:share | Get-FslOrphanedDisk)
            $result.Count | Should -Be 2
            $result | ForEach-Object { $_.State | Should -Be 'Orphaned' }
        }

        It 'classifies unresolvable Entra ID (cloud) SIDs as Unknown, never Orphaned' {
            $disk = [pscustomobject]@{
                PSTypeName   = 'FSLogixDoctor.ProfileDisk'
                Folder       = 'X:\share\S-1-12-1-1111-2222-3333-4444_cloud.user'
                Disk         = 'X:\share\S-1-12-1-1111-2222-3333-4444_cloud.user\Profile_cloud.user.vhdx'
                UserName     = 'cloud.user'
                Sid          = 'S-1-12-1-1111-2222-3333-4444'
                SizeGB       = 12.3
                LastModified = Get-Date
            }
            $result = $disk | Get-FslOrphanedDisk
            $result.State | Should -Be 'Unknown'
            $result.ReclaimableGB | Should -Be 0
            $result.Detail | Should -Match 'Entra'
        }

        It 'classifies a real, existing SID as OK' {
            $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $disk = [pscustomobject]@{
                PSTypeName   = 'FSLogixDoctor.ProfileDisk'
                Folder       = 'X:\share\folder'
                Disk         = 'X:\share\folder\Profile_me.vhdx'
                UserName     = 'me'
                Sid          = $currentSid
                SizeGB       = 1.5
                LastModified = Get-Date
            }
            $result = $disk | Get-FslOrphanedDisk
            $result.State | Should -BeIn @('OK', 'Disabled')
        }
    }

    Context 'via -Path directly' {

        It 'scans the share itself when given a path' {
            $result = @(Get-FslOrphanedDisk -Path $script:share -KnownUser 'jdoe')
            $result.Count | Should -Be 2
            @($result | Where-Object State -eq 'Orphaned').Count | Should -Be 1
        }
    }
}
