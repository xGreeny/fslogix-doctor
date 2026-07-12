# FSLogix error codes, status codes and event IDs - the reference

Plain-English meaning, likely causes and concrete fixes for the codes FSLogix
writes to its logs (`%ProgramData%\FSLogix\Logs`), to the per-session registry
state (`HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID>`) and to the
`Microsoft-FSLogix-Apps` event channels.

Decode any code straight from PowerShell:

```powershell
git clone https://github.com/xGreeny/fslogix-doctor.git
Import-Module .\fslogix-doctor\FSLogixDoctor\FSLogixDoctor.psd1

Get-FslErrorCode 0x00000020    # hex, decimal, int or symbolic name
Get-FslSessionState            # translated Status/Reason/Error per session
```

Entries marked **verified** are confirmed by official Microsoft documentation
(linked per entry). Community-observed entries are marked accordingly - treat
their causes as strong heuristics, not certainties. Corrections and additions
are very welcome: see [CONTRIBUTING](../CONTRIBUTING.md).

> This page is generated from the module's data files by
> `tools/Export-ErrorCodeDoc.ps1` - edit the `.psd1` files, not this page.
## Profile Status codes (registry: Status)

FSLogix writes the outcome of every profile attach to the `Status` value under
`HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID>`. Values 0, 100, 200 and 300 are
normal states; 1-28 are error states. Read them translated with `Get-FslSessionState`.

### Status 0 - STATUS_SUCCESS

**Meaning:** Success - the FSLogix operation completed and the container is working for this user (normal status).

**Likely causes:**
- Normal operation; profile/ODFC container attached successfully

**Fixes / next steps:**
- No action required. Pair with Reason=0 (container attached) to confirm fully healthy state

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 1 - ERROR

**Meaning:** Can't load user's profile (generic profile load failure).

**Likely causes:**
- Container locked/in use by another session (Windows error 33, 'AcquireExclusiveLock' failure documented by Microsoft)
- Storage permission or connectivity failure
- Any unclassified failure during profile load

**Fixes / next steps:**
- Read the companion 'Error' registry value and C:\\ProgramData\\FSLogix\\Logs\\Profile\\Profile\_\<user\>.log for the underlying Windows System Error Code
- Check whether the user has an active session on another host holding the VHDX lock; consider PreventLoginWithTempProfile or the documented multi/concurrent connection options
- Validate SMB share + NTFS permissions per Microsoft's 'Configure SMB Storage Permissions' how-to

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 2 - ERROR_VIRT_DLL

**Meaning:** Virtual disk API isn't available on this platform.

**Likely causes:**
- Unsupported Windows edition/version lacking the Virtual Disk (virtdisk.dll) API

**Fixes / next steps:**
- Verify the OS is on FSLogix's supported platform list
- Confirm virtdisk.dll / Virtual Disk service is present and functional

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 3 - ERROR_GET_USER

**Meaning:** Can't retrieve user's security identifier (SID).

**Likely causes:**
- Domain controller unreachable or identity lookup failure at logon

**Fixes / next steps:**
- Verify domain/DC connectivity from the session host
- Check the Error value for the underlying Windows error; test with 'whoami /user'

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 4 - ERROR_HANDLE_ODFC

**Meaning:** There was an error setting up the Office 365 (ODFC) Container.

**Likely causes:**
- Misconfigured ODFC settings under HKLM\\SOFTWARE\\Policies\\FSLogix\\ODFC
- ODFC storage location unreachable

**Fixes / next steps:**
- Review ODFC container configuration (Enabled, VHDLocations/CCDLocations)
- Check ODFC log files and the Error value for the Windows error code

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 5 - ERROR_SECURITY

**Meaning:** Can't retrieve security information for the user.

**Likely causes:**
- Failure querying user security/ACL information (e.g., directory unavailable)

**Fixes / next steps:**
- Check DC connectivity and the Error value / profile log for the specific Windows error

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 6 - ERROR_VHD_PATH

**Meaning:** Can't retrieve the virtual disk location.

**Likely causes:**
- VHDLocations (standard) or CCDLocations (Cloud Cache) not set, wrong type, or malformed (Microsoft: must be REG\_SZ preferred or REG\_MULTI\_SZ; multi-entry REG\_SZ requires semicolon delimiting)
- Storage path unreachable from the session host

**Fixes / next steps:**
- Validate VHDLocations/CCDLocations under HKLM\\SOFTWARE\\FSLogix\\Profiles or HKLM\\SOFTWARE\\Policies\\FSLogix\\ODFC (value present, correct type, correct delimiting)
- Test the UNC path as an affected user before production use

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Status 7 - ERROR_CREATE_DIR

**Meaning:** Can't create destination folders (the per-user container folder on the share).

**Likely causes:**
- Missing share-level or NTFS 'create folder' permissions on the profile share (most common FSLogix misconfiguration per Microsoft)
- Storage provider out of capacity

**Fixes / next steps:**
- Apply Microsoft's documented SMB storage permissions (users need rights to create/own their folder)
- Verify free space on the storage provider

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 8 - ERROR_IMPERSONATION

**Meaning:** Can't impersonate the user.

**Likely causes:**
- Token/credential problems during logon (e.g., Kerberos failures)

**Fixes / next steps:**
- Check Kerberos health, machine time sync, and the Error value for the underlying Windows error
- Restart the FSLogix service (frxsvc) / host if transient

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 9 - ERROR_CREATE_VHD

**Meaning:** Can't create the virtual disk (VHD/VHDX).

**Likely causes:**
- Access denied on the share (Microsoft log example: 'VirtualDiskAPI::CreateFormattedDisk failed to create vhd(x) ... Access is denied')
- Storage provider full

**Fixes / next steps:**
- Fix share/NTFS permissions per Microsoft's storage permissions how-to
- Increase storage capacity; check the Error value (e.g., 0x00000005 = access denied)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 10 - ERROR_CLOSE_HANDLE

**Meaning:** Can't release the virtual disk.

**Likely causes:**
- Open handles on the container (processes, filter drivers such as antivirus) preventing release

**Fixes / next steps:**
- Check for processes/AV holding handles on the VHDX; apply Microsoft's recommended antivirus exclusions
- Review the Error value for the Windows error code

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 11 - ERROR_OPEN_VHD

**Meaning:** Can't open the virtual disk.

**Likely causes:**
- File locked by another session or process
- Insufficient permissions on the VHDX
- Corrupted container file

**Fixes / next steps:**
- Check for locks (other sessions, backup/AV agents)
- Validate permissions; test disk integrity (e.g., mount manually / chkdsk inside the container)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 12 - ERROR_ATTACH_VHD

**Meaning:** Can't attach to the virtual disk.

**Likely causes:**
- Access denied or file locked (Microsoft log examples: 'Attach vhd(x) failed, file is locked' / 'Failed to attach VHD (Access is denied)')
- Profile in use on another computer (single-connection default)

**Fixes / next steps:**
- Sign the user out of other sessions using the same container, or configure multiple/concurrent connections per Microsoft's concepts article
- Fix SMB/NTFS permissions; check the Error value (0x00000005 access denied, 0x00000020/33 sharing/lock violations)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Status 13 - ERROR_GET_PHYSICAL_PATH

**Meaning:** Can't retrieve the virtual disk's physical information after attach.

**Likely causes:**
- Virtual Disk API/service problem after attach

**Fixes / next steps:**
- Check the Error value and profile log; verify Virtual Disk service health; retry logon

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 14 - ERROR_OPEN_DEVICE

