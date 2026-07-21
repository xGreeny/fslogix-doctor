function Resolve-FslProfileStorePath {
    <#
    .SYNOPSIS
        Finds the profile store path(s) automatically: the local VHDLocations
        registry value first, and in fleet mode the first reachable remote
        host's VHDLocations as fallback (the coordinating admin box usually has
        no FSLogix installed).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]]$ComputerName = @()
    )

    $paths = @()
    try {
        $profilesKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction Stop
        $paths = @(ConvertTo-FslLocationList -Value $profilesKey.VHDLocations)
    }
    catch { $paths = @() }

    if ($paths.Count -eq 0) {
        foreach ($computer in @($ComputerName | Where-Object { $_ -and $_ -notin @($env:COMPUTERNAME, 'localhost', '.') })) {
            try {
                $remoteLocations = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
                    (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue).VHDLocations
                }
                $paths = @(ConvertTo-FslLocationList -Value $remoteLocations)
                if ($paths.Count -gt 0) { break }
            }
            catch { continue }
        }
    }

    $paths
}
