# FSLogix per-session Status/Reason codes (HKLM\SOFTWARE\FSLogix\Profiles\Sessions).
# Generated from verified research; regenerate docs with tools/Export-ErrorCodeDoc.ps1.
@{
    'Reason:0' = @{
        Name     = 'REASON_PROFILE_ATTACHED'
        Meaning  = 'The container is attached. With Status 0 this is the fully healthy state.'
        Causes   = @('Normal operation')
        Fixes    = @('No action required')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:1' = @{
        Name     = 'REASON_NOT_IN_WHITE_LIST'
        Meaning  = 'User isn''t a member of the include group (''FSLogix Profile Include List'' / ''FSLogix ODFC Include List''), so FSLogix skipped the session.'
        Causes   = @('User (or their groups) not in the local FSLogix Include List group', 'Include group membership changed or GPO restricting membership')
        Fixes    = @('Add the user (or Domain Users, as appropriate) to the local ''FSLogix Profile Include List'' group', 'Check GPO/Restricted Groups policies that may rewrite local group membership')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:2' = @{
        Name     = 'REASON_IN_BLACK_LIST'
        Meaning  = 'User is a member of the exclude group (''FSLogix Profile Exclude List'' / ''FSLogix ODFC Exclude List''), so FSLogix skipped the session.'
        Causes   = @('User deliberately or accidentally placed in the local FSLogix Exclude List group (directly or via nested group)')
        Fixes    = @('Remove the user from the local ''FSLogix Profile Exclude List'' group if exclusion is unintended (exclude wins over include)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:3' = @{
        Name     = 'REASON_LOCAL_PROFILE_EXISTS'
        Meaning  = 'A local (non-FSLogix) profile for this user already exists on this system; by default FSLogix honors the local profile instead of attaching the container.'
        Causes   = @('User signed in on this host before FSLogix was installed/enabled, leaving a local profile', 'Leftover local profile from a previous failed logoff/cleanup')
        Fixes    = @('Enable DeleteLocalProfileWhenVHDShouldApply so FSLogix deletes the local profile at sign-in and attaches the container (Microsoft warns: review existing local profiles first to limit data-loss exposure)', 'Alternatively remove the local profile manually (Advanced System Settings > User Profiles, or ProfileList cleanup) after preserving needed data')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    'Reason:4' = @{
        Name     = 'REASON_SHORT_SID'
        Meaning  = 'Not an appropriate user type - the account''s SID is a short/well-known SID (local system/service/built-in accounts), which FSLogix doesn''t manage.'
        Causes   = @('Sign-in by local, built-in, or system accounts rather than a normal domain/AAD user')
        Fixes    = @('Expected behavior for system/local accounts; no action needed. If seen for a real user, verify the account type and SID')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:5' = @{
        Name     = 'REASON_UNSET'
        Meaning  = 'Reason initialized to empty state (no reason has been recorded yet).'
        Causes   = @('Transient/initial state before FSLogix records an outcome for the session')
        Fixes    = @('Re-read after logon completes; investigate the Status value and profile log if it never changes')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:6' = @{
        Name     = 'REASON_COMPONENT_NOT_ENABLED'
        Meaning  = 'Component isn''t enabled in the product key (legacy licensing-era code); in practice the Profiles/ODFC feature isn''t enabled.'
        Causes   = @('FSLogix installed but the Profiles or ODFC container feature isn''t enabled (Enabled=0 or missing)', 'Legacy product-key licensing not covering the component (historic versions)')
        Fixes    = @('Set Enabled=1 under HKLM\SOFTWARE\FSLogix\Profiles (or HKLM\SOFTWARE\Policies\FSLogix\ODFC) per the Microsoft configure-profile-containers tutorial')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:7' = @{
        Name     = 'REASON_WINDOWS_TEMP_PROFILE'
        Meaning  = 'The profile in use is a Windows temporary profile (FSLogix did not manage/attach; the user landed in a TEMP profile).'
        Causes   = @('Container in use on another machine (default single-connection behavior) so Windows fell back to a temp profile', 'An earlier attach failure caused Windows to issue a temp profile', 'Stale .bak entries under the ProfileList registry key')
        Fixes    = @('Find and fix the underlying attach failure (Status/Error values, Profile_<user>.log)', 'Consider PreventLoginWithTempProfile to block sign-in instead of allowing temp profiles (evaluate per-organization, per Microsoft guidance)', 'Clean up stale HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\<SID>.bak entries')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    'Reason:8' = @{
        Name     = 'REASON_NOT_WVD_SESSION'
        Meaning  = 'The session isn''t an Azure Virtual Desktop session, so FSLogix skipped it (relevant where FSLogix is configured/entitled to operate only for AVD sessions).'
        Causes   = @('Sign-in over a non-AVD connection (e.g., console/direct RDP) on a host where FSLogix is scoped to AVD sessions')
        Fixes    = @('Confirm the connection type; review FSLogix configuration/entitlement expectations for non-AVD sessions on that host')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Reason:9' = @{
        Name     = 'REASON_FAILED_TO_LOAD_PROFILE'
        Meaning  = 'Profile load failed - FSLogix attempted but could not load the profile.'
        Causes   = @('Any underlying attach/load failure (locks, permissions, storage) - the Status and Error values carry the specifics')
        Fixes    = @('Read the Status (error) code and Error (Windows System Error Code) values under the same Sessions\<SID> key', 'Correlate with Profile_<user>.log entries at the failure timestamp and fix the underlying cause (permissions, locks, path)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:0' = @{
        Name     = 'STATUS_SUCCESS'
        Meaning  = 'Success - the FSLogix operation completed and the container is working for this user (normal status).'
        Causes   = @('Normal operation; profile/ODFC container attached successfully')
        Fixes    = @('No action required. Pair with Reason=0 (container attached) to confirm fully healthy state')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:1' = @{
        Name     = 'ERROR'
        Meaning  = 'Can''t load user''s profile (generic profile load failure).'
        Causes   = @('Container locked/in use by another session (Windows error 33, ''AcquireExclusiveLock'' failure documented by Microsoft)', 'Storage permission or connectivity failure', 'Any unclassified failure during profile load')
        Fixes    = @('Read the companion ''Error'' registry value and C:\ProgramData\FSLogix\Logs\Profile\Profile_<user>.log for the underlying Windows System Error Code', 'Check whether the user has an active session on another host holding the VHDX lock; consider PreventLoginWithTempProfile or the documented multi/concurrent connection options', 'Validate SMB share + NTFS permissions per Microsoft''s ''Configure SMB Storage Permissions'' how-to')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:10' = @{
        Name     = 'ERROR_CLOSE_HANDLE'
        Meaning  = 'Can''t release the virtual disk.'
        Causes   = @('Open handles on the container (processes, filter drivers such as antivirus) preventing release')
        Fixes    = @('Check for processes/AV holding handles on the VHDX; apply Microsoft''s recommended antivirus exclusions', 'Review the Error value for the Windows error code')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:100' = @{
        Name     = 'STATUS_WAITING_FOR_PROFILE_DIR_SET'
        Meaning  = 'Normal: waiting for the Windows Profile Service to determine the user''s profile folder.'
        Causes   = @('Normal transient state during sign-in')
        Fixes    = @('No action if transient; if stuck here, investigate the Windows User Profile Service (ProfSvc) and logon slowness')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:11' = @{
        Name     = 'ERROR_OPEN_VHD'
        Meaning  = 'Can''t open the virtual disk.'
        Causes   = @('File locked by another session or process', 'Insufficient permissions on the VHDX', 'Corrupted container file')
        Fixes    = @('Check for locks (other sessions, backup/AV agents)', 'Validate permissions; test disk integrity (e.g., mount manually / chkdsk inside the container)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:12' = @{
        Name     = 'ERROR_ATTACH_VHD'
        Meaning  = 'Can''t attach to the virtual disk.'
        Causes   = @('Access denied or file locked (Microsoft log examples: ''Attach vhd(x) failed, file is locked'' / ''Failed to attach VHD (Access is denied)'')', 'Profile in use on another computer (single-connection default)')
        Fixes    = @('Sign the user out of other sessions using the same container, or configure multiple/concurrent connections per Microsoft''s concepts article', 'Fix SMB/NTFS permissions; check the Error value (0x00000005 access denied, 0x00000020/33 sharing/lock violations)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    'Status:13' = @{
        Name     = 'ERROR_GET_PHYSICAL_PATH'
        Meaning  = 'Can''t retrieve the virtual disk''s physical information after attach.'
        Causes   = @('Virtual Disk API/service problem after attach')
        Fixes    = @('Check the Error value and profile log; verify Virtual Disk service health; retry logon')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:14' = @{
        Name     = 'ERROR_OPEN_DEVICE'
        Meaning  = 'Can''t open the virtual disk''s volume device.'
        Causes   = @('Filter driver interference (antivirus/security agents) with the mounted volume')
        Fixes    = @('Apply Microsoft''s recommended FSLogix antivirus exclusions', 'Check the Error value for the Windows error code')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:15' = @{
        Name     = 'ERROR_INIT_DISK'
        Meaning  = 'Can''t initialize the virtual disk (first-time disk setup).'
        Causes   = @('Interrupted first-time container creation leaving a partial/invalid VHDX')
        Fixes    = @('Remove/rename the partially created VHDX and let FSLogix recreate it', 'Check storage stability and the Error value')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:16' = @{
        Name     = 'ERROR_GET_VOL_GUID'
        Meaning  = 'Can''t retrieve the virtual disk (volume) identifier.'
        Causes   = @('Volume enumeration failure after attach (mount manager issues)')
        Fixes    = @('Check the Error value and profile log; verify mount manager/Virtual Disk service; retry')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:17' = @{
        Name     = 'ERROR_FORMAT_VOL'
        Meaning  = 'Error while formatting the virtual disk volume (first-time creation).'
        Causes   = @('Formatting of the new container volume failed (storage interruption, filter drivers)')
        Fixes    = @('Delete the failed VHDX and allow re-creation', 'Check AV exclusions and the Error value')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:18' = @{
        Name     = 'ERROR_GET_PROFILE_DIR'
        Meaning  = 'Can''t retrieve the user''s profile directory from Windows.'
        Causes   = @('Windows Profile Service (ProfSvc) did not provide the profile folder', 'Broken ProfileList registry state for the user')
        Fixes    = @('Check HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList for stale/.bak entries for the SID', 'Review User Profile Service event log (Application log, ProfSvc events)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:19' = @{
        Name     = 'ERROR_SET_MOUNT_POINT'
        Meaning  = 'Can''t set up the directory mount point (junction from C:\Users\<user> into the container volume).'
        Causes   = @('Existing conflicting local profile folder or leftover mount point', 'Permissions/handles on the profile path')
        Fixes    = @('Check for a pre-existing local profile folder for the user and stale mount points under C:\Users', 'Review the Error value; consider DeleteLocalProfileWhenVHDShouldApply if a local profile is the conflict (caution: data loss)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:2' = @{
        Name     = 'ERROR_VIRT_DLL'
        Meaning  = 'Virtual disk API isn''t available on this platform.'
        Causes   = @('Unsupported Windows edition/version lacking the Virtual Disk (virtdisk.dll) API')
        Fixes    = @('Verify the OS is on FSLogix''s supported platform list', 'Confirm virtdisk.dll / Virtual Disk service is present and functional')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:20' = @{
        Name     = 'ERROR_REG_IMPORT'
        Meaning  = 'Can''t import registry information (per-user registry data during profile setup).'
        Causes   = @('Failure writing/loading the user''s registry hive or FSLogix registry data')
        Fixes    = @('Check the Error value and profile log; verify the user hive (NTUSER.DAT) inside the container isn''t corrupt')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:200' = @{
        Name     = 'STATUS_IN_PROGRESS'
        Meaning  = 'Normal: FSLogix setup (container attach/profile setup) is in progress.'
        Causes   = @('Normal transient state during sign-in')
        Fixes    = @('No action if it progresses to Status 0; if it persists, review Profile_<user>.log for where setup stalls (storage latency is a common culprit)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:21' = @{
        Name     = 'ERROR_CHK_GRP_MEMBERSHIP'
        Meaning  = 'Can''t retrieve the user''s group membership (needed to evaluate FSLogix include/exclude groups).'
        Causes   = @('Domain controller unreachable during group evaluation', 'Broken local ''FSLogix Profile Include/Exclude List'' groups')
        Fixes    = @('Verify DC connectivity and that the local FSLogix Include/Exclude List groups exist and resolve', 'Check the Error value for the Windows error code')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:22' = @{
        Name     = 'ERROR_HANDLE_PROFILE'
        Meaning  = 'Error handling the profile (general failure while managing the profile).'
        Causes   = @('Unspecified failure in the profile handling stage; underlying Windows error varies')
        Fixes    = @('Read the Error value and Profile_<user>.log around the failure timestamp to identify the specific Windows error and failing operation')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:23' = @{
        Name     = 'ERROR_PROFILE_SUBFOLDER_REDIRECTION'
        Meaning  = 'Can''t set up folder redirections (redirections.xml exclusions).'
        Causes   = @('Invalid or inaccessible redirections.xml (RedirXMLSourceFolder)', 'Permissions on the redirection source path')
        Fixes    = @('Validate redirections.xml syntax and that RedirXMLSourceFolder is reachable by the user', 'Check the Error value for the underlying Windows error')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:24' = @{
        Name     = 'ERROR_CREATE_EVENT'
        Meaning  = 'Unable to create an event (internal Windows synchronization object).'
        Causes   = @('Resource exhaustion or security policy preventing creation of kernel sync objects')
        Fixes    = @('Check host resource health; review the Error value; reboot the session host if transient')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:25' = @{
        Name     = 'ERROR_PER_SESSION_VHD'
        Meaning  = 'Maximum sessions reached (per-session VHD limit hit).'
        Causes   = @('User has more concurrent sessions than allowed by the multiple-connections/per-session VHD configuration (e.g., NumSessionVHDsToKeep / ProfileType settings)')
        Fixes    = @('Review Microsoft''s ''multiple or concurrent connections'' concepts article and the ProfileType/NumSessionVHDsToKeep configuration', 'Have the user sign out of surplus sessions')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:26' = @{
        Name     = 'ERROR_DETACH_VHD'
        Meaning  = 'Can''t detach the virtual disk at the provided location (sign-out phase).'
        Causes   = @('Open handles on the container at logoff (processes, AV/backup agents)', 'Storage connectivity loss during sign-out')
        Fixes    = @('Apply AV exclusions; identify processes holding handles on the mounted volume at logoff', 'Check storage provider health; the Error value gives the specific Windows error')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:27' = @{
        Name     = 'ERROR_FIND_VHD'
        Meaning  = 'Can''t find the virtual disk at the provided location.'
        Causes   = @('Credentials/authentication failure to the share (Microsoft log example: ''FindFile failed ... The user name or password is incorrect'' with ErrorCode 1326)', 'Wrong VHDLocations path or renamed/moved container files', 'Share unreachable')
        Fixes    = @('Validate VHDLocations and the expected folder/file naming (FlipFlopProfileDirectoryName, VHDNamePattern settings)', 'Verify Kerberos/identity auth to the storage provider (especially Azure Files domain join/Kerberos setup)', 'Test the UNC path as the affected user')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    'Status:28' = @{
        Name     = 'ERROR_NO_SESSION_CONFIG'
        Meaning  = 'No user session config found - FSLogix has no session information for this user (also appears transiently in logs early in sign-in before setup runs).'
        Causes   = @('Session was established before FSLogix was enabled, or FSLogix decided not to manage the session (check Reason)', 'Transient state at the start of sign-in (Microsoft''s own log example shows 28 -> 100 -> 200 -> 0 during a normal logon)')
        Fixes    = @('If persistent, confirm FSLogix Profiles Enabled=1 and the user is included (Reason value tells you why the session isn''t managed)', 'If seen only early in the logon sequence followed by Status 0, no action is needed')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:3' = @{
        Name     = 'ERROR_GET_USER'
        Meaning  = 'Can''t retrieve user''s security identifier (SID).'
        Causes   = @('Domain controller unreachable or identity lookup failure at logon')
        Fixes    = @('Verify domain/DC connectivity from the session host', 'Check the Error value for the underlying Windows error; test with ''whoami /user''')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:300' = @{
        Name     = 'STATUS_ALREADY_ATTACHED'
        Meaning  = 'Normal: the profile is already attached. Applies to differencing disks only.'
        Causes   = @('A subsequent session found the container already attached (differencing-disk configurations)')
        Fixes    = @('No action required; expected behavior with differencing disks')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:4' = @{
        Name     = 'ERROR_HANDLE_ODFC'
        Meaning  = 'There was an error setting up the Office 365 (ODFC) Container.'
        Causes   = @('Misconfigured ODFC settings under HKLM\SOFTWARE\Policies\FSLogix\ODFC', 'ODFC storage location unreachable')
        Fixes    = @('Review ODFC container configuration (Enabled, VHDLocations/CCDLocations)', 'Check ODFC log files and the Error value for the Windows error code')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:5' = @{
        Name     = 'ERROR_SECURITY'
        Meaning  = 'Can''t retrieve security information for the user.'
        Causes   = @('Failure querying user security/ACL information (e.g., directory unavailable)')
        Fixes    = @('Check DC connectivity and the Error value / profile log for the specific Windows error')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:6' = @{
        Name     = 'ERROR_VHD_PATH'
        Meaning  = 'Can''t retrieve the virtual disk location.'
        Causes   = @('VHDLocations (standard) or CCDLocations (Cloud Cache) not set, wrong type, or malformed (Microsoft: must be REG_SZ preferred or REG_MULTI_SZ; multi-entry REG_SZ requires semicolon delimiting)', 'Storage path unreachable from the session host')
        Fixes    = @('Validate VHDLocations/CCDLocations under HKLM\SOFTWARE\FSLogix\Profiles or HKLM\SOFTWARE\Policies\FSLogix\ODFC (value present, correct type, correct delimiting)', 'Test the UNC path as an affected user before production use')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    'Status:7' = @{
        Name     = 'ERROR_CREATE_DIR'
        Meaning  = 'Can''t create destination folders (the per-user container folder on the share).'
        Causes   = @('Missing share-level or NTFS ''create folder'' permissions on the profile share (most common FSLogix misconfiguration per Microsoft)', 'Storage provider out of capacity')
        Fixes    = @('Apply Microsoft''s documented SMB storage permissions (users need rights to create/own their folder)', 'Verify free space on the storage provider')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:8' = @{
        Name     = 'ERROR_IMPERSONATION'
        Meaning  = 'Can''t impersonate the user.'
        Causes   = @('Token/credential problems during logon (e.g., Kerberos failures)')
        Fixes    = @('Check Kerberos health, machine time sync, and the Error value for the underlying Windows error', 'Restart the FSLogix service (frxsvc) / host if transient')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    'Status:9' = @{
        Name     = 'ERROR_CREATE_VHD'
        Meaning  = 'Can''t create the virtual disk (VHD/VHDX).'
        Causes   = @('Access denied on the share (Microsoft log example: ''VirtualDiskAPI::CreateFormattedDisk failed to create vhd(x) ... Access is denied'')', 'Storage provider full')
        Fixes    = @('Fix share/NTFS permissions per Microsoft''s storage permissions how-to', 'Increase storage capacity; check the Error value (e.g., 0x00000005 = access denied)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
}