**Meaning:** Can't open the virtual disk's volume device.

**Likely causes:**
- Filter driver interference (antivirus/security agents) with the mounted volume

**Fixes / next steps:**
- Apply Microsoft's recommended FSLogix antivirus exclusions
- Check the Error value for the Windows error code

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 15 - ERROR_INIT_DISK

**Meaning:** Can't initialize the virtual disk (first-time disk setup).

**Likely causes:**
- Interrupted first-time container creation leaving a partial/invalid VHDX

**Fixes / next steps:**
- Remove/rename the partially created VHDX and let FSLogix recreate it
- Check storage stability and the Error value

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 16 - ERROR_GET_VOL_GUID

**Meaning:** Can't retrieve the virtual disk (volume) identifier.

**Likely causes:**
- Volume enumeration failure after attach (mount manager issues)

**Fixes / next steps:**
- Check the Error value and profile log; verify mount manager/Virtual Disk service; retry

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 17 - ERROR_FORMAT_VOL

**Meaning:** Error while formatting the virtual disk volume (first-time creation).

**Likely causes:**
- Formatting of the new container volume failed (storage interruption, filter drivers)

**Fixes / next steps:**
- Delete the failed VHDX and allow re-creation
- Check AV exclusions and the Error value

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 18 - ERROR_GET_PROFILE_DIR

**Meaning:** Can't retrieve the user's profile directory from Windows.

**Likely causes:**
- Windows Profile Service (ProfSvc) did not provide the profile folder
- Broken ProfileList registry state for the user

**Fixes / next steps:**
- Check HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList for stale/.bak entries for the SID
- Review User Profile Service event log (Application log, ProfSvc events)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 19 - ERROR_SET_MOUNT_POINT

**Meaning:** Can't set up the directory mount point (junction from C:\\Users\\\<user\> into the container volume).

**Likely causes:**
- Existing conflicting local profile folder or leftover mount point
- Permissions/handles on the profile path

**Fixes / next steps:**
- Check for a pre-existing local profile folder for the user and stale mount points under C:\\Users
- Review the Error value; consider DeleteLocalProfileWhenVHDShouldApply if a local profile is the conflict (caution: data loss)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 20 - ERROR_REG_IMPORT

**Meaning:** Can't import registry information (per-user registry data during profile setup).

**Likely causes:**
- Failure writing/loading the user's registry hive or FSLogix registry data

**Fixes / next steps:**
- Check the Error value and profile log; verify the user hive (NTUSER.DAT) inside the container isn't corrupt

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 21 - ERROR_CHK_GRP_MEMBERSHIP

**Meaning:** Can't retrieve the user's group membership (needed to evaluate FSLogix include/exclude groups).

**Likely causes:**
- Domain controller unreachable during group evaluation
- Broken local 'FSLogix Profile Include/Exclude List' groups

**Fixes / next steps:**
- Verify DC connectivity and that the local FSLogix Include/Exclude List groups exist and resolve
- Check the Error value for the Windows error code

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 22 - ERROR_HANDLE_PROFILE

**Meaning:** Error handling the profile (general failure while managing the profile).

**Likely causes:**
- Unspecified failure in the profile handling stage; underlying Windows error varies

**Fixes / next steps:**
- Read the Error value and Profile\_\<user\>.log around the failure timestamp to identify the specific Windows error and failing operation

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 23 - ERROR_PROFILE_SUBFOLDER_REDIRECTION

**Meaning:** Can't set up folder redirections (redirections.xml exclusions).

**Likely causes:**
- Invalid or inaccessible redirections.xml (RedirXMLSourceFolder)
- Permissions on the redirection source path

**Fixes / next steps:**
- Validate redirections.xml syntax and that RedirXMLSourceFolder is reachable by the user
- Check the Error value for the underlying Windows error

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 24 - ERROR_CREATE_EVENT

**Meaning:** Unable to create an event (internal Windows synchronization object).

**Likely causes:**
- Resource exhaustion or security policy preventing creation of kernel sync objects

**Fixes / next steps:**
- Check host resource health; review the Error value; reboot the session host if transient

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 25 - ERROR_PER_SESSION_VHD

**Meaning:** Maximum sessions reached (per-session VHD limit hit).

**Likely causes:**
- User has more concurrent sessions than allowed by the multiple-connections/per-session VHD configuration (e.g., NumSessionVHDsToKeep / ProfileType settings)

**Fixes / next steps:**
- Review Microsoft's 'multiple or concurrent connections' concepts article and the ProfileType/NumSessionVHDsToKeep configuration
- Have the user sign out of surplus sessions

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 26 - ERROR_DETACH_VHD

**Meaning:** Can't detach the virtual disk at the provided location (sign-out phase).

**Likely causes:**
- Open handles on the container at logoff (processes, AV/backup agents)
- Storage connectivity loss during sign-out

**Fixes / next steps:**
- Apply AV exclusions; identify processes holding handles on the mounted volume at logoff
- Check storage provider health; the Error value gives the specific Windows error

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 27 - ERROR_FIND_VHD

**Meaning:** Can't find the virtual disk at the provided location.

**Likely causes:**
- Credentials/authentication failure to the share (Microsoft log example: 'FindFile failed ... The user name or password is incorrect' with ErrorCode 1326)
- Wrong VHDLocations path or renamed/moved container files
- Share unreachable

**Fixes / next steps:**
- Validate VHDLocations and the expected folder/file naming (FlipFlopProfileDirectoryName, VHDNamePattern settings)
- Verify Kerberos/identity auth to the storage provider (especially Azure Files domain join/Kerberos setup)
- Test the UNC path as the affected user

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Status 28 - ERROR_NO_SESSION_CONFIG

**Meaning:** No user session config found - FSLogix has no session information for this user (also appears transiently in logs early in sign-in before setup runs).

