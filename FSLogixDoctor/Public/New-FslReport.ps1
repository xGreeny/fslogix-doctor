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
            $null = $sections.AppendLine(('<h2>{0}</h2>' -f (& $encode $category.Name)))
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
                if ($f.Recommendation) { $details += '<div class="fix">Fix: {0}</div>' -f (& $encode $f.Recommendation) }
                if ($f.HelpUri) { $details += '<div class="link"><a href="{0}">Documentation</a></div>' -f (& $encode $f.HelpUri) }
                $null = $sections.AppendLine(('<tr class="{0}"><td><span class="badge {0}">{1}</span></td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f `
                            $f.Severity.ToLowerInvariant(), (& $encode $f.Severity), (& $encode $f.Check), (& $encode $f.Target), $details))
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
                $null = $chips.Append(('<span class="hostchip {0}">{1}</span>' -f $chipClass, (& $encode $hostName)))
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
            $null = $actions.AppendLine('<h2>Action items</h2>')
            $null = $actions.AppendLine('<table><thead><tr><th>Severity</th><th>Check</th><th>Target</th><th>Action</th></tr></thead><tbody>')
            foreach ($f in $actionable) {
                $action = [string]$f.Recommendation
                if (-not $action) { $action = [string]$f.Message }
                if ($action.Length -gt 220) { $action = $action.Substring(0, 220) + '...' }
                $null = $actions.AppendLine(('<tr class="{0}"><td><span class="badge {0}">{1}</span></td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f `
                            $f.Severity.ToLowerInvariant(), (& $encode $f.Severity), (& $encode $f.Check), (& $encode $f.Target), (& $encode $action)))
            }
            $null = $actions.AppendLine('</tbody></table>')
            $actionSection = $actions.ToString()
        }

        $lookbackSegment = ''
        if ($LookbackHours -gt 0) { $lookbackSegment = (' &middot; last {0}h window' -f $LookbackHours) }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $encode $Title)</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; margin: 0; background: #f4f6f8; color: #1f2933; }
  header { background: #102a43; color: #fff; padding: 24px 32px; }
  header h1 { margin: 0 0 4px 0; font-size: 22px; }
  header .meta { color: #9fb3c8; font-size: 13px; }
  main { max-width: 1100px; margin: 0 auto; padding: 24px 32px 48px; }
  .tiles { display: flex; gap: 12px; flex-wrap: wrap; margin: 0 0 8px; }
  .tile { flex: 1 1 120px; background: #fff; border-radius: 8px; padding: 14px 18px; box-shadow: 0 1px 3px rgba(16,42,67,.12); border-top: 4px solid #829ab1; }
  .tile .num { font-size: 28px; font-weight: 600; }
  .tile .label { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: #627d98; }
  .tile.critical { border-top-color: #c62828; } .tile.critical .num { color: #c62828; }
  .tile.warning { border-top-color: #ef6c00; } .tile.warning .num { color: #ef6c00; }
  .tile.info { border-top-color: #0277bd; } .tile.info .num { color: #0277bd; }
  .tile.pass { border-top-color: #2e7d32; } .tile.pass .num { color: #2e7d32; }
  .verdict { display: inline-block; margin: 12px 0 4px; padding: 6px 14px; border-radius: 999px; font-weight: 600; font-size: 14px; }
  .verdict.pass { background: #e8f5e9; color: #2e7d32; }
  .verdict.warning { background: #fff3e0; color: #ef6c00; }
  .verdict.critical { background: #ffebee; color: #c62828; }
  .hosts { margin: 6px 0 12px; display: flex; gap: 8px; flex-wrap: wrap; }
  .hostchip { display: inline-block; padding: 4px 12px; border-radius: 999px; font-size: 13px; font-weight: 600; }
  .hostchip.critical { background: #ffebee; color: #c62828; }
  .hostchip.warning { background: #fff3e0; color: #ef6c00; }
  .hostchip.info { background: #e1f5fe; color: #0277bd; }
  .hostchip.pass { background: #e8f5e9; color: #2e7d32; }
  details.msg summary { cursor: pointer; margin-bottom: 4px; }
  details.msg .msgfull { margin: 6px 0 4px; }
  h2 { margin: 28px 0 10px; font-size: 17px; color: #102a43; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(16,42,67,.12); }
  th { text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: .05em; color: #627d98; padding: 10px 14px; border-bottom: 2px solid #d9e2ec; }
  td { padding: 10px 14px; border-bottom: 1px solid #e4ebf1; vertical-align: top; font-size: 14px; }
  tr:last-child td { border-bottom: none; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }
  .badge.critical { background: #ffebee; color: #c62828; }
  .badge.warning { background: #fff3e0; color: #ef6c00; }
  .badge.info { background: #e1f5fe; color: #0277bd; }
  .badge.pass { background: #e8f5e9; color: #2e7d32; }
  .msg { margin-bottom: 4px; }
  .evidence { color: #627d98; font-size: 13px; margin-bottom: 4px; }
  .fix { font-size: 13px; color: #334e68; }
  .link { font-size: 13px; } .link a { color: #0277bd; }
  footer { text-align: center; color: #829ab1; font-size: 12px; padding: 16px; }
</style>
</head>
<body>
<header>
  <h1>$(& $encode $Title)</h1>
  <div class="meta">Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by FSLogixDoctor v$moduleVersion &middot; $hostLabel$lookbackSegment &middot; read-only diagnostics &middot; no telemetry</div>
</header>
<main>
  <div class="verdict $verdictClass">$(& $encode $verdict)</div>
$hostChipsHtml
  <div class="tiles">
    <div class="tile critical"><div class="num">$($counts['Critical'])</div><div class="label">Critical</div></div>
    <div class="tile warning"><div class="num">$($counts['Warning'])</div><div class="label">Warnings</div></div>
    <div class="tile info"><div class="num">$($counts['Info'])</div><div class="label">Info</div></div>
    <div class="tile pass"><div class="num">$($counts['Pass'])</div><div class="label">Passed</div></div>
  </div>
$actionSection
$($sections.ToString())
</main>
<footer>FSLogixDoctor &middot; https://github.com/xGreeny/fslogix-doctor</footer>
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
