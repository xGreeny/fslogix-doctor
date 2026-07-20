function New-FslReport {
    <#
    .SYNOPSIS
        Renders FSLogixDoctor findings into a single self-contained HTML report.
    .DESCRIPTION
        Produces one HTML file with an at-a-glance severity summary and the detailed
        findings grouped by category. No external assets, no JavaScript frameworks,
        no telemetry - the file can be mailed to a customer or attached to a ticket.
    .PARAMETER Finding
        FSLogixDoctor.Finding objects, typically from Invoke-FslDiagnostic or
        Test-FslConfiguration. Accepts pipeline input.
    .PARAMETER Path
        Output path of the HTML file.
    .PARAMETER Title
        Report title. Defaults to 'FSLogix Health Report - <computer>'.
    .EXAMPLE
        Test-FslConfiguration | New-FslReport -Path .\fslogix-report.html
    .EXAMPLE
        Invoke-FslDiagnostic -ReportPath .\report.html

        Invoke-FslDiagnostic calls New-FslReport internally.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject[]]$Finding,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Title = '',

        [ValidateRange(0, 8760)]
        [int]$LookbackHours = 0
    )

    begin {
        $all = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($item in $Finding) { $all.Add($item) }
    }

    end {
        # Fleet reports carry merged targets ('host-a, host-b'); the distinct
        # host list drives the title, the header label and the status chips.
        $hostNames = @($all | ForEach-Object { ([string]$_.Target) -split ',\s*' } |
                Where-Object { $_ } | Select-Object -Unique | Sort-Object)
        $hostCount = $hostNames.Count
        $hostLabel = '1 host'
        if ($hostCount -ne 1) { $hostLabel = ('{0} hosts' -f $hostCount) }

        if (-not $Title) {
            if ($hostCount -gt 1) { $Title = 'FSLogix Fleet Report - {0} hosts' -f $hostCount }
            elseif ($hostCount -eq 1) { $Title = 'FSLogix Health Report - {0}' -f $hostNames[0] }
            else { $Title = 'FSLogix Health Report - {0}' -f $env:COMPUTERNAME }
        }
        if (-not $PSCmdlet.ShouldProcess($Path, 'Write HTML report')) { return }

        $encode = { param([object]$text) [System.Net.WebUtility]::HtmlEncode([string]$text) }

        # Severity is never color alone: every state pairs a shape glyph with its
        # label (CVD- and print-safe). Critical X, Warning triangle, Info circle,
        # Pass check.
        $glyphs = @{ Critical = '&#10005;'; Warning = '&#9650;'; Info = '&#9675;'; Pass = '&#10003;' }
        $sevSpan = { param([string]$sev) '<span class="sev {0}"><span class="glyph">{1}</span>{2}</span>' -f $sev.ToLowerInvariant(), $glyphs[$sev], (& $encode $sev) }

        $severityOrder = @{ 'Critical' = 0; 'Warning' = 1; 'Info' = 2; 'Pass' = 3 }
        $counts = @{ 'Critical' = 0; 'Warning' = 0; 'Info' = 0; 'Pass' = 0 }
        foreach ($f in $all) { $counts[$f.Severity]++ }

        $verdict = 'Healthy'
        $verdictClass = 'pass'
        if ($counts['Critical'] -gt 0) { $verdict = 'Critical issues found'; $verdictClass = 'critical' }
        elseif ($counts['Warning'] -gt 0) { $verdict = 'Warnings found'; $verdictClass = 'warning' }

        $sections = New-Object System.Text.StringBuilder
        $categories = @($all | Group-Object Category | Sort-Object Name)
        foreach ($category in $categories) {
            $findingLabel = 'finding'
            if ($category.Group.Count -ne 1) { $findingLabel = 'findings' }
            $null = $sections.AppendLine(('<h2>{0}<span class="count">{1} {2}</span></h2>' -f (& $encode $category.Name), $category.Group.Count, $findingLabel))
            $null = $sections.AppendLine('<table><thead><tr><th>Severity</th><th>Check</th><th>Target</th><th>Details</th></tr></thead><tbody>')
            $ordered = $category.Group | Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Check
            foreach ($f in $ordered) {
                # Long curated meanings collapse to their first ~240 chars; the
                # full text stays one click away (plain <details>, no script).
                $messageText = [string]$f.Message
                if ($messageText.Length -gt 280) {
                    $details = '<details class="msg"><summary>{0}...</summary><div class="msgfull">{1}</div></details>' -f (& $encode $messageText.Substring(0, 240)), (& $encode $messageText)
                }
                else {
                    $details = '<div class="msg">{0}</div>' -f (& $encode $messageText)
                }
                if ($f.Evidence) { $details += '<div class="evidence">{0}</div>' -f (& $encode $f.Evidence) }
                if ($f.Recommendation) { $details += '<div class="fix"><b>Fix:</b> {0}</div>' -f (& $encode $f.Recommendation) }
                if ($f.HelpUri) { $details += '<div class="link"><a href="{0}">Documentation</a></div>' -f (& $encode $f.HelpUri) }
                $null = $sections.AppendLine(('<tr class="{0}"><td class="sevcell">{1}</td><td class="check">{2}</td><td class="target">{3}</td><td>{4}</td></tr>' -f `
                            $f.Severity.ToLowerInvariant(), (& $sevSpan $f.Severity), (& $encode $f.Check), (& $encode $f.Target), $details))
            }
            $null = $sections.AppendLine('</tbody></table>')
        }

        $moduleVersion = '0.0.0'
        $manifest = Get-Module -Name FSLogixDoctor
        if ($manifest) { $moduleVersion = [string]$manifest.Version }

        # Per-host status chips: worst severity per host, at a glance.
        $hostChipsHtml = ''
        if ($hostCount -gt 1) {
            $chips = New-Object System.Text.StringBuilder
            foreach ($hostName in $hostNames) {
                $worstIndex = 3
                foreach ($f in $all) {
                    if ((([string]$f.Target) -split ',\s*') -contains $hostName -and $severityOrder[$f.Severity] -lt $worstIndex) {
                        $worstIndex = $severityOrder[$f.Severity]
                    }
                }
                $chipClass = @('critical', 'warning', 'info', 'pass')[$worstIndex]
                $chipGlyph = $glyphs[@('Critical', 'Warning', 'Info', 'Pass')[$worstIndex]]
                $null = $chips.Append(('<span class="hostchip"><span class="sev {0}"><span class="glyph">{1}</span></span>{2}</span>' -f $chipClass, $chipGlyph, (& $encode $hostName)))
            }
            $hostChipsHtml = ('<div class="hosts">{0}</div>' -f $chips.ToString())
        }

        # Action items: everything that actually needs a human, in one block -
        # Critical and Warning findings must not drown between Info rows.
        $actionSection = ''
        $actionable = @($all | Where-Object { $_.Severity -in @('Critical', 'Warning') } |
                Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Category, Check)
        if ($actionable.Count -gt 0) {
            $actions = New-Object System.Text.StringBuilder
            $null = $actions.AppendLine(('<h2>Action items<span class="count">{0}</span></h2>' -f $actionable.Count))
            $null = $actions.AppendLine('<table><thead><tr><th>Severity</th><th>Check</th><th>Target</th><th>Action</th></tr></thead><tbody>')
            foreach ($f in $actionable) {
                $action = [string]$f.Recommendation
                if (-not $action) { $action = [string]$f.Message }
                if ($action.Length -gt 220) { $action = $action.Substring(0, 220) + '...' }
                $null = $actions.AppendLine(('<tr class="{0}"><td class="sevcell">{1}</td><td class="check">{2}</td><td class="target">{3}</td><td>{4}</td></tr>' -f `
                            $f.Severity.ToLowerInvariant(), (& $sevSpan $f.Severity), (& $encode $f.Check), (& $encode $f.Target), (& $encode $action)))
            }
            $null = $actions.AppendLine('</tbody></table>')
            $actionSection = $actions.ToString()
        }

        $lookbackSegment = ''
        if ($LookbackHours -gt 0) { $lookbackSegment = (' &middot; last {0}h window' -f $LookbackHours) }

        $verdictGlyph = @{ pass = $glyphs['Pass']; warning = $glyphs['Warning']; critical = $glyphs['Critical'] }[$verdictClass]
        $actionLabel = 'action item'
        if ($actionable.Count -ne 1) { $actionLabel = 'action items' }
        $verdictSub = ('{0} {1} &middot; {2} &middot; {3} findings total' -f $actionable.Count, $actionLabel, $hostLabel, $all.Count)
        # When run history is active, the findings carry a ChangeStatus - put
        # the diff verdict where the eye lands first.
        $changeAware = @($all | Where-Object { $null -ne $_.PSObject.Properties['ChangeStatus'] -and $_.ChangeStatus })
        if ($changeAware.Count -gt 0) {
            $newCount = @($changeAware | Where-Object { $_.ChangeStatus -eq 'New' -and $_.Severity -in @('Critical', 'Warning') }).Count
            $resolvedCount = @($changeAware | Where-Object ChangeStatus -eq 'Resolved').Count
            $verdictSub += (' &middot; since last run: {0} new, {1} resolved' -f $newCount, $resolvedCount)
        }

        # Summary tiles: only non-zero Critical/Warning tiles carry a color
        # accent; a zero renders muted so nothing shouts about a non-problem.
        $tileLabels = @{ Critical = 'Critical'; Warning = 'Warnings'; Info = 'Info'; Pass = 'Passed' }
        $tilesHtml = New-Object System.Text.StringBuilder
        foreach ($sevName in @('Critical', 'Warning', 'Info', 'Pass')) {
            $stateClass = ''
            if ($counts[$sevName] -eq 0) { $stateClass = ' zero' }
            elseif ($sevName -in @('Critical', 'Warning')) { $stateClass = ' hot' }
            $null = $tilesHtml.AppendLine(('    <div class="tile {0}{1}"><div class="num">{2}</div><div class="label"><span class="sev {0}"><span class="glyph">{3}</span></span>{4}</div></div>' -f `
                        $sevName.ToLowerInvariant(), $stateClass, $counts[$sevName], $glyphs[$sevName], $tileLabels[$sevName]))
        }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $encode $Title)</title>
<style>
  :root {
    color-scheme: light dark;
    --page: #f0efeb; --surface: #ffffff; --thead: #f7f6f3;
    --header-bg: #1a1a19; --header-ink: #ffffff; --header-ink2: #c3c2b7;
    --ink: #0b0b0b; --ink-2: #52514e; --muted: #898781;
    --hairline: #e1e0d9; --ring: rgba(11,11,11,0.12);
    --card-shadow: 0 1px 2px rgba(11,11,11,0.05);
    --critical: #d03b3b; --warning: #fab219; --good: #0ca30c; --info: #898781;
    --link: #256abf;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --page: #0d0d0d; --surface: #1a1a19; --thead: #201f1e;
      --ink: #ffffff; --ink-2: #c3c2b7;
      --hairline: #2c2c2a; --ring: rgba(255,255,255,0.10);
      --card-shadow: none;
      --link: #6da7ec;
    }
  }
  * { box-sizing: border-box; }
  body { font-family: system-ui, -apple-system, 'Segoe UI', sans-serif; margin: 0; background: var(--page); color: var(--ink); }
  header { background: var(--header-bg); border-bottom: 1px solid var(--hairline); }
  header .inner { max-width: 1100px; margin: 0 auto; padding: 24px 32px 20px; }
  header h1 { margin: 0 0 6px; font-size: 20px; font-weight: 650; letter-spacing: -0.01em; color: var(--header-ink); }
  header .meta { color: var(--header-ink2); font-size: 13px; }
  main { max-width: 1100px; margin: 0 auto; padding: 22px 32px 48px; }
  .verdict { display: flex; align-items: baseline; gap: 10px; margin: 4px 0 14px; flex-wrap: wrap; }
  .verdict .headline { font-size: 16px; font-weight: 650; }
  .verdict .sub { color: var(--muted); font-size: 13px; }
  .sev { display: inline-flex; align-items: center; gap: 6px; font-weight: 600; white-space: nowrap; }
  .glyph { font-size: 11px; line-height: 1; }
  .sev.critical .glyph { color: var(--critical); }
  .sev.warning .glyph { color: var(--warning); }
  .sev.info .glyph { color: var(--info); }
  .sev.pass .glyph { color: var(--good); }
  .hosts { display: flex; gap: 8px; flex-wrap: wrap; margin: 0 0 16px; }
  .hostchip { display: inline-flex; align-items: center; gap: 7px; padding: 5px 12px; border-radius: 999px;
              background: var(--surface); border: 1px solid var(--ring); box-shadow: var(--card-shadow);
              font-size: 13px; font-weight: 600; color: var(--ink-2); }
  .tiles { display: flex; gap: 12px; flex-wrap: wrap; margin: 0 0 6px; }
  .tile { flex: 1 1 130px; background: var(--surface); border: 1px solid var(--ring); border-radius: 10px;
          padding: 14px 16px 12px; box-shadow: var(--card-shadow); }
  .tile .num { font-size: 30px; font-weight: 650; line-height: 1.1; }
  .tile .label { margin-top: 2px; font-size: 11px; text-transform: uppercase; letter-spacing: .07em; color: var(--muted);
                 display: flex; align-items: center; gap: 6px; }
  .tile.zero .num { color: var(--muted); font-weight: 600; }
  .tile.critical.hot { border-left: 3px solid var(--critical); }
  .tile.warning.hot { border-left: 3px solid var(--warning); }
  h2 { margin: 30px 0 10px; font-size: 15px; font-weight: 650; letter-spacing: -0.005em; }
  h2 .count { color: var(--muted); font-weight: 500; font-size: 13px; margin-left: 6px; }
  table { width: 100%; border-collapse: collapse; background: var(--surface); border: 1px solid var(--ring);
          border-radius: 10px; overflow: hidden; box-shadow: var(--card-shadow); }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .07em; color: var(--muted);
       padding: 10px 14px 8px; border-bottom: 1px solid var(--hairline); font-weight: 600; background: var(--thead); }
  td { padding: 11px 14px; border-bottom: 1px solid var(--hairline); vertical-align: top; font-size: 13.5px; }
  tr:last-child td { border-bottom: none; }
  tr.critical td:first-child { box-shadow: inset 3px 0 0 var(--critical); }
  tr.warning td:first-child { box-shadow: inset 3px 0 0 var(--warning); }
  td.sevcell { white-space: nowrap; width: 1%; }
  td.sevcell .sev { font-size: 12.5px; color: var(--ink-2); }
  td.check { font-weight: 600; width: 16%; }
  td.target { color: var(--muted); font-size: 12.5px; width: 17%; }
  .msg { margin-bottom: 5px; line-height: 1.45; }
  .evidence { color: var(--muted); font-size: 12.5px; margin-bottom: 5px; line-height: 1.45; }
  .fix { font-size: 13px; color: var(--ink-2); line-height: 1.45; }
  .fix b { font-weight: 650; }
  .link { font-size: 12.5px; margin-top: 3px; } .link a { color: var(--link); }
  details.msg summary { cursor: pointer; line-height: 1.45; color: var(--ink); }
  details.msg summary::marker { color: var(--muted); }
  details.msg .msgfull { margin: 8px 0 4px; padding-left: 10px; border-left: 2px solid var(--hairline); line-height: 1.5; }
  tr.pass .msg, tr.info .msg { color: var(--ink-2); }
  footer { max-width: 1100px; margin: 0 auto; text-align: center; color: var(--muted); font-size: 12px; padding: 18px 32px 26px; }
  footer a { color: var(--muted); }
</style>
</head>
<body>
<header>
  <div class="inner">
    <h1>$(& $encode $Title)</h1>
    <div class="meta">Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by FSLogixDoctor v$moduleVersion &middot; $hostLabel$lookbackSegment &middot; read-only diagnostics &middot; no telemetry</div>
  </div>
</header>
<main>
  <div class="verdict">
    <span class="sev $verdictClass headline"><span class="glyph">$verdictGlyph</span>$(& $encode $verdict)</span>
    <span class="sub">$verdictSub</span>
  </div>
$hostChipsHtml
  <div class="tiles">
$($tilesHtml.ToString())  </div>
$actionSection
$($sections.ToString())
</main>
<footer>FSLogixDoctor &middot; <a href="https://github.com/xGreeny/fslogix-doctor">github.com/xGreeny/fslogix-doctor</a></footer>
</body>
</html>
"@

        # Resolve via the provider so relative paths work even when the caller
        # sits on a registry drive (realistic while poking HKLM:\SOFTWARE\FSLogix).
        $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        [System.IO.File]::WriteAllText($resolvedPath, $html, (New-Object System.Text.UTF8Encoding($false)))
        Get-Item -LiteralPath $resolvedPath
    }
}
