@{
    # Curated events from the Windows logs AROUND FSLogix - the places the
    # module's own recommendations used to send the human ('check the User
    # Profile Service event log', 'check the System log for disk errors').
    # Deliberately a short, curated list, not a log dump: every entry names
    # why it matters ON AN FSLOGIX HOST and what to do about it.
    #
    # ProviderPattern is matched (-like) against ProviderName because the same
    # event ID exists under multiple providers in Application/System.
    Events = @(
        @{
            Key             = 'ProfSvc:1511'
            Label           = 'User Profile Service'
            LogName         = 'Application'
            ProviderPattern = '*User Profiles Service*'
            Id              = 1511
            Severity        = 'Critical'
            Meaning  = 'Windows logged a user on with a TEMPORARY profile (''Windows cannot find the local profile...''). Everything the user saves in it is lost at sign-out. On an FSLogix host this is the visible end of a failed container attach when PreventLoginWithTempProfile=0 masks the failure.'
            Causes   = @('FSLogix container attach failed and PreventLoginWithTempProfile=0 let the logon continue into a temp profile', 'Genuine local profile corruption unrelated to FSLogix (registry hive unloadable)')
            Fixes    = @('Correlate the timestamp with Get-FslSessionState (Reason=7) and Get-FslLogError to find the attach failure behind it', 'Set PreventLoginWithFailure=1 and PreventLoginWithTempProfile=1 so failures surface instead of costing user data', 'Warn the affected user immediately: work saved in the temp profile disappears at sign-out')
            Source   = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/troubleshoot-temporary-user-profiles'
            Verified = $true
        }
        @{
            Key             = 'ProfSvc:1515'
            Label           = 'User Profile Service'
            LogName         = 'Application'
            ProviderPattern = '*User Profiles Service*'
            Id              = 1515
            Severity        = 'Warning'
            Meaning  = 'Windows backed up a user profile and will try the backup at the next logon - the recovery side of the temp-profile chain (usually paired with 1511).'
            Causes   = @('Profile could not be loaded at logon; Windows preserved it as <profile>.bak', 'Repeated occurrences: the underlying load failure is chronic')
            Fixes    = @('Treat together with event 1511: find and fix the load/attach failure', 'Check HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList for .bak SID entries left behind')
            Source   = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/troubleshoot-temporary-user-profiles'
            Verified = $true
        }
        @{
            Key             = 'ProfSvc:1530'
            Label           = 'User Profile Service'
            LogName         = 'Application'
            ProviderPattern = '*User Profiles Service*'
            Id              = 1530
            Severity        = 'Warning'
            Meaning  = 'Registry hive handles were still open when the user signed out (''Windows detected your registry file is still in use...''). On an FSLogix host this delays or breaks the container detach - the classic source of ''profile in use'' at the next logon.'
            Causes   = @('A service, agent or antivirus holds HKCU handles past logoff (the event lists the holder)', 'Abrupt session teardown')
            Fixes    = @('Read the event detail: it names the process holding the handles - exclude or fix that agent', 'Correlate with FSLogix detach/unload errors and locked-container findings at the same time', 'Apply the Microsoft-recommended FSLogix antivirus exclusions')
            Source   = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/event-id-1530-is-logged-user-profile-service'
            Verified = $false
        }
        @{
            Key             = 'ProfSvc:1533'
            Label           = 'User Profile Service'
            LogName         = 'Application'
            ProviderPattern = '*User Profiles Service*'
            Id              = 1533
            Severity        = 'Warning'
            Meaning  = 'Windows could not delete a profile directory. With DeleteLocalProfileWhenVHDShouldApply=1 a leftover local profile that cannot be deleted blocks the container from applying (session Reason=3).'
            Causes   = @('Files in the local profile held open by a process during deletion', 'NTFS permission damage in the leftover profile directory')
            Fixes    = @('Identify and close the holder, then remove the leftover local profile directory during maintenance', 'Correlate with FSLogix session Reason=3 (local profile exists) findings')
            Source   = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/troubleshoot-temporary-user-profiles'
            Verified = $false
        }
        @{
            Key             = 'Ntfs:55'
            Label           = 'NTFS'
            LogName         = 'System'
            ProviderPattern = '*Ntfs*'
            Id              = 55
            Severity        = 'Warning'
            Meaning  = 'NTFS reported a corrupt file system structure and asks for chkdsk. On an FSLogix host this frequently refers to the volume INSIDE a mounted profile container - the independent confirmation of compaction failures like ErrCode 42008 / event 33.'
            Causes   = @('Filesystem damage inside a user''s VHD(X) after an abrupt detach (host crash, hard session teardown)', 'Damage on a host-local volume (check the volume name in the event text)')
            Fixes    = @('Read the event text to identify the volume; for a container volume, mount the VHDX with the user signed out and run chkdsk /f', 'Cross-check with the 0x0000A418 / event 33 findings of this report - same container means confirmed corruption', 'If it recurs across containers, investigate storage-level causes')
            Source   = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/event-id-55-when-chkdsk-runs'
            Verified = $true
        }
        @{
            Key             = 'Disk:7'
            Label           = 'Disk'
            LogName         = 'System'
            ProviderPattern = 'disk'
            Id              = 7
            Severity        = 'Warning'
            Meaning  = 'The disk driver reported a bad block (''The device ... has a bad block''). Underneath a session host this can silently corrupt profile containers during I/O.'
            Causes   = @('Failing physical disk or storage path under the host', 'For virtual hosts: storage-layer faults surfacing through the virtual disk stack')
            Fixes    = @('Check host storage health (SMART, RAID, hypervisor storage alarms)', 'Cross-check container integrity findings (NTFS 55, compaction errors) in the same window')
            Source   = 'https://learn.microsoft.com/en-us/windows/win32/eventlog/event-logging'
            Verified = $false
        }
        @{
            Key             = 'Disk:153'
            Label           = 'Disk'
            LogName         = 'System'
            ProviderPattern = 'disk'
            Id              = 153
            Severity        = 'Info'
            Meaning  = 'An I/O operation was retried (''The IO operation at logical block address ... was retried''). Occasional entries are transient storage latency; clusters of them explain slow logons and container I/O stalls.'
            Causes   = @('Transient storage/SAN latency spikes', 'Sustained storage overload during logon storms')
            Fixes    = @('Ignore occasional entries; investigate storage latency when they cluster around logon windows', 'Correlate timing with slow-logon complaints and FSLogix attach durations')
            Source   = 'https://learn.microsoft.com/en-us/archive/blogs/ntdebugging/interpreting-event-153-errors'
            Verified = $false
        }
    )
}
