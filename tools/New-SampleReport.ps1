<#
.SYNOPSIS
    Generates samples/sample-report.html from synthetic lab findings.
    All names, paths and SIDs are fabricated - no real environment data.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\samples\sample-report.html')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\FSLogixDoctor\FSLogixDoctor.psd1') -Force

function New-SampleFinding {
    param($Category, $Check, $Severity, $Target, $Message, $Evidence = '', $Recommendation = '', $HelpUri = '')
    [pscustomobject]@{
        PSTypeName     = 'FSLogixDoctor.Finding'
        Category       = $Category
        Check          = $Check
        Severity       = $Severity
        Target         = $Target
        Message        = $Message
        Evidence       = $Evidence
        Recommendation = $Recommendation
        HelpUri        = $HelpUri
    }
}

$configHelp = 'https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings'

$findings = @(
    New-SampleFinding 'SessionState' 'Session attach state' 'Critical' 'LAB\mmuster' `
        "Last attach did not complete cleanly: Status=12 (Can't attach to virtual disk), Reason=0 (The container is attached)." `
        'Error: 32 - The profile disk is open in another session or process (sharing violation): the classic "profile already in use".' `
        'Correlate with Get-FslLockedProfile on the file server: a stale SMB handle from LAB-SH-02 is the most likely holder.'
    New-SampleFinding 'LogFile' 'Log errors (0x00000020)' 'Critical' 'LAB-SH-01' `
        '7x in the last 24h: [0x00000020] ERROR_SHARING_VIOLATION - the container is already open elsewhere.' `
        'Sample: Failed to open virtual disk (The process cannot access the file because it is being used by another process.) (C:\ProgramData\FSLogix\Logs\Profile\Profile-20260712.log:214)' `
        'Sign the user out everywhere or release the stale handle (Close-SmbOpenFile after verification), then retry.'
    New-SampleFinding 'EventLog' 'Event 26' 'Critical' 'LAB-SH-01' `
        '4x event 26: container attach failure reported by the FSLogix Apps service.' `
        'Last seen 2026-07-12 07:41. Sample: Failed to attach VHD for user LAB\mmuster' `
        'Event 26 carries multiple message types - read the message text and pair it with the Status/Reason codes from Get-FslSessionState.'
    New-SampleFinding 'Configuration' 'Failure masking' 'Warning' 'LAB-SH-01' `
        'PreventLoginWithFailure=0 and PreventLoginWithTempProfile=0: when the container attach fails, users silently work in a temp profile and changes are lost at logoff.' `
        'Correlate with session Reason=7 (temp profile) to find affected users.' `
        'Set both to 1 in production so attach failures surface immediately instead of costing user data.' $configHelp
    New-SampleFinding 'Configuration' 'Antivirus exclusions' 'Warning' 'LAB-SH-01' `
        'Profile share paths are not in the Microsoft Defender path exclusions; on-access scanning of container disks degrades logon performance and can cause locks.' `
        'Not excluded: \\lab-fs01\fslogix$' `
        'Add the Microsoft-recommended FSLogix exclusions.' 'https://learn.microsoft.com/en-us/fslogix/overview-prerequisites#configure-antivirus-file-and-folder-exclusions'
    New-SampleFinding 'ProfileStore' 'Orphaned containers' 'Warning' '\\lab-fs01\fslogix$' `
        '3 container disks belong to deleted or disabled accounts - 41.5 GB reclaimable.' `
        'Largest: Profile_tmuellerx.vhdx (18.2 GB, last used 214 days ago).' `
        'Review with Get-FslOrphanedDisk, archive if policy requires, then delete deliberately - the tool never deletes on its own.'
    New-SampleFinding 'Configuration' 'Log retention' 'Info' 'LAB-SH-01' `
        'LogFileKeepingPeriod=2 days (default 2) - often too short to investigate incidents reported after a weekend.' '' `
        'Raise to at least 7-14 days (maximum 180).' $configHelp
    New-SampleFinding 'Environment' 'FSLogix version' 'Info' 'LAB-SH-01' `
        'Installed FSLogix version: 2.9.8884.27471.' '' `
        'Compare against the current release and known issues: https://learn.microsoft.com/en-us/fslogix/overview-release-notes'
    New-SampleFinding 'Environment' 'FSLogix service running' 'Pass' 'LAB-SH-01' `
        'The FSLogix service (frxsvc) is running.' 'Version: 2.9.8884.27471'
    New-SampleFinding 'Configuration' 'Profiles enabled' 'Pass' 'LAB-SH-01' `
        'FSLogix profile containers are enabled.'
    New-SampleFinding 'Configuration' 'VHDLocations reachable' 'Pass' 'LAB-SH-01' `
        "Profile location '\\lab-fs01\fslogix$' is reachable."
    New-SampleFinding 'SessionState' 'Session attach state' 'Pass' 'LAB\jdoe' `
        'Attached cleanly: Status=0 (Success), Reason=0 (The container is attached).'
)

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

$report = $findings | New-FslReport -Path $OutputPath -Title 'FSLogix Health Report - LAB-SH-01 (sample, synthetic data)'
Write-Host "Wrote $($report.FullName)"
