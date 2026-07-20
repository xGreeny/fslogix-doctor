BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force
}

Describe 'Invoke-FslDiagnostic' {

    BeforeAll {
        Mock Test-FslConfiguration -ModuleName FSLogixDoctor {
            [pscustomobject]@{
                PSTypeName = 'FSLogixDoctor.Finding'; Category = 'Configuration'; Check = 'Profiles enabled'
                Severity = 'Pass'; Target = 'HOST'; Message = 'ok'; Evidence = ''; Recommendation = ''; HelpUri = ''
            }
        }
        Mock Get-FslSessionState -ModuleName FSLogixDoctor {
            @(
                [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1002'; Account = 'LAB\mmuster'; Status = 12; StatusText = "Can't attach to virtual disk"; Reason = 0; ReasonText = 'Attached'; Error = 32; ErrorText = 'Sharing violation'; Attached = $false; Healthy = $false }
            )
        }
        Mock Get-FslLogError -ModuleName FSLogixDoctor {
            @(
                [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000020'; Message = 'Failed to open virtual disk'; File = 'C:\logs\Profile-1.log'; LineNumber = 10 }
            )
        }
        Mock Get-FslEventSummary -ModuleName FSLogixDoctor {
            @(
                # Localized display name on purpose: classification must use LevelValue.
                [pscustomobject]@{ ComputerName = 'HOST'; EventId = 26; Count = 4; Level = 'Fehler'; LevelValue = 2; Meaning = 'Attach failure'; Recommendation = 'Check storage'; FirstSeen = (Get-Date).AddHours(-3); LastSeen = Get-Date; SampleMessage = 'sample' }
            )
        }
    }

    It 'aggregates findings from every category' {
        $findings = @(Invoke-FslDiagnostic)
        ($findings | Select-Object -ExpandProperty Category -Unique) | Sort-Object |
            Should -Be @('Configuration', 'EventLog', 'LogFile', 'SessionState')
    }

    It 'converts unhealthy sessions into findings' {
        $findings = @(Invoke-FslDiagnostic)
        $sessionFindings = @($findings | Where-Object Category -eq 'SessionState')
        $sessionFindings.Count | Should -Be 1
        $sessionFindings[0].Target | Should -Be 'LAB\mmuster'
        $sessionFindings[0].Message | Should -Match 'Status=12'
    }

    It 'escalates curated log error codes to Critical severity' {
        $findings = @(Invoke-FslDiagnostic)
        $logFinding = @($findings | Where-Object Category -eq 'LogFile')
        $logFinding[0].Severity | Should -Be 'Critical'
        $logFinding[0].Message | Should -Match '0x00000020'
    }

    It 'escalates error-level event buckets to Critical severity' {
        $findings = @(Invoke-FslDiagnostic)
        $eventFinding = @($findings | Where-Object Category -eq 'EventLog')
        $eventFinding[0].Severity | Should -Be 'Critical'
        $eventFinding[0].Message | Should -Match 'event 26'
    }

    It 'sorts findings by severity, Critical first' {
        $findings = @(Invoke-FslDiagnostic)
        $findings[0].Severity | Should -Be 'Critical'
        $findings[-1].Severity | Should -Be 'Pass'
    }

    It 'writes an HTML report and returns the file when -ReportPath is used' {
        $path = Join-Path $TestDrive 'diag.html'
        $result = Invoke-FslDiagnostic -ReportPath $path
        $result | Should -BeOfType [System.IO.FileInfo]
        Test-Path $path | Should -BeTrue
    }

    It 'returns findings alongside the report with -PassThru' {
        $path = Join-Path $TestDrive 'diag2.html'
        $results = @(Invoke-FslDiagnostic -ReportPath $path -PassThru)
        @($results | Where-Object { $_ -is [System.IO.FileInfo] }) | Should -BeNullOrEmpty
        $results.Count | Should -BeGreaterThan 3
        Test-Path $path | Should -BeTrue
    }

    It 'emits Pass findings when logs and events are clean' {
        Mock Get-FslLogError -ModuleName FSLogixDoctor { @() }
        Mock Get-FslEventSummary -ModuleName FSLogixDoctor { @() }
        $findings = @(Invoke-FslDiagnostic)
        @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Severity -eq 'Pass' }).Count | Should -Be 1
        @($findings | Where-Object { $_.Category -eq 'EventLog' -and $_.Severity -eq 'Pass' }).Count | Should -Be 1
    }

    Context 'noise handling and session correlation' {

        It 'reports all-benign log buckets as Info' {
            Mock Get-FslLogError -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000057'; Message = 'Failed to query activity id for session 1 (Falscher Parameter.)'; Benign = $true; File = 'C:\logs\Profile-1.log'; LineNumber = 12 }
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000057'; Message = 'Failed to query activity id for session 7 (Falscher Parameter.)'; Benign = $true; File = 'C:\logs\Profile-1.log'; LineNumber = 40 }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $logFinding = @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Check -like '*0x00000057*' })
            $logFinding.Count | Should -Be 1
            $logFinding[0].Severity | Should -Be 'Info'
            $logFinding[0].Message | Should -Match 'known-benign'
        }

        It 'counts only alert-worthy lines and reports the benign remainder' {
            Mock Get-FslLogError -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000005'; Message = 'Failed to attach VHD (Access is denied.)'; Benign = $false; File = 'C:\logs\Profile-1.log'; LineNumber = 10 }
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000005'; Message = 'Import group policy DataStore key failed (Zugriff verweigert)'; Benign = $true; File = 'C:\logs\Profile-1.log'; LineNumber = 22 }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $logFinding = @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Check -like '*0x00000005*' })
            $logFinding[0].Message | Should -Match '^1x'
            $logFinding[0].Message | Should -Match '1 known-benign noise line'
            $logFinding[0].Evidence | Should -Match 'Messages:'
        }

        It 'downgrades Critical log findings to Warning when every session attached cleanly' {
            Mock Get-FslSessionState -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $logFinding = @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Check -like '*0x00000020*' })
            $logFinding[0].Severity | Should -Be 'Warning'
            $logFinding[0].Message | Should -Match 'attached cleanly'
            $eventFinding = @($findings | Where-Object Category -eq 'EventLog')
            $eventFinding[0].Severity | Should -Be 'Warning'
        }

        It 'reports all-benign event buckets as Info' {
            Mock Get-FslEventSummary -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ ComputerName = 'HOST'; EventId = 26; Count = 56; BenignCount = 56; Level = 'Fehler'; LevelValue = 2; Meaning = 'Generic error record'; Recommendation = 'n/a'; FirstSeen = (Get-Date).AddHours(-3); LastSeen = Get-Date; SampleMessage = 'Failed to query activity id for session 1 (Falscher Parameter.)'; TopMessages = @('56x Failed to query activity id for session # (Falscher Parameter.)') }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $eventFinding = @($findings | Where-Object Category -eq 'EventLog')
            $eventFinding[0].Severity | Should -Be 'Info'
            $eventFinding[0].Message | Should -Match 'known-benign'
            $eventFinding[0].Evidence | Should -Match 'Messages: 56x'
        }
    }

    It 'does not escalate WARN-only curated codes to Critical' {
        Mock Get-FslLogError -ModuleName FSLogixDoctor {
            @(
                # 0x00000002 is curated but documented as benign at WARN level.
                [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'WARN'; ErrorCode = '0x00000002'; Message = 'Failed to query size of VHD(x)'; File = 'C:\logs\Profile-1.log'; LineNumber = 5 }
            )
        }
        $findings = @(Invoke-FslDiagnostic -IncludeWarnings)
        $logFinding = @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Check -like '*0x00000002*' })
        $logFinding[0].Severity | Should -Be 'Warning'
    }
}
