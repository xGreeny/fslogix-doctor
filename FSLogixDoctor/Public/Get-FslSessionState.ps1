function Get-FslSessionState {
    <#
    .SYNOPSIS
        Reads the per-session profile state FSLogix records in the registry and
        translates Status/Reason/Error into plain English.
    .DESCRIPTION
        FSLogix writes three values per user session - Status, Reason and Error -
        to HKLM:\SOFTWARE\FSLogix\Profiles\Sessions\<SID> (and, for ODFC containers,
        HKLM:\SOFTWARE\Policies\FSLogix\ODFC\Sessions\<SID>). This function reads
        each session key, resolves the SID to an account and translates the values
        using the curated FSLogixDoctor database - the fastest way to answer
        'why did this user get a temp profile?'.

        Semantics per Microsoft: Status 0/100/200/300 are normal states; Status 1-28
        are error states. Reason clarifies normal states only (e.g. Reason 3 = a
        local profile blocked the attach). Error is a standard Windows system error
        code from the failing API call.
    .PARAMETER SessionsKeyPath
        Registry path(s) holding per-session state. Defaults to the Profile
        container path; add the ODFC path via -IncludeOdfc or override for testing.
    .PARAMETER IncludeOdfc
        Also read ODFC container session state
        (HKLM:\SOFTWARE\Policies\FSLogix\ODFC\Sessions).
    .EXAMPLE
        Get-FslSessionState

        Shows every session FSLogix knows about on this host, translated.
    .EXAMPLE
        Get-FslSessionState | Where-Object Healthy -eq $false
    .LINK
        https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$SessionsKeyPath = 'HKLM:\SOFTWARE\FSLogix\Profiles\Sessions',

        [switch]$IncludeOdfc
    )

    $keyPaths = @(
        [pscustomobject]@{ Container = 'Profile'; Path = $SessionsKeyPath }
    )
    if ($IncludeOdfc) {
        $keyPaths += [pscustomobject]@{ Container = 'ODFC'; Path = 'HKLM:\SOFTWARE\Policies\FSLogix\ODFC\Sessions' }
    }

    $codes = Get-FslDataTable -Name SessionCodes

    $translate = {
        param([string]$prefix, [object]$value)
        if ($null -eq $value) { return $null }
        $key = '{0}:{1}' -f $prefix, $value
        if ($codes.ContainsKey($key)) { return $codes[$key].Meaning }
        "Undocumented $prefix value '$value'"
    }

    # Per Microsoft: 0=success, 100=waiting on profile service, 200=setup in
    # progress, 300=already attached (differencing disks).
    $normalStatuses = @(0, 100, 200, 300)
    # Reasons that mean 'the container did NOT attach because something is wrong'
    # (3=local profile exists, 7=temp profile, 9=profile load failed), as opposed
    # to deliberate exclusions (1/2/4/8).
    $problemReasons = @(3, 7, 9)

    $foundAny = $false
    foreach ($keyPath in $keyPaths) {
        if (-not (Test-Path -LiteralPath $keyPath.Path)) {
            Write-Verbose "Session state key '$($keyPath.Path)' not found."
            continue
        }
        $foundAny = $true

        foreach ($sessionKey in (Get-ChildItem -LiteralPath $keyPath.Path -ErrorAction SilentlyContinue)) {
            $sid = Split-Path -Leaf $sessionKey.PSPath
            $values = Get-ItemProperty -LiteralPath $sessionKey.PSPath -ErrorAction SilentlyContinue
            $account = Resolve-FslAccount -Sid $sid

            $status = $values.Status
            $reason = $values.Reason
            # The documented value name is 'Error'; some log lines say 'ErrorCode',
            # so read that defensively as fallback.
            $errorValue = $values.Error
            if ($null -eq $errorValue) { $errorValue = $values.ErrorCode }

            $errorText = $null
            if ($null -ne $errorValue -and 0 -ne $errorValue) {
                $decoded = Get-FslErrorCode -Code $errorValue
                if ($decoded) { $errorText = $decoded.Meaning }
            }

            $statusIsNormal = ($normalStatuses -contains $status)
            # Status 300 = 'already attached' (differencing-disk setups) counts as attached.
            $attached = (($status -eq 0 -or $status -eq 300) -and $reason -eq 0)
            $reasonIsClean = -not ($problemReasons -contains $reason)
            $errorIsClean = (($null -eq $errorValue) -or ($errorValue -eq 0))
            $healthy = ($statusIsNormal -and $reasonIsClean -and $errorIsClean)

            [pscustomobject]@{
                PSTypeName = 'FSLogixDoctor.SessionState'
                Container  = $keyPath.Container
                Sid        = $sid
                Account    = $account.Account
                Status     = $status
                StatusText = & $translate 'Status' $status
                Reason     = $reason
                ReasonText = & $translate 'Reason' $reason
                Error      = $errorValue
                ErrorText  = $errorText
                Attached   = $attached
                Healthy    = $healthy
            }
        }
    }

    if (-not $foundAny) {
        Write-Warning "No FSLogix session state found. FSLogix is not installed, has never attached a profile on this host, or you lack permissions."
    }
}
