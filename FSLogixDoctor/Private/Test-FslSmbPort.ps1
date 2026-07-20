function Test-FslSmbPort {
    <#
    .SYNOPSIS
        Tests whether TCP 445 answers on a host, with a short timeout. Separates
        'network path down' from 'share denies the probing user' - a share that
        denies THIS account still answers on the SMB port.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [ValidateRange(200, 30000)]
        [int]$TimeoutMs = 3000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, 445, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}
