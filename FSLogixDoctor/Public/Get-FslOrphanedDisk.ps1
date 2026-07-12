function Get-FslOrphanedDisk {
    <#
    .SYNOPSIS
        Finds profile container disks whose owner no longer exists (or is disabled)
        - the gigabytes you can reclaim from a profile share.
    .DESCRIPTION
        Takes the output of Get-FslProfileReport (or scans a share itself) and checks
        each disk's SID against the identity infrastructure:

        - Without extra modules, the SID is translated via the OS. A SID that no
          longer translates means the account was deleted: state 'Orphaned'.
        - When the ActiveDirectory module is available, disabled accounts are also
          detected: state 'Disabled'.

        The function never deletes anything. Pipe the output to a report first;
        removal stays a deliberate human decision.
    .PARAMETER InputObject
        FSLogixDoctor.ProfileDisk objects from Get-FslProfileReport.
    .PARAMETER Path
        Alternatively, a profile share path to scan directly.
    .PARAMETER KnownUser
        Offline mode: a list of valid usernames. Disks whose user is not in the list
        are flagged 'Orphaned' without touching AD - useful for testing and for
        air-gapped analysis of a share listing.
    .EXAMPLE
        Get-FslProfileReport -Path \\fs01\fslogix$ | Get-FslOrphanedDisk

        Full pipeline: scan the share, then classify every disk.
    .EXAMPLE
        Get-FslOrphanedDisk -Path \\fs01\fslogix$ | Where-Object State -ne 'OK' |
            Measure-Object SizeGB -Sum

        How many GB the share could reclaim.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Pipeline', Mandatory, ValueFromPipeline)]
        [PSTypeName('FSLogixDoctor.ProfileDisk')]
        [pscustomobject]$InputObject,

        [Parameter(ParameterSetName = 'Path', Mandatory)]
        [string]$Path,

        [string[]]$KnownUser
    )

    begin {
        $adAvailable = $null -ne (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)
        $useKnownList = $PSBoundParameters.ContainsKey('KnownUser')

        $classify = {
            param([pscustomobject]$disk)

            if ($null -eq $disk.Disk) { return } # empty folders are reported by Get-FslProfileReport

            $state = 'OK'
            $detail = ''

            if ($useKnownList) {
                if (-not $disk.UserName) {
                    $state = 'Unknown'
                    $detail = 'No username could be derived from the folder name - verify manually before touching this disk.'
                }
                elseif ($KnownUser -contains $disk.UserName) {
                    $state = 'OK'
                    $detail = 'User is in the provided KnownUser list.'
                }
                else {
                    $state = 'Orphaned'
                    $detail = "User '$($disk.UserName)' is not in the provided KnownUser list."
                }
            }
            elseif ($null -eq $disk.Sid) {
                $state = 'Unknown'
                $detail = 'No SID could be derived from the folder name.'
            }
            elseif ($disk.Sid -like 'S-1-12-1-*') {
                # Entra-ID-only (cloud) SIDs resolve exclusively on Entra-joined
                # hosts; a translation failure on a domain-joined file server says
                # nothing about the account, so never call these orphaned here.
                $account = Resolve-FslAccount -Sid $disk.Sid
                if ($account.Exists) {
                    $detail = "Entra ID account '$($account.Account)' resolved on this host."
                }
                else {
                    $state = 'Unknown'
                    $detail = 'Entra ID (cloud) SID - resolvable only from an Entra-joined host. Verify the account in Entra ID before treating this disk as orphaned.'
                }
            }
            else {
                $account = Resolve-FslAccount -Sid $disk.Sid
                if (-not $account.Exists) {
                    $state = 'Orphaned'
                    $detail = "SID '$($disk.Sid)' no longer resolves to an account."
                }
                elseif ($adAvailable -and $disk.Sid -like 'S-1-5-21-*') {
                    try {
                        $adUser = Get-ADUser -Identity $disk.Sid -Properties Enabled -ErrorAction Stop
                        if (-not $adUser.Enabled) {
                            $state = 'Disabled'
                            $detail = "Account '$($account.Account)' exists but is disabled."
                        }
                        else {
                            $detail = "Account '$($account.Account)' exists and is enabled."
                        }
                    }
                    catch {
                        # The SID translated, so the account exists - an AD lookup
                        # miss (local account, other forest) must not degrade that.
                        $detail = "Account '$($account.Account)' exists (AD lookup not possible: $($_.Exception.Message))"
                    }
                }
                else {
                    $detail = "Account '$($account.Account)' exists (enable/disable state needs the ActiveDirectory module)."
                }
            }

            $reclaimable = 0
            if ($state -in @('Orphaned', 'Disabled')) { $reclaimable = $disk.SizeGB }

            [pscustomobject]@{
                PSTypeName    = 'FSLogixDoctor.OrphanCandidate'
                Disk          = $disk.Disk
                Folder        = $disk.Folder
                UserName      = $disk.UserName
                Sid           = $disk.Sid
                SizeGB        = $disk.SizeGB
                LastModified  = $disk.LastModified
                State         = $state
                Detail        = $detail
                ReclaimableGB = $reclaimable
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            & $classify $InputObject
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($disk in (Get-FslProfileReport -Path $Path)) {
                & $classify $disk
            }
        }
    }
}
