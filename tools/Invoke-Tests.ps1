<#
.SYNOPSIS
    Runs the FSLogixDoctor Pester test suite. Used locally and in CI.
#>
[CmdletBinding()]
param(
    [string]$TestPath = (Join-Path $PSScriptRoot '..\tests'),
    [switch]$CI
)

$ErrorActionPreference = 'Stop'

# The suite is written for Pester 5; pin below 6 for deterministic behavior.
$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.4.0' -and $_.Version -lt [version]'6.0.0' } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Host 'Installing Pester 5...'
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Install-Module -Name Pester -MinimumVersion 5.4.0 -MaximumVersion 5.99.99 -Force -Scope CurrentUser -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.4.0 -MaximumVersion 5.99.99 -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = (Resolve-Path $TestPath).Path
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'

if ($CI) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'TestResults.xml'
}

Invoke-Pester -Configuration $configuration
