@{
    RootModule        = 'FSLogixDoctor.psm1'
    ModuleVersion     = '1.6.0'
    GUID              = 'afcd98ed-8941-4b9d-ac1b-f6891cfc2a73'
    Author            = 'Flurin Gubler'
    Copyright         = '(c) 2026 Flurin Gubler. All rights reserved.'
    Description       = 'Diagnostics toolkit for Microsoft FSLogix profile containers. Decodes FSLogix error, status and reason codes into plain-English causes and fixes, parses FSLogix log files and event logs, finds locked, orphaned and bloated profile disks, sanity-checks the FSLogix configuration and renders self-contained HTML health reports. Read-only by default.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('FSLogix', 'AVD', 'AzureVirtualDesktop', 'ProfileContainer', 'Diagnostics', 'Troubleshooting', 'Windows', 'RDS')
            LicenseUri   = 'https://github.com/xGreeny/fslogix-doctor/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/xGreeny/fslogix-doctor'
            ReleaseNotes = 'https://github.com/xGreeny/fslogix-doctor/blob/main/CHANGELOG.md'
        }
    }
}
