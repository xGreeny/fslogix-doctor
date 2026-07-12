function Resolve-FslAccount {
    <#
    .SYNOPSIS
        Translates a SID to an account name without requiring the ActiveDirectory module.
    .NOTES
        Translation asks the machine's logon infrastructure (local SAM / domain),
        so a SID whose account was deleted fails to translate. That failure is the
        signal Get-FslOrphanedDisk relies on.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $account = $null
    $exists = $false
    try {
        $sidObject = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        $account = $sidObject.Translate([System.Security.Principal.NTAccount]).Value
        $exists = $true
    }
    catch {
        Write-Verbose "SID '$Sid' did not translate to an account: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Sid     = $Sid
        Account = $account
        Exists  = $exists
    }
}
