# Contributing

Thanks for considering a contribution - especially to the error-code database,
which only gets better through real-world troubleshooting experience.

## Contributing error codes

The most valuable contribution is a code you have actually diagnosed:

1. Add the entry to `FSLogixDoctor/Data/ErrorCodes.psd1` (keep the existing
   structure: `Name`, `Meaning`, `Causes`, `Fixes`, `Source`, `Verified`).
2. `Verified = $true` is reserved for codes confirmed by Microsoft
   documentation - link the doc as `Source`. Community-observed codes are
   welcome with `Verified = $false` and a source link (blog, forum thread).
3. Regenerate the reference page: `./tools/Export-ErrorCodeDoc.ps1`.
4. Never include customer-identifiable data (hostnames, domains, usernames)
   in examples or fixtures.

## Code contributions

- Target Windows PowerShell 5.1 **and** PowerShell 7 - no PS7-only syntax
  (ternaries, null-coalescing).
- Every public function needs comment-based help and Pester tests.
- Run the suite before pushing: `./tools/Invoke-Tests.ps1` and
  `Invoke-ScriptAnalyzer -Path ./FSLogixDoctor -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`.
- All diagnostics stay **read-only by default**. Anything that changes state
  needs `-WhatIf`/`-Confirm` support and an explicit, documented decision.

## Reporting bugs

Open an issue with the FSLogix version, Windows version, and - if possible -
the sanitized log lines or event IDs involved.
