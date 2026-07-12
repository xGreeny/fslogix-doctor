<#
.SYNOPSIS
    Regenerates docs/error-codes.md from the module's data files.
    Run after every change to FSLogixDoctor/Data/*.psd1.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\docs\error-codes.md')
)

$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $PSScriptRoot '..\FSLogixDoctor\Data'
$sessionCodes = Import-PowerShellDataFile (Join-Path $dataDir 'SessionCodes.psd1')
$errorCodes = Import-PowerShellDataFile (Join-Path $dataDir 'ErrorCodes.psd1')
$eventIds = Import-PowerShellDataFile (Join-Path $dataDir 'EventIds.psd1')

$sb = New-Object System.Text.StringBuilder

$null = $sb.AppendLine(@'
# FSLogix error codes, status codes and event IDs - the reference

Plain-English meaning, likely causes and concrete fixes for the codes FSLogix
writes to its logs (`%ProgramData%\FSLogix\Logs`), to the per-session registry
state (`HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID>`) and to the
`Microsoft-FSLogix-Apps` event channels.

Decode any code straight from PowerShell:

```powershell
git clone https://github.com/xGreeny/fslogix-doctor.git
Import-Module .\fslogix-doctor\FSLogixDoctor\FSLogixDoctor.psd1

Get-FslErrorCode 0x00000020    # hex, decimal, int or symbolic name
Get-FslSessionState            # translated Status/Reason/Error per session
```

Entries marked **verified** are confirmed by official Microsoft documentation
(linked per entry). Community-observed entries are marked accordingly - treat
their causes as strong heuristics, not certainties. Corrections and additions
are very welcome: see [CONTRIBUTING](../CONTRIBUTING.md).

> This page is generated from the module's data files by
> `tools/Export-ErrorCodeDoc.ps1` - edit the `.psd1` files, not this page.
'@)

function ConvertTo-SafeMarkdown {
    # The psd1 texts contain bare <placeholders>, *.vhdx wildcards and
    # underscored names; unescaped, GitHub's HTML sanitizer swallows them.
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $Text -replace '\\', '\\' -replace '<', '\<' -replace '>', '\>' -replace '\*', '\*' -replace '_', '\_'
}

function Add-Section {
    param([string]$Title, [string]$Intro, [hashtable]$Table, [scriptblock]$KeySort, [string]$KeyLabel)

    $null = $sb.AppendLine("## $Title")
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine($Intro)
    $null = $sb.AppendLine('')

    foreach ($key in ($Table.Keys | Sort-Object $KeySort)) {
        $entry = $Table[$key]
        $badge = 'community-observed'
        if ($entry.Verified) { $badge = 'verified by Microsoft docs' }
        $name = ''
        if ($entry.Name) { $name = " - $($entry.Name)" }

        $null = $sb.AppendLine("### $KeyLabel $key$name")
        $null = $sb.AppendLine('')
        $null = $sb.AppendLine("**Meaning:** $(ConvertTo-SafeMarkdown $entry.Meaning)")
        $null = $sb.AppendLine('')
        if (@($entry.Causes).Count -gt 0) {
            $null = $sb.AppendLine('**Likely causes:**')
            foreach ($cause in $entry.Causes) { $null = $sb.AppendLine("- $(ConvertTo-SafeMarkdown $cause)") }
            $null = $sb.AppendLine('')
        }
        if (@($entry.Fixes).Count -gt 0) {
            $null = $sb.AppendLine('**Fixes / next steps:**')
            foreach ($fix in $entry.Fixes) { $null = $sb.AppendLine("- $(ConvertTo-SafeMarkdown $fix)") }
            $null = $sb.AppendLine('')
        }
        $null = $sb.AppendLine("*Source:* [$($entry.Source)]($($entry.Source)) ($badge)")
        $null = $sb.AppendLine('')
    }
}

$statusTable = @{}
$reasonTable = @{}
foreach ($key in $sessionCodes.Keys) {
    if ($key -like 'Status:*') { $statusTable[($key -replace '^Status:', '')] = $sessionCodes[$key] }
    else { $reasonTable[($key -replace '^Reason:', '')] = $sessionCodes[$key] }
}

Add-Section -Title 'Profile Status codes (registry: Status)' -Intro @'
FSLogix writes the outcome of every profile attach to the `Status` value under
`HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID>`. Values 0, 100, 200 and 300 are
normal states; 1-28 are error states. Read them translated with `Get-FslSessionState`.
'@ -Table $statusTable -KeySort { [int]$_ } -KeyLabel 'Status'

Add-Section -Title 'Reason codes (registry: Reason)' -Intro @'
`Reason` clarifies **normal** Status values only - most importantly why a
container did *not* attach even though nothing failed (exclude group, existing
local profile, temp profile, non-AVD session).
'@ -Table $reasonTable -KeySort { [int]$_ } -KeyLabel 'Reason'

Add-Section -Title 'Windows error codes in FSLogix logs (and registry: Error)' -Intro @'
The `Error` registry value and the `[WARN: xxxxxxxx]` / `[ERROR:xxxxxxxx]`
markers in the text logs carry standard Windows system error codes (sometimes
in HRESULT form `0x8007xxxx`). These are the codes worth knowing in an FSLogix
context.
'@ -Table $errorCodes -KeySort { [Convert]::ToUInt32($_.Substring(2), 16) } -KeyLabel 'Code'

Add-Section -Title 'Event IDs (Microsoft-FSLogix-Apps channels)' -Intro @'
Microsoft publishes no complete FSLogix event catalog, and several IDs (26 in
particular) are generic carriers for different messages - always read the
message text, not just the ID. On any host with FSLogix installed you can dump
the authoritative per-version list with:
`(Get-WinEvent -ListProvider 'Microsoft-FSLogix-Apps').Events | Select-Object Id, Description`.
'@ -Table $eventIds -KeySort { [int]$_ } -KeyLabel 'Event'

$resolved = $OutputPath
if (-not [System.IO.Path]::IsPathRooted($resolved)) { $resolved = Join-Path (Get-Location).Path $resolved }
$parent = Split-Path -Parent $resolved
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($resolved, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $resolved"