**Likely causes:**
- Session was established before FSLogix was enabled, or FSLogix decided not to manage the session (check Reason)
- Transient state at the start of sign-in (Microsoft's own log example shows 28 -\> 100 -\> 200 -\> 0 during a normal logon)

**Fixes / next steps:**
- If persistent, confirm FSLogix Profiles Enabled=1 and the user is included (Reason value tells you why the session isn't managed)
- If seen only early in the logon sequence followed by Status 0, no action is needed

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 100 - STATUS_WAITING_FOR_PROFILE_DIR_SET

**Meaning:** Normal: waiting for the Windows Profile Service to determine the user's profile folder.

**Likely causes:**
- Normal transient state during sign-in

**Fixes / next steps:**
- No action if transient; if stuck here, investigate the Windows User Profile Service (ProfSvc) and logon slowness

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 200 - STATUS_IN_PROGRESS

**Meaning:** Normal: FSLogix setup (container attach/profile setup) is in progress.

**Likely causes:**
- Normal transient state during sign-in

**Fixes / next steps:**
- No action if it progresses to Status 0; if it persists, review Profile\_\<user\>.log for where setup stalls (storage latency is a common culprit)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Status 300 - STATUS_ALREADY_ATTACHED

**Meaning:** Normal: the profile is already attached. Applies to differencing disks only.

**Likely causes:**
- A subsequent session found the container already attached (differencing-disk configurations)

**Fixes / next steps:**
- No action required; expected behavior with differencing disks

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

## Reason codes (registry: Reason)

`Reason` clarifies **normal** Status values only - most importantly why a
container did *not* attach even though nothing failed (exclude group, existing
local profile, temp profile, non-AVD session).

### Reason 0 - REASON_PROFILE_ATTACHED

**Meaning:** The container is attached. With Status 0 this is the fully healthy state.

**Likely causes:**
- Normal operation

**Fixes / next steps:**
- No action required

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 1 - REASON_NOT_IN_WHITE_LIST

**Meaning:** User isn't a member of the include group ('FSLogix Profile Include List' / 'FSLogix ODFC Include List'), so FSLogix skipped the session.

**Likely causes:**
- User (or their groups) not in the local FSLogix Include List group
- Include group membership changed or GPO restricting membership

**Fixes / next steps:**
- Add the user (or Domain Users, as appropriate) to the local 'FSLogix Profile Include List' group
- Check GPO/Restricted Groups policies that may rewrite local group membership

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 2 - REASON_IN_BLACK_LIST

**Meaning:** User is a member of the exclude group ('FSLogix Profile Exclude List' / 'FSLogix ODFC Exclude List'), so FSLogix skipped the session.

**Likely causes:**
- User deliberately or accidentally placed in the local FSLogix Exclude List group (directly or via nested group)

**Fixes / next steps:**
- Remove the user from the local 'FSLogix Profile Exclude List' group if exclusion is unintended (exclude wins over include)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 3 - REASON_LOCAL_PROFILE_EXISTS

**Meaning:** A local (non-FSLogix) profile for this user already exists on this system; by default FSLogix honors the local profile instead of attaching the container.

**Likely causes:**
- User signed in on this host before FSLogix was installed/enabled, leaving a local profile
- Leftover local profile from a previous failed logoff/cleanup

**Fixes / next steps:**
- Enable DeleteLocalProfileWhenVHDShouldApply so FSLogix deletes the local profile at sign-in and attaches the container (Microsoft warns: review existing local profiles first to limit data-loss exposure)
- Alternatively remove the local profile manually (Advanced System Settings \> User Profiles, or ProfileList cleanup) after preserving needed data

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Reason 4 - REASON_SHORT_SID

**Meaning:** Not an appropriate user type - the account's SID is a short/well-known SID (local system/service/built-in accounts), which FSLogix doesn't manage.

**Likely causes:**
- Sign-in by local, built-in, or system accounts rather than a normal domain/AAD user

**Fixes / next steps:**
- Expected behavior for system/local accounts; no action needed. If seen for a real user, verify the account type and SID

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 5 - REASON_UNSET

**Meaning:** Reason initialized to empty state (no reason has been recorded yet).

**Likely causes:**
- Transient/initial state before FSLogix records an outcome for the session

**Fixes / next steps:**
- Re-read after logon completes; investigate the Status value and profile log if it never changes

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 6 - REASON_COMPONENT_NOT_ENABLED

**Meaning:** Component isn't enabled in the product key (legacy licensing-era code); in practice the Profiles/ODFC feature isn't enabled.

**Likely causes:**
- FSLogix installed but the Profiles or ODFC container feature isn't enabled (Enabled=0 or missing)
- Legacy product-key licensing not covering the component (historic versions)

**Fixes / next steps:**
- Set Enabled=1 under HKLM\\SOFTWARE\\FSLogix\\Profiles (or HKLM\\SOFTWARE\\Policies\\FSLogix\\ODFC) per the Microsoft configure-profile-containers tutorial

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 7 - REASON_WINDOWS_TEMP_PROFILE

**Meaning:** The profile in use is a Windows temporary profile (FSLogix did not manage/attach; the user landed in a TEMP profile).

**Likely causes:**
- Container in use on another machine (default single-connection behavior) so Windows fell back to a temp profile
- An earlier attach failure caused Windows to issue a temp profile
- Stale .bak entries under the ProfileList registry key

**Fixes / next steps:**
- Find and fix the underlying attach failure (Status/Error values, Profile\_\<user\>.log)
- Consider PreventLoginWithTempProfile to block sign-in instead of allowing temp profiles (evaluate per-organization, per Microsoft guidance)
- Clean up stale HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList\\\<SID\>.bak entries

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Reason 8 - REASON_NOT_WVD_SESSION

**Meaning:** The session isn't an Azure Virtual Desktop session, so FSLogix skipped it (relevant where FSLogix is configured/entitled to operate only for AVD sessions).

**Likely causes:**
- Sign-in over a non-AVD connection (e.g., console/direct RDP) on a host where FSLogix is scoped to AVD sessions

**Fixes / next steps:**
- Confirm the connection type; review FSLogix configuration/entitlement expectations for non-AVD sessions on that host

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Reason 9 - REASON_FAILED_TO_LOAD_PROFILE

**Meaning:** Profile load failed - FSLogix attempted but could not load the profile.

**Likely causes:**
- Any underlying attach/load failure (locks, permissions, storage) - the Status and Error values carry the specifics

**Fixes / next steps:**
- Read the Status (error) code and Error (Windows System Error Code) values under the same Sessions\\\<SID\> key
- Correlate with Profile\_\<user\>.log entries at the failure timestamp and fix the underlying cause (permissions, locks, path)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

## Windows error codes in FSLogix logs (and registry: Error)

The `Error` registry value and the `[WARN: xxxxxxxx]` / `[ERROR:xxxxxxxx]`
markers in the text logs carry standard Windows system error codes (sometimes
in HRESULT form `0x8007xxxx`). These are the codes worth knowing in an FSLogix
context.

### Code 0x00000002 - ERROR_FILE_NOT_FOUND

**Meaning:** The system cannot find the file specified. In FSLogix logs this is usually the container VHD/VHDX not found at the expected path, e.g. 'Failed to query size of VHD(x)'. Benign as a WARN at a user's first sign-in (container not created yet); an ERROR if an existing container is expected but missing.

**Likely causes:**
- First sign-in for the user (no container exists yet - normal)
- VHDLocations points to the wrong folder, or folder/file naming settings (FlipFlopProfileDirectoryName, SIDDirNamePattern, VHDNamePattern) changed after containers were created
- Container was deleted, moved or renamed on the share

**Fixes / next steps:**
- Ignore if it is the user's first logon and a container is then created
- Verify VHDLocations and naming-pattern settings match the actual folder/file layout on the share
- Confirm the user's Profile\_\*.vhdx exists at the expected UNC path (browse it as the user)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Code 0x00000003 - ERROR_PATH_NOT_FOUND

**Meaning:** The system cannot find the path specified. The share may be reachable but the directory path (or a local path) does not exist. Microsoft's FSLogix docs show the HRESULT-wrapped form 0x80070003 of this same code in profile logs.

**Likely causes:**
- Typo or stale entry in VHDLocations/CCDLocations
- Per-user subfolder missing and FSLogix lacks permission to create directories
- Unexpanded/undefined environment variable inside a configured path

**Fixes / next steps:**
- Validate VHDLocations/CCDLocations values (REG\_SZ, semicolon-delimited for multiple entries) per the Microsoft old/temp/local-profiles troubleshooting article
- Test the exact UNC path from the session host
- Grant the create-folder NTFS rights required by the Microsoft SMB storage permissions how-to

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) (community-observed)

### Code 0x00000005 - ERROR_ACCESS_DENIED

**Meaning:** Access is denied. The most common FSLogix attach failure: FSLogix could not open/create/attach the container or remove a directory because the user or computer identity lacks permissions, or the file is locked. Official docs show log lines such as 'Attach vhd(x) failed, file is locked... (Access is denied.)' and 'Failed to attach VHD. (Access is denied.)'.

**Likely causes:**
- Missing/incorrect NTFS ACLs or SMB share permissions on the container share
- Azure Files: user/group missing the 'Storage File Data SMB Share Contributor' RBAC role
- Container file locked by another process while retrying attach
- Antivirus/EDR blocking VHD(X) access
- Wrong identity used against storage (e.g. Entra-joined hosts without proper Kerberos/AccessNetworkAsComputerObject configuration)

**Fixes / next steps:**
- Configure permissions exactly per Microsoft's 'Configure SMB Storage Permissions' how-to
- Azure Files: assign Storage File Data SMB Share Contributor (Elevated Contributor for admins) and re-check NTFS ACLs
- Add AV exclusions for %ProgramFiles%\\FSLogix and \*.vhd/\*.vhdx per Microsoft guidance
- Test by browsing the share and creating a folder as the affected user

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Code 0x00000013 - ERROR_WRITE_PROTECT

**Meaning:** The media is write protected. The profile container attaches read-only or fails to attach because a policy denies write access to non-BitLocker-protected fixed drives (the mounted VHD is seen as an unprotected fixed drive).

**Likely causes:**
- 'Deny write access to fixed drives not protected by BitLocker' enforced via Intune, Defender, or GPO
- Container deliberately attached read-only (VHDAccessMode/ProfileType read-only settings)

**Fixes / next steps:**
- Exclude session hosts from the BitLocker deny-write policy (Intune/Defender/GPO) as described by Nerdio's mount-error guide
- Review VHDAccessMode/ProfileType if read-only behavior is unexpected

*Source:* [https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors](https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors) (community-observed)

### Code 0x0000001F - ERROR_GEN_FAILURE

**Meaning:** A device attached to the system is not functioning. Low-level failure of the virtual-disk stack while attaching the VHD(X); the profile fails to attach and the user typically gets a temp profile.

**Likely causes:**
- Microsoft Virtual Disk (virtdisk) driver not fully installed/initialized on a freshly provisioned VDI image (works after a reboot or delay)
- Corrupted VHDX
- Underlying storage/driver fault

**Fixes / next steps:**
- Reboot the session host; if it recurs on fresh provisions, warm up/reboot images before first logon
- Update FSLogix to the latest release
- Test-mount the container manually (Mount-VHD / frx) and run chkdsk inside it
- Check System event log for disk/virtdisk errors

*Source:* [https://learn.microsoft.com/en-us/answers/questions/250546/fslogix-vhdx-not-attaching-on-first-login](https://learn.microsoft.com/en-us/answers/questions/250546/fslogix-vhdx-not-attaching-on-first-login) (community-observed)

### Code 0x00000020 - ERROR_SHARING_VIOLATION

**Meaning:** The process cannot access the file because it is being used by another process. In FSLogix: the container VHD(X) is already open - the profile is attached in another session, or a stale/orphaned SMB handle from a crashed session still holds the file. Frequently seen in the per-session registry as Error=0x00000020 with Status 0x0000000C (ERROR\_ATTACH\_VHD).

**Likely causes:**
- User signed in on another session host with the same container (default config allows only one connection)
- Previous session crashed / VM force-restarted so the handle was never released
- Orphaned file handle or lease on Azure Files / file server
- Backup or antivirus holding the VHD(X) open

**Fixes / next steps:**
- Check for and sign out other sessions (qwinsta, host pool user sessions)
- Close open handles: Windows file server via Computer Management \> Shared Folders \> Open Files; Azure Files via portal/Az PowerShell (Close-AzStorageFileHandle) per Microsoft's FSLogix open-file-handles article
- Restart the VM that still holds the lock
- Add AV/backup exclusions for VHD(X) files
- If multi-session access is a business need, evaluate FSLogix concurrent-connections (differencing disk) configuration

*Source:* [https://learn.microsoft.com/en-us/answers/questions/1625025/fixing-error-code-0x00000020-when-logging-into-dev](https://learn.microsoft.com/en-us/answers/questions/1625025/fixing-error-code-0x00000020-when-logging-into-dev) (community-observed)

### Code 0x00000021 - ERROR_LOCK_VIOLATION

**Meaning:** The process cannot access the file because another process has locked a portion of the file. FSLogix failed to obtain its exclusive byte-range lock on the container: the profile is in use on another computer. Official docs show 'ErrorCode set to 33' and 'LoadProfile failed... FrxStatus: 33' for this scenario.

**Likely causes:**
- Same profile container mounted by an active session on a different host
- Stale lock from a session that did not sign out cleanly

**Fixes / next steps:**
- Sign the user out of the original session before connecting elsewhere
- Close orphaned SMB handles on the storage backend
- Decide policy: allow temp profile, enable PreventLoginWithTempProfile, or configure multiple/concurrent connections per Microsoft's concepts-multi-concurrent-connections article

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Code 0x00000035 - ERROR_BAD_NETPATH

**Meaning:** The network path was not found. The session host cannot reach the SMB endpoint hosting VHDLocations at all (network/DNS/port-level failure), so no container can be found or created.

**Likely causes:**
- TCP port 445 outbound blocked (ISP, NSG, firewall)
- DNS cannot resolve the file server / storage account FQDN (common with Azure private endpoints)
- File server or storage account offline
- NTLMv1-only client configuration (Azure Files requires NTLMv2/Kerberos)

**Fixes / next steps:**
- Test-NetConnection \<server\> -Port 445 from the session host
- Verify DNS resolution (private endpoint DNS zones for Azure Files)
- Check NSG/firewall rules and run the AzFileDiagnostics tool per Microsoft's Azure Files SMB troubleshooting doc
- Confirm VHDLocations hostname is correct

*Source:* [https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity) (verified by Microsoft docs)

### Code 0x00000040 - ERROR_NETNAME_DELETED

**Meaning:** The specified network name is no longer available. The established SMB session to the container storage dropped while the container was attached or being attached - users may freeze, lose their session, or the container may be corrupted on repeated occurrences.

**Likely causes:**
- Network instability / packet loss between session hosts and storage
- Storage failover or maintenance closing SMB sessions
- Storage throttling or an overloaded file server dropping connections

**Fixes / next steps:**
- Check Microsoft-Windows-SMBClient event logs at matching timestamps
- Review storage availability/throttling metrics (Azure Files transactions, IOPS caps)
- Use SMB Continuous Availability capable storage (Premium Azure Files, ANF) or FSLogix Cloud Cache for resilience
- Validate NIC/network path health

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) (community-observed)

### Code 0x00000043 - ERROR_BAD_NET_NAME

**Meaning:** The network name cannot be found. The server responds but the share name in VHDLocations cannot be resolved - classic 'System error 67'. Documented by Microsoft for Azure file share mounts and reported in FSLogix profile creation cases (e.g. AVD on Azure Stack HCI).

**Likely causes:**
- Misspelled share name in VHDLocations
- File share does not exist (never created, or deleted)
- SMB namespace/share path cannot be resolved even though the endpoint is reachable
- Port 445 partially blocked

**Fixes / next steps:**
- Verify the share exists and the exact spelling of \\\\server\\share in VHDLocations
- Browse the UNC from a session host on the same network
- Check storage account network access restrictions ('Selected networks' rules)
- Follow the Error 53/67/87 section of Microsoft's Azure Files SMB troubleshooting doc

*Source:* [https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity) (verified by Microsoft docs)

### Code 0x00000047 - ERROR_REQ_NOT_ACCEP

**Meaning:** No more connections can be made to this remote computer at this time because there are already as many connections as the computer can accept. Only the first N users get their containers mounted; later logons fail.

**Likely causes:**
- Containers hosted on a client-SKU Windows machine (20 concurrent SMB connection limit)
- NAS appliance with per-license SMB connection limits
- File server at its configured session limit

**Fixes / next steps:**
- Host containers on server-class or scalable storage (Windows Server file share, Azure Files, Azure NetApp Files)
- Increase the NAS SMB connection/license limit
- Distribute users across multiple shares if the backend cannot scale

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) (community-observed)

### Code 0x00000057 - ERROR_INVALID_PARAMETER

**Meaning:** The parameter is incorrect. Seen when mounting the share or attaching the disk fails due to an invalid parameter - Microsoft documents 'System error 87' for Azure file share mounts (commonly NTLMv1 clients); in FSLogix logs it can also indicate malformed configuration values.

**Likely causes:**
- NTLMv1 enabled on the client (LmCompatibilityLevel \< 3) against Azure Files
- Invalid FSLogix registry values (wrong type/range, e.g. SizeInMBs)
- Corrupt VHD metadata passed to the virtual disk API

**Fixes / next steps:**
- Set HKLM\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\LmCompatibilityLevel to 3 or higher
- Validate FSLogix registry value types against the Microsoft configuration settings reference
- Recreate or repair the container if VHD metadata is damaged

*Source:* [https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity) (verified by Microsoft docs)

### Code 0x00000070 - ERROR_DISK_FULL

**Meaning:** There is not enough space on the disk. Either the storage backing VHDLocations is full (containers cannot be created or expanded) or the dynamically expanding container hit its maximum size. Microsoft documents storage-capacity exhaustion as a cause of temp/local profiles, hung sessions, and failed mounts/detaches.

**Likely causes:**
- Azure Files share quota reached
- File server volume out of space
- Container reached its SizeInMBs maximum (disk full \*inside\* the VHD)

**Fixes / next steps:**
- Increase the file share quota / expand the volume; monitor capacity per Microsoft's storage-space guidance
- Enable/verify VHD disk compaction (VHDCompactDisk) and clean container content with redirections.xml exclusions
- Raise SizeInMBs if containers legitimately need more space (new size applies to dynamic disks)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (community-observed)

### Code 0x00000079 - ERROR_SEM_TIMEOUT

**Meaning:** The semaphore timeout period has expired. An SMB/storage operation (usually AttachVirtualDisk) timed out - the classic signature of a slow, congested, or lossy path to the container storage. Logged as 'ErrorCode set to 121' / 'Failed to attach VHD (The semaphore timeout period has expired.)'.

**Likely causes:**
- Network latency or packet loss to the file server / storage account
- Storage throttling (Azure Files standard IOPS/burst limits) or overloaded file server
- Antivirus scanning large VHD(X) files during attach
- NIC/SMB multichannel or RSS misconfiguration

**Fixes / next steps:**
- Check storage latency and throttling metrics; move to Premium Azure Files or scale the file server if saturated
- Validate the network path (latency, MTU, drops) between hosts and storage
- Add AV exclusions for VHD/VHDX and FSLogix processes
- Stagger logon storms; review concurrent attach volume per host

*Source:* [https://learn.microsoft.com/en-us/answers/questions/521937/fslogix-semaphore-timeout](https://learn.microsoft.com/en-us/answers/questions/521937/fslogix-semaphore-timeout) (community-observed)

### Code 0x0000007B - ERROR_INVALID_NAME

**Meaning:** The filename, directory name, or volume label syntax is incorrect. FSLogix cannot parse a configured path - typically a syntactically malformed VHDLocations/CCDLocations or naming-pattern value.

**Likely causes:**
- Quotes, trailing spaces/semicolons, or illegal characters inside the VHDLocations REG\_SZ value
- Environment variable in the path that does not exist at service time (profile attach happens before the shell defines user variables)
- Bad VHDNamePattern/VHDNameMatch tokens

**Fixes / next steps:**
- Re-enter VHDLocations without surrounding quotes; separate multiple paths with semicolons only
- Use only variables that exist in the SYSTEM context at logon
- Verify naming pattern settings against the Microsoft configuration settings reference

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) (community-observed)

### Code 0x00000091 - ERROR_DIR_NOT_EMPTY

**Meaning:** The directory is not empty. Cleanup of a directory failed - most often FSLogix removing the local\_%username% staging folder, a mount-point directory, or a leftover local profile at sign-out/sign-in. Usually a WARN and retried at next logon.

**Likely causes:**
- Files inside the folder still open (antivirus, search indexer, backup agent)
- Leftover data from a crashed session
- Third-party agents writing into the profile path during logoff

**Fixes / next steps:**
- Generally benign if occasional; FSLogix retries the cleanup at next logon
- If persistent, identify the process holding files open and add AV/indexer exclusions
- Reboot the host to clear stuck handles; remove stale local\_\* folders during maintenance

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) (community-observed)

