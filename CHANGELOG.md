# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
