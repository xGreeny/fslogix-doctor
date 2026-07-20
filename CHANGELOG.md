# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.6.1] - 2026-07-20

### Fixed

- The HTML report no longer counts shares or user accounts as 'hosts': the
  host list behind the title, header label and status chips excludes
  ProfileStore targets and path-like targets. A fleet report with a store
  scan showed the profile share as a third 'host' chip and titled itself
  '3 hosts' for a two-host fleet.

## [1.6.0] - 2026-07-20

### Added

- **Run history and diff** (`Invoke-FslDiagnostic -HistoryPath`, opt-in so
  the module stays read-only by default): every run is persisted as JSON and
  diffed against the previous run of the same scope. Findings carry a
  `ChangeStatus` (New/Persisting/Resolved), alert-worthy messages are
  annotated ('New since the last run', 'Persisting - seen in N consecutive
  runs'), vanished Critical/Warning findings resurface as 'Resolved' Info
  findings, the summary gains `NewCount`/`ResolvedCount`, and the report
  verdict shows 'since last run: N new, M resolved'. The daily run now
  answers 'what is NEWLY broken?' instead of 'what is broken?'.
- **Profile store scan** (`-IncludeProfileStore` / `-ProfileStorePath`):
  containers at >=85% of their maximum become Warnings, >=95% Critical -
  FSLogix's own event 33 only fires below 200 MB free, which is too late.
  Structural anomalies (leftover/multi-disk folders) become findings with
  cleanup guidance. Runs once from the coordinator in fleet mode.
- **`Remove-FslOrphanedDisk`**: second explicit -Fix companion. Acts only on
  disks Get-FslOrphanedDisk classified as 'Orphaned' (never Disabled or
  Unknown), supports -ArchivePath (move instead of delete), removes emptied
  container folders, WhatIf-first with ConfirmImpact High.
- **Fleet configuration drift**: fleet runs compare the 12 core FSLogix
  registry values across hosts and emit one Warning per drifting value with
  per-host evidence - two hosts with different SizeInMBs, each unremarkable
  on its own, only surface here.

## [1.5.1] - 2026-07-20

### Changed

- HTML report visual redesign on a validated palette: severity is now
  encoded as shape glyph + label + color (never color alone - CVD- and
  print-safe), Info renders neutral instead of blue so only findings that
  need action carry color, zero-count tiles render muted, and warning/
  critical rows carry an accent edge for scanning. Warm neutral surfaces
  with an anchored dark header replace the blue-gray look, and the report
  ships a native dark mode (follows the OS setting, deliberately stepped
  values instead of an automatic invert). Still plain HTML/CSS, one file,
  no JavaScript.

## [1.5.0] - 2026-07-20

### Added

- HTML report: fleet-aware default title ('FSLogix Fleet Report - N hosts';
  single-host reports are named after the target host instead of the
  executing machine), per-host status chips showing each host's worst
  severity at a glance, and an 'Action items' section that lists every
  Critical/Warning finding with its recommendation before the detail
  tables - real work no longer drowns between Info rows.
- HTML report: long curated meanings collapse behind a plain <details>
  element (no JavaScript, still self-contained); the look-back window
  appears in the header (`New-FslReport -LookbackHours`, passed
  automatically by Invoke-FslDiagnostic).

### Fixed

- Fleet mode no longer produces pseudo-warnings for the share probe: inside
  a remote (WinRM) session, Kerberos blocks the second hop to the file
  server, so the probe fails regardless of the account's permissions. The
  probe now detects remote execution ($PSSenderInfo; fixture snapshots can
  inject `InRemoteSession`), says so in the evidence, and with healthy
  sessions the finding lands at Info ('expected in fleet mode') instead of
  Warning.
- Message breakdowns truncate at 240 instead of 160 characters, so details
  such as the event-29 'Potential Savings' figure survive.

## [1.4.1] - 2026-07-20

### Fixed

- Event 33 curated entry corrected from field evidence: it is a container
  free-space warning in Microsoft-FSLogix-Apps/Admin ('less than 200 MB free
  space left ... Logins will fail if the vhd(x) gets too full'), not the
  community-claimed attach failure. Causes/fixes now cover profile bloat,
  Remove-FslOrphanedOst, VHDX resize and the Get-FslProfileReport overview.
- Event findings name the channel in the evidence ('Last seen ... in
  Microsoft-FSLogix-Apps/Admin'); `Get-FslEventSummary` gained a `Channel`
  property. Follow-up Get-WinEvent queries no longer have to guess between
  Operational and Admin.
- Fleet findings are rebuilt as clean objects: the PSComputerName/RunspaceId
  metadata that PowerShell remoting attaches no longer pollutes the output.

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