### Code 0x000000A7 - ERROR_LOCK_FAILED

**Meaning:** Unable to lock a region of a file. FSLogix's 'AcquireExclusiveLock' operation on the container failed - the profile is in use on another computer. Official docs show '[ERROR:000000a7] Operation AcquireExclusiveLock failed. Retrying...' followed by Status 1 (cannot load profile) and ErrorCode 33.

**Likely causes:**
- Active session using the same container on another host
- Stale SMB handle/lease still holding the previous lock

**Fixes / next steps:**
- Sign the user out of their other session(s)
- Close orphaned file handles on the storage backend (see Microsoft's FSLogix open-file-handles article)
- Consider concurrent-connection (differencing disk) configuration if simultaneous sessions are required

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Code 0x000000B7 - ERROR_ALREADY_EXISTS

**Meaning:** Cannot create a file when that file already exists. FSLogix tried to create a folder/file that is already present - official docs show '[ERROR:000000b7] No Create access: \\\\server\\share\\user-SID... (Cannot create a file when that file already exists.)' followed by LoadProfile failed.

**Likely causes:**
- Leftover/orphaned profile directory or local\_%username% folder from an earlier failed logon
- Duplicate SID-named folder on the share (e.g. after SID history or username change)
- Race condition between two hosts creating the same profile folder

**Fixes / next steps:**
- Remove or rename the stale conflicting folder on the share (after backing it up)
- Clean up leftover local\_\* staging folders on the session host
- Ensure only one naming convention (FlipFlopProfileDirectoryName etc.) is in effect across all hosts

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Code 0x00000428 - ERROR_EXCEPTION_IN_SERVICE

**Meaning:** An exception occurred in the service when handling the control request. In FSLogix logs this is usually a \*trailing\* error on 'LoadProfile failed' lines - the frxsvc service hit an exception after an earlier root-cause error; also matches known frxsvc crash bugs that give users temp profiles.

**Likely causes:**
- A preceding error a few lines earlier in the Profile log is the real cause (per Nerdio's guidance)
- frxsvc.exe crash bugs in specific releases (e.g. FSLogix 2210 InstallAppxPackages crash, fixed in later versions)

**Fixes / next steps:**
- Search the Profile log upward for the first [ERROR:...] entry before this one and diagnose that code instead
- Update FSLogix to the latest release
- Collect logs with the FSLogix Support Tool and open a support case if it persists

*Source:* [https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors](https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors) (community-observed)

### Code 0x0000045D - ERROR_IO_DEVICE

**Meaning:** The request could not be performed because of an I/O device error. Read/write against the mounted container or the underlying SMB channel failed at device level - possible container corruption or storage-side fault.

**Likely causes:**
- Network drops during heavy container I/O
- Storage hardware or filesystem faults on the backend
- Corrupted VHD(X) after an unclean detach/power loss

**Fixes / next steps:**
- Mount the container manually and run chkdsk against the volume inside it
- Check backend storage health and SMB client/server event logs
- Restore the container from backup if corrupt
- Consider Cloud Cache for redundancy against storage faults

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-) (community-observed)

### Code 0x0000048F - ERROR_DEVICE_NOT_CONNECTED

**Meaning:** The device is not connected. Per Nerdio's FSLogix mount-error guide, in practice this commonly surfaces when the Azure file share's size limit/quota has been reached (writes to the 'device' fail), or when the SMB connection dropped during attach.

**Likely causes:**
- File share quota/size limit reached
- Transient SMB disconnect between host and storage during the operation

**Fixes / next steps:**
- Increase the file share size quota
- Check storage capacity and connection metrics
- Retry the logon after capacity/connectivity is restored

*Source:* [https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors](https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors) (community-observed)

### Code 0x000004C3 - ERROR_SESSION_CREDENTIAL_CONFLICT

**Meaning:** Multiple connections to a server or shared resource by the same user, using more than one user name, are not allowed. Windows already has an SMB session to the storage host under different credentials, so FSLogix's connection attempt is rejected.

**Likely causes:**
- cmdkey/Credential Manager entry with the storage account key (common Entra ID-joined workaround) conflicting with the user/computer Kerberos identity
- Mapped drive or script mounting the same server as a different user
- Mixed authentication paths to the same storage account from one host

**Fixes / next steps:**
- Remove conflicting stored credentials and mappings (cmdkey /delete, net use \\\\server /delete)
- Standardize on a single authentication method per host for the container share
- Avoid user drive mappings to the same file server that hosts FSLogix containers

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-) (community-observed)

