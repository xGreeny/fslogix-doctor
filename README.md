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
event 26 that means five different things. FSLogixDoctor reads every source
that matters - configuration, per-session state, the FSLogix text logs and
event channels, the surrounding Windows logs and the profile store itself -
translates them against curated, source-linked databases, correlates symptom
with cause, and tells you what is wrong in plain English. And because it
remembers yesterday's run, it tells you what is *newly* broken, not just what
is broken. Read-only diagnostics, no agent, no telemetry.

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

# Full health diagnostic - store scan, run history and HTML report included
# automatically (report lands in %ProgramData%\FSLogixDoctor\Reports):
Invoke-FslDiagnostic

# Whole fleet, one merged report at a path of your choice:
Invoke-FslDiagnostic -ComputerName avd-0, avd-1 -ReportPath .\fleet.html

# RMM/monitoring sensor: exit 0 = healthy, 1 = warnings, 2 = critical
$r = Invoke-FslDiagnostic -AsSummary -NoReport; exit $r.ExitCode
```

**[View a sample report](samples/sample-report.html)** (synthetic lab data) -
download and open locally, or view it rendered via
[htmlpreview](https://htmlpreview.github.io/?https://github.com/xGreeny/fslogix-doctor/blob/main/samples/sample-report.html).

## The curated databases

The heart of this project is a set of six curated, field-validated databases:
FSLogix **status codes**, **reason codes**, **Windows error codes** and
**event IDs**, plus the **profile-related events from the surrounding Windows
logs** (User Profile Service, NTFS, disk) and the **known-benign noise
patterns** the diagnostic suppresses so real findings stand out. Every entry
carries meaning, likely causes, concrete fixes and a link to the source; where
Microsoft documents a code, the entry is marked verified, and
community-observed entries are labeled as such.

**Browse it all here: [docs/error-codes.md](docs/error-codes.md)** - or query
it from PowerShell with `Get-FslErrorCode` (hex, decimal, integer or symbolic
name) and `Get-FslSessionState` (translated per-session state).

## What's inside

| Function | What it answers | Run on |
|---|---|---|
| `Invoke-FslDiagnostic` | "What is wrong with FSLogix on this host?" - every check below in one zero-parameter command: store scan (auto-detected), run history with new/persisting/resolved diffs and HTML report happen automatically; fleet mode via `-ComputerName` (incl. config-drift detection), monitoring output via `-AsSummary`/`-AsJson`; opt-outs `-NoProfileStore`/`-NoHistory`/`-NoReport` | session host or admin box |
| `Get-FslErrorCode` | "What does `0x00000020` mean and how do I fix it?" | anywhere |
| `Get-FslSessionState` | "Why did this user get a temp profile?" - translated Status/Reason/Error per session | session host |
| `Get-FslLogError` | Structured WARN/ERROR entries from the FSLogix text logs, codes extracted and normalized (incl. HRESULT form) | session host |
| `Get-FslEventSummary` | FSLogix event channels bucketed by ID and explained | session host |
| `Get-FslContextEvent` | Curated profile-related events from the surrounding Windows logs (User Profile Service, NTFS, disk) | session host |
| `Test-FslConfiguration` | Misconfigurations that cause temp profiles, login hangs and data loss - 20+ rules distilled from real troubleshooting | session host |
| `Get-FslProfileReport` | Size, age and structural anomalies of every container on a share - without mounting anything | anywhere with share access |
| `Get-FslOrphanedDisk` | "Which containers belong to deleted/disabled users, and how many GB do I get back?" | anywhere with share access |
| `Get-FslLockedProfile` | "Who is holding this VHDX open?" - stale SMB handles behind 'profile in use' | file server |
| `New-FslReport` | Any findings → one self-contained HTML report | anywhere |
| `Remove-FslOrphanedOst` | Cleanup companion to event 29: deletes orphaned Outlook OST caches, WhatIf-first | session host / mounted container |
| `Remove-FslOrphanedDisk` | Cleanup companion to `Get-FslOrphanedDisk`: deletes or archives confirmed-orphaned containers, WhatIf-first | anywhere with share access |

## Design principles

- **Read-only diagnostics.** Nothing in this module mutates FSLogix or Windows
  state; the only writes are the module's own artifacts - run history and HTML
  reports under `%ProgramData%\FSLogixDoctor` (opt out with `-NoHistory` /
  `-NoReport`). Where a fix is obvious, the output hands you the exact command
  including `-Confirm` - executing it stays a human decision, and the `-Fix`
  companions are WhatIf-first.
- **Trustworthy explanations.** Every database entry links its source and is
  flagged verified (Microsoft docs) or community-observed. Unknown codes fall
  back to the generic Win32 message instead of guessing.
- **No dependencies, no telemetry.** Plain PowerShell 5.1+ (runs on the oldest
  session host you still operate), optional integrations (ActiveDirectory
  module, SMB cmdlets) degrade gracefully. Reports are single HTML files with
  zero external assets.
- **Tested like software, not like a script dump.** 196 Pester tests against
  fixtures (no live environment needed in CI), PSScriptAnalyzer gate, CI matrix
  on Windows PowerShell 5.1 and PowerShell 7. Locale-independence is tested
  explicitly - the module behaves identically on German and English Windows.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+ on Windows
- FSLogix installed on the target session host (for the host-side checks)
- Write access to `%ProgramData%\FSLogixDoctor` for the automatic run history
  and reports (they fail soft with a warning without it - the diagnostics
  themselves need no write access)
- Optional: `ActiveDirectory` module for disabled-account detection,
  SMB cmdlets on the file server for `Get-FslLockedProfile`

## Roadmap

- [x] On the [PowerShell Gallery](https://www.powershellgallery.com/packages/FSLogixDoctor) (since v1.2.0)
- [x] `-Fix` companions (explicit, `-WhatIf`-first): `Remove-FslOrphanedOst` (v1.4.0), `Remove-FslOrphanedDisk` (v1.6.0)
- [ ] Built-in retention for the run history (rotate old `run-*.json` files)
- [ ] More context channels as the field demands them (SMB client, Winlogon)
- [ ] Cross-correlate event 33 with the store scan ("VHDX resized but the partition inside was not extended")
- [ ] `Get-FslProfileReport`: parallel scanning for multi-TB shares
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
