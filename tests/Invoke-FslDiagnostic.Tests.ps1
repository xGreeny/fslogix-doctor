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
            $logFinding[0].Evidence | Should -Match 'Alert-worthy:'
        }

        It 'leads the log evidence with the alert-worthy message even when noise dominates' {
            Mock Get-FslLogError -ModuleName FSLogixDoctor {
                $noise = 1..10 | ForEach-Object {
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000005'; Message = "Import group policy Status key failed (Zugriff verweigert)"; Benign = $true; File = 'C:\logs\Profile-1.log'; LineNumber = $_ }
                }
                $noise + @(
                    [pscustomobject]@{ Timestamp = Get-Date; Component = 'Profile'; Level = 'ERROR'; ErrorCode = '0x00000005'; Message = 'Failed to attach VHD (Access is denied.)'; Benign = $false; File = 'C:\logs\Profile-1.log'; LineNumber = 99 }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $logFinding = @($findings | Where-Object { $_.Category -eq 'LogFile' -and $_.Check -like '*0x00000005*' })
            $logFinding[0].Evidence | Should -Match '^Alert-worthy: 1x Failed to attach VHD'
            $logFinding[0].Evidence | Should -Not -Match 'Alert-worthy:.*Import group policy'
        }

        It 'leads the event evidence with the alert-worthy message in mixed buckets' {
            Mock Get-FslEventSummary -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ ComputerName = 'HOST'; EventId = 26; Count = 69; BenignCount = 68; Level = 'Fehler'; LevelValue = 2; CuratedSeverity = $null; Meaning = 'Generic error record'; Recommendation = 'n/a'; FirstSeen = (Get-Date).AddHours(-3); LastSeen = Get-Date; SampleMessage = 'noise'; TopMessages = @('24x Failed to query activity id for session # (Falscher Parameter.)'); AlertMessages = @('1x Volume optimization failed, Path: C:\x.vhdx') }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $eventFinding = @($findings | Where-Object Category -eq 'EventLog')
            $eventFinding[0].Evidence | Should -Match 'Alert-worthy: 1x Volume optimization failed'
            $eventFinding[0].Evidence | Should -Match 'Plus 68x known-benign noise'
        }

        It 'downgrades an unreachable-share probe when sessions are attached and TCP 445 is open' {
            Mock Test-FslConfiguration -ModuleName FSLogixDoctor {
                [pscustomobject]@{
                    PSTypeName = 'FSLogixDoctor.Finding'; Category = 'Configuration'; Check = 'VHDLocations reachable'
                    Severity = 'Critical'; Target = 'HOST'
                    Message = "Profile location '\\sa.file.core.windows.net\prof' is NOT reachable from this host (as the probing user)."
                    Evidence = "TCP 445 to 'sa.file.core.windows.net' is open - the endpoint answers, so this looks like missing share permissions for the probing account 'admin', not a network problem."
                    Recommendation = 'rbac'; HelpUri = ''
                }
            }
            Mock Get-FslSessionState -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $probe = @($findings | Where-Object Check -eq 'VHDLocations reachable')
            $probe[0].Severity | Should -Be 'Warning'
            $probe[0].Message | Should -Match 'Downgraded from Critical: 1 session'
        }

        It 'downgrades the share probe to Info for the expected fleet double-hop' {
            Mock Test-FslConfiguration -ModuleName FSLogixDoctor {
                [pscustomobject]@{
                    PSTypeName = 'FSLogixDoctor.Finding'; Category = 'Configuration'; Check = 'VHDLocations reachable'
                    Severity = 'Critical'; Target = 'HOST'
                    Message = "Profile location '\\fs01\prof' is NOT reachable from this host (as the probing user)."
                    Evidence = "The probe ran inside a remote (WinRM) session, where Kerberos blocks the second hop to the file server - this failure is expected in fleet mode regardless of the account's real permissions. TCP 445 to 'fs01' is open."
                    Recommendation = 'rbac'; HelpUri = ''
                }
            }
            Mock Get-FslSessionState -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $probe = @($findings | Where-Object Check -eq 'VHDLocations reachable')
            $probe[0].Severity | Should -Be 'Info'
            $probe[0].Message | Should -Match 'expected in fleet mode'
        }

        It 'keeps the unreachable-share probe Critical when TCP 445 is closed' {
            Mock Test-FslConfiguration -ModuleName FSLogixDoctor {
                [pscustomobject]@{
                    PSTypeName = 'FSLogixDoctor.Finding'; Category = 'Configuration'; Check = 'VHDLocations reachable'
                    Severity = 'Critical'; Target = 'HOST'
                    Message = "Profile location '\\fs01\prof' is NOT reachable from this host (as the probing user)."
                    Evidence = "TCP 445 to 'fs01' is NOT answering (blocked or offline) - this is a network/endpoint problem, not a permissions issue."
                    Recommendation = 'network'; HelpUri = ''
                }
            }
            Mock Get-FslSessionState -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $probe = @($findings | Where-Object Check -eq 'VHDLocations reachable')
            $probe[0].Severity | Should -Be 'Critical'
            $probe[0].Message | Should -Not -Match 'Downgraded'
        }

        It 'honors the curated severity override for housekeeping events' {
            Mock Get-FslEventSummary -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ ComputerName = 'HOST'; Channel = 'Microsoft-FSLogix-Apps/Operational'; EventId = 29; Count = 2; BenignCount = 0; Level = 'Warnung'; LevelValue = 3; CuratedSeverity = 'Info'; Meaning = 'Orphaned OST housekeeping'; Recommendation = 'Delete the orphaned OST'; FirstSeen = (Get-Date).AddHours(-1); LastSeen = Get-Date; SampleMessage = 'Orphaned OST file(s) found.'; TopMessages = @('2x Orphaned OST file(s) found. Username: user#'); AlertMessages = @('2x Orphaned OST file(s) found. Username: user#') }
                )
            }
            $findings = @(Invoke-FslDiagnostic)
            $eventFinding = @($findings | Where-Object Category -eq 'EventLog')
            $eventFinding[0].Severity | Should -Be 'Info'
            $eventFinding[0].Message | Should -Match 'Orphaned OST'
            $eventFinding[0].Evidence | Should -Match 'in Microsoft-FSLogix-Apps/Operational'
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

    Context 'fleet mode' {

        It 'merges findings that are identical across hosts and keeps host-specific ones separate' {
            Mock Invoke-Command -ModuleName FSLogixDoctor {
                # PSComputerName/RunspaceId simulate the metadata that real
                # remoting tacks onto returned objects.
                $remoteHost = [string]$ComputerName
                @(
                    [pscustomobject]@{ PSTypeName = 'FSLogixDoctor.Finding'; Category = 'Configuration'; Check = 'Failure masking'; Severity = 'Warning'; Target = $remoteHost; Message = 'PreventLoginWithFailure=0'; Evidence = 'same'; Recommendation = 'set to 1'; HelpUri = ''; PSComputerName = $remoteHost; RunspaceId = [guid]::NewGuid() }
                    [pscustomobject]@{ PSTypeName = 'FSLogixDoctor.Finding'; Category = 'LogFile'; Check = 'Log errors (0x00000005)'; Severity = 'Info'; Target = $remoteHost; Message = ("noise on {0}" -f $remoteHost); Evidence = ''; Recommendation = ''; HelpUri = ''; PSComputerName = $remoteHost; RunspaceId = [guid]::NewGuid() }
                )
            }
            $findings = @(Invoke-FslDiagnostic -ComputerName 'AVD-0', 'AVD-1')
            $mergedFinding = @($findings | Where-Object Check -eq 'Failure masking')
            $mergedFinding.Count | Should -Be 1
            $mergedFinding[0].Target | Should -Be 'AVD-0, AVD-1'
            $mergedFinding[0].Message | Should -Match 'Affects 2 hosts'
            @($findings | Where-Object Check -eq 'Log errors (0x00000005)').Count | Should -Be 2
        }

        It 'strips remoting metadata from fleet findings' {
            Mock Invoke-Command -ModuleName FSLogixDoctor {
                $remoteHost = [string]$ComputerName
                @(
                    [pscustomobject]@{ PSTypeName = 'FSLogixDoctor.Finding'; Category = 'LogFile'; Check = 'Log errors (0x00000005)'; Severity = 'Info'; Target = $remoteHost; Message = ("noise on {0}" -f $remoteHost); Evidence = ''; Recommendation = ''; HelpUri = ''; PSComputerName = $remoteHost; RunspaceId = [guid]::NewGuid() }
                )
            }
            $findings = @(Invoke-FslDiagnostic -ComputerName 'AVD-0')
            foreach ($fleetFinding in $findings) {
                $fleetFinding.PSObject.Properties['PSComputerName'] | Should -BeNullOrEmpty
                $fleetFinding.PSObject.Properties['RunspaceId'] | Should -BeNullOrEmpty
            }
        }

        It 'turns an unreachable host into a Critical fleet-connectivity finding' {
            Mock Invoke-Command -ModuleName FSLogixDoctor { throw 'WinRM cannot complete the operation' }
            $findings = @(Invoke-FslDiagnostic -ComputerName 'AVD-DEAD')
            $connectivity = @($findings | Where-Object Check -eq 'Fleet connectivity')
            $connectivity.Count | Should -Be 1
            $connectivity[0].Severity | Should -Be 'Critical'
            $connectivity[0].Target | Should -Be 'AVD-DEAD'
            $connectivity[0].Message | Should -Match 'WinRM'
        }
    }

    Context 'summary and JSON output' {

        It 'returns a summary object with counts and a monitoring exit code' {
            $summary = Invoke-FslDiagnostic -AsSummary
            $summary.PSObject.TypeNames | Should -Contain 'FSLogixDoctor.Summary'
            $summary.CriticalCount | Should -BeGreaterThan 0
            $summary.WorstSeverity | Should -Be 'Critical'
            $summary.ExitCode | Should -Be 2
            @($summary.Findings).Count | Should -BeGreaterThan 3
        }

        It 'returns valid JSON with -AsJson' {
            $json = Invoke-FslDiagnostic -AsJson
            $json | Should -BeOfType [string]
            $parsed = $json | ConvertFrom-Json
            $parsed.WorstSeverity | Should -Be 'Critical'
            $parsed.ExitCode | Should -Be 2
        }

        It 'reports ExitCode 0 when only Pass and Info findings exist' {
            Mock Get-FslSessionState -ModuleName FSLogixDoctor {
                @(
                    [pscustomobject]@{ Container = 'Profile'; Sid = 'S-1-5-21-1-2-3-1001'; Account = 'LAB\jdoe'; Status = 0; StatusText = 'Success'; Reason = 0; ReasonText = 'Attached'; Error = 0; ErrorText = $null; Attached = $true; Healthy = $true }
                )
            }
            Mock Get-FslLogError -ModuleName FSLogixDoctor { @() }
            Mock Get-FslEventSummary -ModuleName FSLogixDoctor { @() }
            $summary = Invoke-FslDiagnostic -AsSummary
            $summary.ExitCode | Should -Be 0
            $summary.CriticalCount | Should -Be 0
            $summary.WarningCount | Should -Be 0
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