### Code 0x000004F1 - ERROR_DOWNGRADE_DETECTED

**Meaning:** The system cannot contact a domain controller to service the authentication request. Kerberos authentication to the container share failed because no DC (or Entra Kerberos endpoint) could service the request - a frequent Azure Files + AVD failure.

**Likely causes:**
- Domain controller unreachable (VNet DNS not pointing at DCs, DC offline)
- Entra ID-joined-only hosts missing Cloud Kerberos configuration (CloudKerberosTicketRetrievalEnabled, credential key registry settings) for the storage account
- Storage account Kerberos/AD object misconfigured
- Conditional Access interfering with the storage service principal

**Fixes / next steps:**
- Verify DC reachability and VNet DNS settings; test with nltest/klist
- For Entra ID-joined: follow Microsoft's 'Use Azure Files with Entra ID' guidance (enable Entra Kerberos, set required session-host registry keys, exclude the storage app from CA policies)
- Re-register/repair the storage account's AD or Entra Kerberos configuration
- Re-image or redeploy session hosts after changing these settings (per Nerdio)

*Source:* [https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors](https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors) (community-observed)

### Code 0x0000052E - ERROR_LOGON_FAILURE

**Meaning:** The user name or password is incorrect. Authentication to the container share failed - official FSLogix docs show '[ERROR:0000052e] FindFile failed for path: \\\\server\\share\\...Profile\*.VHDX (The user name or password is incorrect.)' with 'ErrorCode set to 1326', leading to Status 27 (cannot find virtual disk).

