function Get-FslLockedProfile {
    <#
    .SYNOPSIS
        Finds FSLogix container disks that are currently held open over SMB - the
        classic cause of 'profile is already in use' at login time.
    .DESCRIPTION
        Enumerates open SMB handles on the file server hosting the profile share and
        returns every open VHD/VHDX, including which user and client machine holds
        the handle. A handle from a session host the user is no longer logged on to
        is a stale lock; releasing it (Close-SmbOpenFile) is deliberately left as an
        explicit human decision.

        Must run on the file server itself or against it via -CimSession.
    .PARAMETER CimSession
        A CIM session to the file server hosting the profile share.
    .PARAMETER PathFilter
        Only return handles whose path matches this wildcard pattern,
        e.g. '*fslogix*'. Defaults to all VHD/VHDX handles.
    .EXAMPLE
        Get-FslLockedProfile

        Run directly on the file server: all currently open container disks.
    .EXAMPLE
        Get-FslLockedProfile -CimSession (New-CimSession fs01) -PathFilter '*fslogix*'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Microsoft.Management.Infrastructure.CimSession]$CimSession,

        [string]$PathFilter = '*'
    )

    if (-not (Get-Command -Name 'Get-SmbOpenFile' -ErrorAction SilentlyContinue)) {
        throw 'Get-SmbOpenFile is not available on this system. Run this function on the file server hosting the profile share (or pass -CimSession).'
    }

    $smbParams = @{ ErrorAction = 'Stop' }
    if ($CimSession) { $smbParams['CimSession'] = $CimSession }

    $openFiles = @(Get-SmbOpenFile @smbParams | Where-Object {
            ($_.Path -like '*.vhd' -or $_.Path -like '*.vhdx' -or $_.Path -like '*.VHD' -or $_.Path -like '*.VHDX') -and
            $_.Path -like $PathFilter
        })

    foreach ($file in $openFiles) {
        [pscustomobject]@{
            PSTypeName         = 'FSLogixDoctor.LockedProfile'
            Path               = $file.Path
            HeldByUser         = $file.ClientUserName
            HeldByComputer     = $file.ClientComputerName
            SessionId          = $file.SessionId
            FileId             = $file.FileId
            Locks              = $file.Locks
            ReleaseInstruction = ('Verify the user has no active session on {0}, then: Close-SmbOpenFile -FileId {1} -Confirm' -f $file.ClientComputerName, $file.FileId)
        }
    }

    if ($openFiles.Count -eq 0) {
        Write-Verbose 'No open VHD/VHDX handles found.'
    }
}
