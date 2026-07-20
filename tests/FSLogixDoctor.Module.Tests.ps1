BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1'
    Import-Module $modulePath -Force
}

Describe 'FSLogixDoctor module' {

    It 'has a valid module manifest' {
        { Test-ModuleManifest -Path (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'exports exactly the documented public functions' {
        $expected = @(
            'Get-FslContextEvent'
            'Get-FslErrorCode'
            'Get-FslEventSummary'
            'Get-FslLockedProfile'
            'Get-FslLogError'
            'Get-FslOrphanedDisk'
            'Get-FslProfileReport'
            'Get-FslSessionState'
            'Invoke-FslDiagnostic'
            'New-FslReport'
            'Remove-FslOrphanedDisk'
            'Remove-FslOrphanedOst'
            'Test-FslConfiguration'
        )
        $exported = (Get-Module FSLogixDoctor).ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be ($expected | Sort-Object)
    }

    It 'does not leak private helper functions' {
        (Get-Module FSLogixDoctor).ExportedFunctions.Keys | Should -Not -Contain 'New-FslFinding'
        (Get-Module FSLogixDoctor).ExportedFunctions.Keys | Should -Not -Contain 'Get-FslDataTable'
    }

    It 'provides comment-based help with a synopsis for <_>' -ForEach @(
        'Get-FslContextEvent'
        'Get-FslErrorCode'
        'Get-FslEventSummary'
        'Get-FslLockedProfile'
        'Get-FslLogError'
        'Get-FslOrphanedDisk'
        'Get-FslProfileReport'
        'Get-FslSessionState'
        'Invoke-FslDiagnostic'
        'New-FslReport'
        'Remove-FslOrphanedDisk'
        'Remove-FslOrphanedOst'
        'Test-FslConfiguration'
    ) {
        $help = Get-Help $_ -ErrorAction Stop
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match '^\s*$'
    }

    Context 'data files' {

        It 'ships a well-formed error-code database' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\ErrorCodes.psd1')
            $data.Keys.Count | Should -BeGreaterThan 10
            foreach ($key in $data.Keys) {
                $key | Should -Match '^0x[0-9A-F]{8}$'
                $entry = $data[$key]
                $entry.Meaning | Should -Not -BeNullOrEmpty -Because "entry $key needs a meaning"
                @($entry.Causes).Count | Should -BeGreaterThan 0 -Because "entry $key needs causes"
                @($entry.Fixes).Count | Should -BeGreaterThan 0 -Because "entry $key needs fixes"
                $entry.Keys | Should -Contain 'Source' -Because "entry $key needs a source"
            }
        }

        It 'ships a well-formed session-code database' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\SessionCodes.psd1')
            $data.Keys.Count | Should -BeGreaterThan 5
            foreach ($key in $data.Keys) {
                $key | Should -Match '^(Status|Reason):\d+$'
                $data[$key].Meaning | Should -Not -BeNullOrEmpty
            }
            $data.Keys | Should -Contain 'Status:0'
            $data.Keys | Should -Contain 'Reason:0'
        }

        It 'ships a well-formed event-ID database' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\EventIds.psd1')
            $data.Keys.Count | Should -BeGreaterThan 3
            foreach ($key in $data.Keys) {
                $key | Should -Match '^\d+$'
                $data[$key].Meaning | Should -Not -BeNullOrEmpty
            }
        }

        It 'ships a well-formed release table' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\Releases.psd1')
            $data.AsOf | Should -Match '^\d{4}-\d{2}-\d{2}$'
            @($data.Releases).Count | Should -BeGreaterThan 1
            foreach ($entry in $data.Releases) {
                { [version]$entry.Version } | Should -Not -Throw
                $entry.Notes | Should -Not -BeNullOrEmpty
            }
        }

        It 'ships a well-formed context-event database' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\ContextEvents.psd1')
            @($data.Events).Count | Should -BeGreaterThan 4
            foreach ($entry in $data.Events) {
                $entry.Key | Should -Match '^\w+:\d+$'
                $entry.LogName | Should -Not -BeNullOrEmpty
                $entry.ProviderPattern | Should -Not -BeNullOrEmpty
                $entry.Label | Should -Not -BeNullOrEmpty
                [int]$entry.Id | Should -BeGreaterThan 0
                $entry.Severity | Should -BeIn @('Critical', 'Warning', 'Info')
                $entry.Meaning | Should -Not -BeNullOrEmpty
                @($entry.Fixes).Count | Should -BeGreaterThan 0
                $entry.Keys | Should -Contain 'Source'
            }
        }

        It 'ships a well-formed benign-pattern database' {
            $data = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FSLogixDoctor\Data\BenignPatterns.psd1')
            @($data.Patterns).Count | Should -BeGreaterThan 3
            foreach ($entry in $data.Patterns) {
                $entry.Pattern | Should -Not -BeNullOrEmpty
                # Patterns must tolerate arbitrary prefixes and localized suffixes.
                $entry.Pattern | Should -Match '^\*.*\*$'
                $entry.Reason | Should -Not -BeNullOrEmpty
            }
        }
    }
}
