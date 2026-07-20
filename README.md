# fslogix-doctor

[![CI](https://github.com/xGreeny/fslogix-doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/xGreeny/fslogix-doctor/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/FSLogixDoctor.svg?label=PSGallery)](https://www.powershellgallery.com/packages/FSLogixDoctor)
[![PSGallery downloads](https://img.shields.io/powershellgallery/dt/FSLogixDoctor.svg)](https://www.powershellgallery.com/packages/FSLogixDoctor)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-blue.svg)](#requirements)

**Answers "why did this FSLogix profile fail to attach?" in one command - and
translates every cryptic FSLogix error code into a cause and a fix.**

It is 2 a.m., a login storm is running, and the only clues are
`[ERROR:00000020]` in a text log, `Status=12` in some registry key, and an
event 26 that means five different things. FSLogixDoctor reads all three
sources, translates them against a curated, source-linked database, and tells
you what is wrong in plain English - read-only, no agent, no telemetry.

```powershell
PS> Get-FslErrorCode 0x00000020

Code       : 0x00000020
Name       : ERROR_SHARING_VIOLATION
Meaning    : The profile disk is open in another session or process - the classic
             "profile already in use" scenario.
Causes     : {User still has an active or stale session on another host, Stale SMB
             handle on the file server after a session host crash, Antivirus or
             backup agent holding the VHDX open...}
Fixes      : {Sign the user out of all other sessions, Find and release the stale
             handle: Get-FslLockedProfile on the file server, Apply the
             Microsoft-recommended antivirus exclusions...}
InDatabase : True
```

## Quick start

```powershell
# From the PowerShell Gallery:
Install-Module -Name FSLogixDoctor -Scope CurrentUser

# Or from source:
git clone https://github.com/xGreeny/fslogix-doctor.git
Import-Module .\fslogix-doctor\FSLogixDoctor\FSLogixDoctor.psd1

# Full health diagnostic of a session host, findings on the pipeline:
Invoke-FslDiagnostic

# Same, but as a self-contained HTML report you can attach to a ticket:
Invoke-FslDiagnostic -Hours 8 -ReportPath .\fslogix-report.html
```

**[View a sample report](samples/sample-report.html)** (synthetic lab data) -
download and open locally, or view it rendered via
[htmlpreview](https://htmlpreview.github.io/?https://github.com/xGreeny/fslogix-doctor/blob/main/samples/sample-report.html).

## The error-code reference

The heart of this project is a curated database of FSLogix **status codes**,
**reason codes**, **Windows error codes** and **event IDs** - each with meaning,
likely causes, concrete fixes and a link to the source. Where Microsoft
documents a code, the entry is marked verified; community-observed entries are
labeled as such.

**Browse it here: [docs/error-codes.md](docs/error-codes.md)** - or query it
from PowerShell with `Get-FslErrorCode` (hex, decimal, integer or symbolic
name) and `Get-FslSessionState` (translated per-session state).

## What's inside

| Function | What it answers | Run on |
|---|---|---|
| `Invoke-FslDiagnostic` | "What is wrong with FSLogix on this host?" - all checks below, one command, optional HTML report; fleet mode via `-ComputerName` (incl. config-drift detection), monitoring output via `-AsSummary`/`-AsJson`, run history and new/persisting/resolved diffs via `-HistoryPath`, store capacity checks via `-ProfileStorePath` | session host or admin box |
| `Get-FslErrorCode` | "What does `0x00000020` mean and how do I fix it?" | anywhere |
| `Get-FslSessionState` | "Why did this user get a temp profile?" - translated Status/Reason/Error per session | session host |
| `Get-FslLogError` | Structured WARN/ERROR entries from the FSLogix text logs, codes extracted and normalized (incl. HRESULT form) | session host |
| `Get-FslEventSummary` | FSLogix event channels bucketed by ID and explained | session host |
| `Get-FslContextEvent` | Curated profile-related events from the surrounding Windows logs (User Profile Service, NTFS, disk) | session host |
| `Test-FslConfiguration` | Misconfigurations that cause temp profiles, login hangs and data loss - 15+ rules distilled from real troubleshooting | session host |
| `Get-FslProfileReport` | Size, age and structural anomalies of every container on a share - without mounting anything | anywhere with share access |
| `Get-FslOrphanedDisk` | "Which containers belong to deleted/disabled users, and how many GB do I get back?" | anywhere with share access |
| `Get-FslLockedProfile` | "Who is holding this VHDX open?" - stale SMB handles behind 'profile in use' | file server |
| `New-FslReport` | Any findings → one self-contained HTML report | anywhere |
| `Remove-FslOrphanedOst` | Cleanup companion to event 29: deletes orphaned Outlook OST caches, WhatIf-first | session host / mounted container |
| `Remove-FslOrphanedDisk` | Cleanup companion to `Get-FslOrphanedDisk`: deletes or archives confirmed-orphaned containers, WhatIf-first | anywhere with share access |

## Design principles

- **Read-only by default.** Nothing in this module mutates a system. Where a
  fix is obvious (e.g. releasing a stale SMB handle), the output hands you the
  exact command including `-Confirm` - executing it stays a human decision.
- **Trustworthy explanations.** Every database entry links its source and is
  flagged verified (Microsoft docs) or community-observed. Unknown codes fall
  back to the generic Win32 message instead of guessing.
- **No dependencies, no telemetry.** Plain PowerShell 5.1+ (runs on the oldest
  session host you still operate), optional integrations (ActiveDirectory
  module, SMB cmdlets) degrade gracefully. Reports are single HTML files with
  zero external assets.
- **Tested like software, not like a script dump.** 193 Pester tests against
  fixtures (no live environment needed in CI), PSScriptAnalyzer gate, CI matrix
  on Windows PowerShell 5.1 and PowerShell 7. Locale-independence is tested
  explicitly - the module behaves identically on German and English Windows.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+ on Windows
- FSLogix installed on the target session host (for the host-side checks)
- Optional: `ActiveDirectory` module for disabled-account detection,
  SMB cmdlets on the file server for `Get-FslLockedProfile`

## Roadmap

- [x] On the [PowerShell Gallery](https://www.powershellgallery.com/packages/FSLogixDoctor) (since v1.2.0)
- [ ] `Get-FslProfileReport`: parallel scanning for multi-TB shares
- [x] Optional `-Fix` companions (explicit, `-WhatIf`-first) - first one: `Remove-FslOrphanedOst` (v1.4.0)
- [ ] Cloud Cache (CCD) health checks
- [ ] More error codes - contribute the ones you have diagnosed!

## Contributing

The most valuable contribution is an error code you have actually root-caused -
see [CONTRIBUTING.md](CONTRIBUTING.md). Please never include customer- or
environment-identifiable data in issues, fixtures or examples.

## License and disclaimer

MIT - see [LICENSE](LICENSE). This is a personal lab project, not affiliated
with or endorsed by Microsoft or any employer. FSLogix is a trademark of
Microsoft Corporation. All diagnostics run at your own risk - they are
read-only, but you remain responsible for your environment.