**Likely causes:**
- Azure Files identity-based auth misconfigured (AD DS/Entra Kerberos not enabled or broken on the storage account)
- Expired or rotated storage account key still stored via cmdkey
- Storage account's AD computer object password/kerb keys out of sync
- Time skew breaking Kerberos

**Fixes / next steps:**
- Re-validate storage authentication: re-run the AzFilesHybrid join / rotate kerb keys, or update stored credentials
- Follow Microsoft's 'Configure SMB Storage Permissions' and Azure Files identity-auth docs
- Check time synchronization on hosts and DCs
- Test share access interactively as the affected user

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles](https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles) (verified by Microsoft docs)

### Code 0x0000052F - ERROR_ACCOUNT_RESTRICTION

**Meaning:** Account restrictions are preventing this user from signing in (blank passwords not allowed, sign-in times limited, or a policy restriction enforced). With Azure Files + Entra Kerberos this classically means Conditional Access/MFA is being applied to the storage account's service principal, blocking the Kerberos ticket for the share.

**Likely causes:**
- Storage account app registration not excluded from Conditional Access/MFA policies (Cloud Kerberos deployments)
- Logon-hours or other account restrictions on the user
- Policy restriction on the authenticating identity

**Fixes / next steps:**
- Exclude the storage account's app registration from all Conditional Access policies (disable MFA for it) per Microsoft's Entra Kerberos guidance
- Review account restrictions (logon hours, workstation restrictions) for the user

*Source:* [https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors](https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors) (community-observed)

### Code 0x000005AA - ERROR_NO_SYSTEM_RESOURCES

**Meaning:** Insufficient system resources exist to complete the requested service. The session host ran out of kernel resources (paged/non-paged pool, memory) while attaching containers or servicing container I/O - typically on densely loaded multi-session hosts.

**Likely causes:**
- Memory/pool exhaustion on heavily loaded session hosts
- Many simultaneously mounted containers plus memory-hungry workloads
- Handle or pool leaks from drivers/agents

**Fixes / next steps:**
- Right-size session hosts (RAM, user density) and rebalance the host pool
- Establish a reboot cadence for multi-session hosts
- Update Windows, FSLogix, and third-party filter drivers; investigate pool usage with poolmon if recurring

*Source:* [https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-) (community-observed)

### Code 0x80070003 - HRESULT_ERROR_PATH_NOT_FOUND

**Meaning:** HRESULT-wrapped 'The system cannot find the path specified' (Win32 error 3 in facility WIN32). Official FSLogix docs show it in profile logs as '[ERROR:80070003] Failed to save installed AppxPackages (The system cannot find the path specified.)' - a path expected inside the profile/container is missing.

**Likely causes:**
- Expected folder inside the user profile or container does not exist (e.g. AppX package state location)
- Profile contents incomplete after an earlier failed load

**Fixes / next steps:**
- Often non-fatal - verify whether the user's profile loaded correctly otherwise
- If recurring around AppX operations, review the InstallAppxPackages setting and update FSLogix
- Check the profile container contents for the missing path

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes](https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes) (verified by Microsoft docs)

### Code 0x80070005 - E_ACCESSDENIED

**Meaning:** HRESULT-wrapped 'Access is denied' (decimal 2147942405). Microsoft's archived FSLogix troubleshooting FAQ calls '[ERROR:0x80070005] SHSetKnownFolderPath error (Access is denied.)' the most common exception seen in otherwise healthy Profile/Office logs - usually benign.

**Likely causes:**
- Known-folder redirection call denied for a folder the user/service cannot modify (commonly benign)
- Genuine ACL problems on profile folders or registry keys if the error is widespread and paired with user-visible issues

