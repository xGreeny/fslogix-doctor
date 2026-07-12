function Get-FslInstallInfo {
    <#
    .SYNOPSIS
        Detects whether FSLogix is installed and returns service state and version.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $service = Get-Service -Name 'frxsvc' -ErrorAction SilentlyContinue
    $version = $null

    # ProgramW6432 keeps the path correct even in a 32-bit host process.
    $programFiles = $env:ProgramW6432
    if (-not $programFiles) { $programFiles = $env:ProgramFiles }
    $frxsvcPath = Join-Path $programFiles 'FSLogix\Apps\frxsvc.exe'
    if (Test-Path -LiteralPath $frxsvcPath) {
        try {
            $version = (Get-Item -LiteralPath $frxsvcPath).VersionInfo.FileVersion
        }
        catch {
            Write-Verbose "Could not read frxsvc.exe version: $($_.Exception.Message)"
        }
    }

    $status = $null
    if ($service) { $status = [string]$service.Status }

    [pscustomobject]@{
        Installed     = ($null -ne $service)
        ServiceStatus = $status
        Version       = $version
    }
}
