# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.4.0] - 2026-07-20

### Added

- **Fleet mode**: `Invoke-FslDiagnostic -ComputerName avd-0, avd-1` runs the
  diagnostic on multiple session hosts via PowerShell remoting and merges the
  results. Findings identical across hosts (configuration drift) collapse
  into one finding listing every affected host; host-specific findings stay
  separate. Unreachable hosts become Critical 'Fleet connectivity' findings
  instead of aborting the run. The HTML report header shows the host count.
- **Monitoring output**: `-AsSummary` returns a `FSLogixDoctor.Summary`
  object (severity counts, worst severity, exit code 0/1/2, findings);
  `-AsJson` returns the same as JSON - made for RMM/monitoring sensors
  (PRTG, Zabbix, scheduled tasks).
- **Version currency check**: a curated release table
  (`Data\Releases.psd1`, with an honest AsOf date) lets the version finding
  give a verdict offline - older than the newest curated release becomes a
  Warning instead of 'compare manually'.
- **`Remove-FslOrphanedOst`**: first explicit `-Fix` companion (WhatIf-first,
  ConfirmImpact High). Deletes orphaned Outlook OST caches flagged by event
  29, keeps the newest OST per folder, skips locked files, reports per-file
  results. Never called by the diagnostic itself.

### Changed

- The single-host diagnostic pipeline moved into the internal
  `Invoke-FslLocalDiagnostic` so the local and fleet paths share one
  implementation (no behavior change).

## [1.3.0] - 2026-07-20

### Added

- Share-reachability check separates network from permissions: when the
  probe fails, a TCP 445 test against the share host distinguishes 'endpoint
  answers but denies the probing account' from 'network path down'
  (new private helper `Test-FslSmbPort`; fixture snapshots can inject the
  verdict via the `SmbPortOpen` key).
- Azure Files awareness: for `*.file.core.windows.net` locations the
  recommendation names the required RBAC roles (Storage File Data SMB Share
  Contributor / Elevated Contributor) and links the identity-based-auth
  how-to instead of the generic DNS/SMB advice.

### Changed

- `Invoke-FslDiagnostic` correlates the share probe with session state:
  sessions currently attached from the 'unreachable' share plus an open TCP
  445 downgrade the finding from Critical to Warning - the classic Azure
  Files false alarm where only the AVD users hold the share-level RBAC role
  and the diagnosing admin cannot browse. A closed SMB port stays Critical
  even with attached sessions (they may predate a real network break).

## [1.2.0] - 2026-07-20

### Added

- Curated event 29 (`ORPHANED_OST_DETECTED`): FSLogix's orphaned-OST
  housekeeping hint now explains itself and reports as Info via a new
  per-entry `Severity` override in the event database (Windows logs it as
  Warning, but an orphaned OST is a regenerable cache, not a failure).
- Curated error code `0x0000A418` (Storage Management ErrCode 42008,
  'Cannot shrink a partition containing a volume with errors'): VHD Disk
  Compaction skips containers whose inner NTFS volume has filesystem
  errors - with chkdsk-based repair guidance. Observed in the field during
  the v1.1.x rollout.
- `Get-FslEventSummary`: new `AlertMessages` (breakdown of only the
  alert-worthy messages) and `CuratedSeverity` properties.

### Changed

- Mixed buckets (real failures plus known-benign noise sharing one error
  code or event ID) now lead the evidence with the alert-worthy messages;
  noise is summarized behind them. Previously a single real failure could
  hide behind '(+N more message patterns)' when the noise dominated the
  top-3 counts.

## [1.1.1] - 2026-07-20

### Fixed

- The GPO-import noise pattern only matched the DataStore key, but real-world
  logs show the same harmless failure once per imported key (Status, Sid, ...)
  per import cycle. The pattern now covers `Import group policy * key failed`,
  so all variants classify as known-benign noise instead of masquerading as
  ACL problems under 0x00000005 'Access is denied'.

## [1.1.0] - 2026-07-20

### Added

- Known-benign noise database (`Data\BenignPatterns.psd1`). Messages that
  FSLogix logs at ERROR level but that are documented or widely observed as
  harmless - 'Failed to query activity id', the GPO DataStore import failure,
  the two documented Entra-only LDAP errors and the archived-FAQ
  SHSetKnownFolderPath exception - are recognized per message, not per error
  code. Buckets consisting entirely of noise are reported as Info.
- `Get-FslLogError`: new `Benign` property on every entry, so real errors
  separate from noise with `Where-Object { -not $_.Benign }`.
- `Get-FslEventSummary`: new `BenignCount` and `TopMessages` properties per
  bucket - generic-error IDs (notably event 26) no longer hide what the
  events actually say.

### Changed

- `Invoke-FslDiagnostic` now correlates log/event findings with the session
  state: when every recorded session attached cleanly, Critical log/event
  findings are downgraded to Warning, because no user-visible impact exists.
  Hosts with unhealthy sessions keep the Critical escalation unchanged.
- Log and event findings show a breakdown of the distinct messages behind
  each counter (digit-collapsed, top 3) instead of a single sample line, and
  alert counts exclude known-benign noise lines.

## [1.0.0] - 2026-07-13

### Added

- `Invoke-FslDiagnostic` - one-command health diagnostic for a session host.
- `Get-FslErrorCode` - curated FSLogix error-code database with plain-English
  causes and fixes, plus generic Win32 fallback for unknown codes.
- `Get-FslSessionState` - translated per-session Status/Reason/Error from the
  FSLogix Sessions registry key.
- `Get-FslLogError` - structured parser for the FSLogix text logs.
- `Get-FslEventSummary` - FSLogix event channels bucketed by event ID and
  explained.
- `Test-FslConfiguration` - misconfiguration rule set (unreachable
  VHDLocations, masked failures, local-profile collisions, Profile/ODFC
  overlap, missing antivirus exclusions, login-hang retry tuning).
- `Get-FslProfileReport` - read-only profile share scan: size, age, anomalies.
- `Get-FslOrphanedDisk` - orphaned/disabled-owner container detection.
- `Get-FslLockedProfile` - open SMB handles on container disks.
- `New-FslReport` - self-contained HTML health report.
- Pester 5 test suite, PSScriptAnalyzer gate and GitHub Actions CI
  (Windows PowerShell 5.1 + PowerShell 7).