**Fixes / next steps:**
- Ignore isolated occurrences when the profile loads and functions normally (per Microsoft's FAQ)
- If paired with real symptoms, audit NTFS ACLs on the profile folders and user-hive registry permissions

*Source:* [https://learn.microsoft.com/en-us/archive/msdn-technet-forums/8a495cb9-d025-4b34-a122-e1c387d35a0b](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/8a495cb9-d025-4b34-a122-e1c387d35a0b) (community-observed)

## Event IDs (Microsoft-FSLogix-Apps channels)

Microsoft publishes no complete FSLogix event catalog, and several IDs (26 in
particular) are generic carriers for different messages - always read the
message text, not just the ID. On any host with FSLogix installed you can dump
the authoritative per-version list with:
`(Get-WinEvent -ListProvider 'Microsoft-FSLogix-Apps').Events | Select-Object Id, Description`.

### Event 5 - CLOUDCACHE_PROXY_LOCK (unofficial label; officially documented event)

**Meaning:** Officially documented verification event in Microsoft-FSLogix-CloudCache/Operational: Event ID 5 'shows the lock on the proxy file'. Normal/healthy Cloud Cache operation - the local cache proxy file is locked for the active session. NOTE: this ID exists in the CloudCache channel; do not confuse with IDs in the Apps channels.

**Likely causes:**
- Normal Cloud Cache attach: local cache (C:\\ProgramData\\FSLogix\\Cache\\\<user\>\_\<sid\>) proxy file locked by the active session

**Fixes / next steps:**
- No action - healthy indicator during Cloud Cache verification

*Source:* [https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers](https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers) (verified by Microsoft docs)

### Event 25 - PROFILE_LOAD (unofficial label; no symbolic name documented)

**Meaning:** Informational event in Microsoft-FSLogix-Apps/Operational written when a user profile container is loaded/attached. The rendered description contains parseable fields including 'Username: \<user\>'. Widely used by monitoring solutions (e.g. Log Analytics KQL parsing) as the 'profile load' signal, i.e. the healthy-attach heartbeat. NOT documented per-ID by Microsoft; one Microsoft Q&A answer conversely describes 25 as a 'profile load failure' event when the message contains 'locked', so treat the message text (not the ID alone) as authoritative.

**Likely causes:**
- Normal user sign-in with FSLogix profile container attach (expected, healthy)
- If the message text contains failure/'locked' wording, the load did not complete cleanly (community-reported, unconfirmed)

**Fixes / next steps:**
- No action for normal occurrences - use as a healthy attach/load telemetry signal and parse Username from the event description
- Correlate with the session registry state HKLM\\SOFTWARE\\FSLogix\\Profiles\\Sessions\\\<SID\> (Status=0 and Reason=0 mean container attached successfully) and with Profile\_\*.log 'LoadProfile'/'loadProfile time:' entries
- If message indicates failure, check the embedded Windows error code against FSLogix Status/Error code docs

*Source:* [https://www.cloudsma.com/2020/09/collect-parse-fslogix-event-log/](https://www.cloudsma.com/2020/09/collect-parse-fslogix-event-log/) (community-observed)

### Event 26 - FSLOGIX_APPS_ERROR (generic error event; no symbolic name documented)

**Meaning:** Error-level event in Microsoft-FSLogix-Apps/Operational (Source: Microsoft-FSLogix-Apps). Event ID 26 is a GENERIC error record reused for many different error messages - the message text carries the actual diagnosis. Officially documented examples: 'Failed to get computer's group SIDs' and 'Querying computer's fully qualified distinguished name failed' (two such errors occur at every boot/logon on Entra-joined-only devices and are expected and safe to ignore). Also observed carrying 'The required VHDLocations/CCDLocations setting is not present (One or more arguments are not correct.)' and container detach/unload failure messages. Alert-worthy EXCEPT for the two known benign Entra-only LDAP messages.

**Likely causes:**
- Device is Microsoft Entra joined only (not domain/hybrid joined) so FSLogix app rule set LDAP queries to a Domain Controller fail - benign, expected, all FSLogix versions (Microsoft known issue, state: In progress)
- Missing or malformed VHDLocations/CCDLocations configuration (e.g. a container type enabled without a storage location defined)
- Other runtime errors surfaced by the FSLogix Apps service (message-specific)

**Fixes / next steps:**
- Parse and branch on the event MESSAGE, not just the ID; suppress/ignore the two documented LDAP messages on Entra-only joined hosts
- Verify VHDLocations (or CCDLocations for Cloud Cache) is set for every enabled container type (Profiles and ODFC); remove accidentally-enabled ODFC config with no location
- For unload/detach errors, check for open handles on the VHD(x) and stale sessions; consider CleanupInvalidSessions

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-known-issues](https://learn.microsoft.com/en-us/fslogix/troubleshooting-known-issues) (verified by Microsoft docs)

### Event 33 - VHD_ATTACH_FAILURE (community claim; unconfirmed)

**Meaning:** Claimed by a Microsoft Q&A community answer to indicate a VHD attach failure in Microsoft-FSLogix-Apps/Operational, possibly with 'locked' in the message when the disk is still in use elsewhere. NOT found in any official Microsoft documentation and not corroborated by a second independent source - low confidence; include in a diagnostic tool only as 'possible attach failure, verify message text'.

**Likely causes:**
- Profile VHD(x) still locked/attached by another session host (per the unconfirmed community claim)

**Fixes / next steps:**
- Treat as unverified: read the actual event message and the Profile\_\*.log around the same timestamp
- Check for file locks on the container with Get-SmbOpenFile on the file server and close stale handles/sessions

*Source:* [https://learn.microsoft.com/en-us/answers/questions/5878138/multiple-sessions-for-users-in-avd-fslogix-is-unab](https://learn.microsoft.com/en-us/answers/questions/5878138/multiple-sessions-for-users-in-avd-fslogix-is-unab) (community-observed)

### Event 41 - LOGON_FAILED (unofficial label; no symbolic name documented)

**Meaning:** Error event observed in the FSLogix Apps event log with message pattern: 'SessionId: \<n\>, ErrorCode: \<code\>, Detail: Logon failed, Please check logs and tracelogging and verify that the users disk was detached.' Indicates the FSLogix logon sequence failed for a session - a failure worth alerting on. The embedded ErrorCode is a Windows system error code (e.g. 160 = ERROR\_BAD\_ARGUMENTS). Real-world event text posted on Microsoft Q&A; the ID is not cataloged in official FSLogix docs.

**Likely causes:**
- Container misconfiguration, e.g. Cloud Cache directory set without a primary location, or a container type enabled without any storage location
- User's disk from a previous session not detached, blocking the new logon

**Fixes / next steps:**
- Review FSLogix configuration: ensure VHDLocations or CCDLocations (not both) is correctly defined for every enabled container
- Verify the previous session's container detached (check open handles on the share; sign the user out fully); consider CleanupInvalidSessions
- Decode the ErrorCode as a Windows system error code and check C:\\ProgramData\\FSLogix\\Logs\\Profile for the matching [ERROR:xxxxxxxx] entries

*Source:* [https://learn.microsoft.com/en-us/answers/questions/831552/fslogix-errors-26-and-41-in-event-log](https://learn.microsoft.com/en-us/answers/questions/831552/fslogix-errors-26-and-41-in-event-log) (community-observed)

### Event 51 - CONTAINER_LOCKED_ATTACH_FAILED (unofficial label; no symbolic name documented)

**Meaning:** Event in Microsoft-FSLogix-Apps/Operational generated when FSLogix fails to attach a profile container because it is 'in-use'/locked. The event includes the username, the locked profile path, and the machine currently holding the lock - which makes it the key event for automated locked-profile detection/remediation. Definitely a failure to alert on: the user typically receives 'FSLogix: Logon Failure - The user profile failed to attach' (with PreventLoginWithFailure the sign-in is blocked by frxshell). Community-documented (ControlUp, Nerdio); not cataloged in official Microsoft docs, though Microsoft officially documents the locked-container scenario itself.

**Likely causes:**
- Container still exclusively locked by another (possibly stale/disconnected) session - FSLogix default allows only a single concurrent connection per container
- Previous sign-out did not complete (process/app held the container; abrupt session termination left artifacts)
- User launching multiple desktops/apps against a single-session-configured container

**Fixes / next steps:**
- Identify and close the lock holder: the event names the machine; on the file server use Get-SmbOpenFile / Close-SmbOpenFile or sign the stale session out
- Enable CleanupInvalidSessions to clean stale session artifacts (official recommendation for the locked-container scenario)
- If concurrent access is a business requirement, review official 'Concurrent or multiple connections' concepts before changing ProfileType/VHDAccessMode
- Tune LockedRetryCount/LockedRetryInterval and ReAttachRetryCount/ReAttachIntervalSeconds

*Source:* [https://www.controlup.com/resources/blog/how-to-fix-the-fslogix-issue-the-user-profile-failed-to-attach/](https://www.controlup.com/resources/blog/how-to-fix-the-fslogix-issue-the-user-profile-failed-to-attach/) (community-observed)

### Event 56 - CLOUDCACHE_PROVIDERS_ONLINE (unofficial label; officially documented event)

**Meaning:** Officially documented verification event in Microsoft-FSLogix-CloudCache/Operational: Event ID 56 'shows which providers are online' - one event per CCDLocations provider indicating it is online/healthy. Healthy-state indicator for Cloud Cache configurations; its absence (or provider-offline error events) after user logon is the alert condition.

**Likely causes:**
- Normal Cloud Cache operation: each configured provider (SMB/Azure page blob) registered and online at container attach

**Fixes / next steps:**
- No action - use as the healthy signal that all CCDLocations providers are reachable
- If a provider is missing/offline: verify connection strings (frx-protected for Azure), network reachability, storage permissions; HealthyProvidersRequiredForRegister governs whether logon proceeds with unhealthy providers

*Source:* [https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers](https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers) (verified by Microsoft docs)

### Event 57 - VHD_DISK_COMPACTION_RESULT (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Operational (Provider: Microsoft-FSLogix-Apps). Message: 'Disk was compacted: \<true-or-false\>. Sign out time increased by xx milliseconds. Disk size reduced by xx MB. (VHDPath: \<path\>)'. Structured EventData fields: Path, WasCompacted, MaxSupportedSizeMB, MinSupportedSizeMB, SizeBeforeMB, SizeAfterMB, SavedSpaceMB, TimeSpentMillis (Properties[0..7] via Get-WinEvent). Emitted at user sign-out when VHD Disk Compaction (FSLogix 2210+) evaluates/compacts the container. Informational/telemetry - a healthy detach-phase event; WasCompacted=false is normal when there is not enough recoverable space.

**Likely causes:**
- Normal sign-out with VHDCompactDisk enabled (default in supported versions)
- WasCompacted=false: thresholds not met / not enough recoverable space (also chronic with differencing disks: ProfileType=3 or VHDAccessMode=1/2/3)

**Fixes / next steps:**
- No action needed - use for storage-savings and sign-out-duration metrics (Microsoft publishes ready-made PowerShell and KQL for exactly this event)
- If compaction never runs on differencing-disk configurations, this is a known limitation
- If sign-out delays matter, correlate with Winlogon Event 6006 (services exceeding the 60-second logoff threshold)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

### Event 58 - VOLUME_OPTIMIZATION_FAILED (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Operational. Message: 'Volume optimization failed, Path: \<path\>, Message: \<message\>, ExtendedMessage \<extended-message\>'. The defrag/optimize step of VHD Disk Compaction failed for the container volume. Failure event worth flagging (compaction skipped; disk keeps growing on disk).

**Likely causes:**
- Optimize Drives (defragsvc) or Microsoft Storage Spaces SMP (smphost) service disabled or failing (official errors ERROR:00000422 'defragsvc is disabled' / ERROR:00000102 'Failed to query minimum supported size')
- Volume/filesystem issues inside the container

**Fixes / next steps:**
- Set-Service defragsvc -StartupType Manual; Set-Service smphost -StartupType Manual (Disabled is unsupported for compaction)
- Review Message/ExtendedMessage in the event and the [ERROR: entries in C:\\ProgramData\\FSLogix\\Logs\\Profile

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

### Event 60 - COMPACTION_DEFRAGSVC_DISABLED (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Admin. Message: 'The VHDCompactDisk configuration setting is dependent on the defragsvc service. The service start type is set to disabled. Make sure the service start type is set to Manual or Automatic.' Configuration problem event - alert once per host, fix is deterministic. CAUTION: some community sources wrongly describe Event 60/61 as container mount/dismount-success events; official docs define them as compaction events.

**Likely causes:**
- defragsvc (Optimize Drives) service StartupType set to Disabled by image hardening/optimization tooling (common in VDI golden images)

**Fixes / next steps:**
- Set defragsvc (and smphost) StartupType to Manual or Automatic in the golden image / via policy; the service state (Running/Stopped) does not matter, only StartupType

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

### Event 61 - COMPACTION_FIXED_SIZE_VHD (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Operational. Message: 'This vhd(x) can't be compacted because it has a fixed size. VHD(x) Path: \<path-to-vhd\>'. Informational/expected when containers were created as fixed-size disks; not a failure of the attach/detach path.

**Likely causes:**
- Container VHD(x) created with IsDynamic=0 (fixed size) - compaction only applies to dynamic disks

**Fixes / next steps:**
- No action if fixed-size disks are intentional; otherwise set IsDynamic=1 for new containers or migrate existing containers to dynamic VHDX
- Suppress this ID from alerting where fixed-size disks are policy

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

### Event 62 - COMPACTION_UNABLE (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Admin. Message: 'Unable to compact the disk, Message: \<message\>, Path: \<path\>, ExtendedMessage: \<extended-message\>'. Compaction could not run for this container - warning-grade; investigate if recurring for the same user/path.

**Likely causes:**
- Environmental/service issues (defragsvc/smphost), disk in unexpected state, storage/permission problems - message-specific

**Fixes / next steps:**
- Read Message/ExtendedMessage; verify defragsvc and smphost StartupType; check the container path is reachable and healthy
- Cross-check Profile\_\*.log around sign-out for the corresponding [ERROR:/[WARN: code

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

### Event 63 - COMPACTION_FAILED (unofficial label; officially documented event)

**Meaning:** Officially documented in Microsoft-FSLogix-Apps/Admin. Message: 'Failed during disk compaction, ErrorCode: \<error code\>, VHD(x) Path: \<path\>'. Compaction started but failed mid-operation - alert if recurring; the ErrorCode is a Windows system error code.

**Likely causes:**
- I/O or storage errors against the VHD(x) during compaction; service crash/timeout (compaction is capped at 5 minutes, then sign-out continues)

**Fixes / next steps:**
- Decode ErrorCode via Windows System Error Codes / Error Code Lookup Tool
- Check storage latency/health for the container path; verify container not corrupt (chkdsk against mounted VHDX in maintenance window)

*Source:* [https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction](https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction) (verified by Microsoft docs)

