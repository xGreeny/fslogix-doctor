# FSLogix Windows event IDs (Microsoft-FSLogix-Apps channels).
# Generated from verified research; regenerate docs with tools/Export-ErrorCodeDoc.ps1.
@{
    '25' = @{
        Name     = 'PROFILE_LOAD (unofficial label; no symbolic name documented)'
        Meaning  = 'Informational event in Microsoft-FSLogix-Apps/Operational written when a user profile container is loaded/attached. The rendered description contains parseable fields including ''Username: <user>''. Widely used by monitoring solutions (e.g. Log Analytics KQL parsing) as the ''profile load'' signal, i.e. the healthy-attach heartbeat. NOT documented per-ID by Microsoft; one Microsoft Q&A answer conversely describes 25 as a ''profile load failure'' event when the message contains ''locked'', so treat the message text (not the ID alone) as authoritative.'
        Causes   = @('Normal user sign-in with FSLogix profile container attach (expected, healthy)', 'If the message text contains failure/''locked'' wording, the load did not complete cleanly (community-reported, unconfirmed)')
        Fixes    = @('No action for normal occurrences - use as a healthy attach/load telemetry signal and parse Username from the event description', 'Correlate with the session registry state HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID> (Status=0 and Reason=0 mean container attached successfully) and with Profile_*.log ''LoadProfile''/''loadProfile time:'' entries', 'If message indicates failure, check the embedded Windows error code against FSLogix Status/Error code docs')
        Source   = 'https://www.cloudsma.com/2020/09/collect-parse-fslogix-event-log/'
        Verified = $false
    }
    '26' = @{
        Name     = 'FSLOGIX_APPS_ERROR (generic error event; no symbolic name documented)'
        Meaning  = 'Error-level event in Microsoft-FSLogix-Apps/Operational (Source: Microsoft-FSLogix-Apps). Event ID 26 is a GENERIC error record reused for many different error messages - the message text carries the actual diagnosis. Officially documented examples: ''Failed to get computer''s group SIDs'' and ''Querying computer''s fully qualified distinguished name failed'' (two such errors occur at every boot/logon on Entra-joined-only devices and are expected and safe to ignore). Also observed carrying ''The required VHDLocations/CCDLocations setting is not present (One or more arguments are not correct.)'' and container detach/unload failure messages. Alert-worthy EXCEPT for the two known benign Entra-only LDAP messages.'
        Causes   = @('Device is Microsoft Entra joined only (not domain/hybrid joined) so FSLogix app rule set LDAP queries to a Domain Controller fail - benign, expected, all FSLogix versions (Microsoft known issue, state: In progress)', 'Missing or malformed VHDLocations/CCDLocations configuration (e.g. a container type enabled without a storage location defined)', 'Other runtime errors surfaced by the FSLogix Apps service (message-specific)')
        Fixes    = @('Parse and branch on the event MESSAGE, not just the ID; suppress/ignore the two documented LDAP messages on Entra-only joined hosts', 'Verify VHDLocations (or CCDLocations for Cloud Cache) is set for every enabled container type (Profiles and ODFC); remove accidentally-enabled ODFC config with no location', 'For unload/detach errors, check for open handles on the VHD(x) and stale sessions; consider CleanupInvalidSessions')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-known-issues'
        Verified = $true
    }
    '33' = @{
        Name     = 'VHD_ATTACH_FAILURE (community claim; unconfirmed)'
        Meaning  = 'Claimed by a Microsoft Q&A community answer to indicate a VHD attach failure in Microsoft-FSLogix-Apps/Operational, possibly with ''locked'' in the message when the disk is still in use elsewhere. NOT found in any official Microsoft documentation and not corroborated by a second independent source - low confidence; include in a diagnostic tool only as ''possible attach failure, verify message text''.'
        Causes   = @('Profile VHD(x) still locked/attached by another session host (per the unconfirmed community claim)')
        Fixes    = @('Treat as unverified: read the actual event message and the Profile_*.log around the same timestamp', 'Check for file locks on the container with Get-SmbOpenFile on the file server and close stale handles/sessions')
        Source   = 'https://learn.microsoft.com/en-us/answers/questions/5878138/multiple-sessions-for-users-in-avd-fslogix-is-unab'
        Verified = $false
    }
    '41' = @{
        Name     = 'LOGON_FAILED (unofficial label; no symbolic name documented)'
        Meaning  = 'Error event observed in the FSLogix Apps event log with message pattern: ''SessionId: <n>, ErrorCode: <code>, Detail: Logon failed, Please check logs and tracelogging and verify that the users disk was detached.'' Indicates the FSLogix logon sequence failed for a session - a failure worth alerting on. The embedded ErrorCode is a Windows system error code (e.g. 160 = ERROR_BAD_ARGUMENTS). Real-world event text posted on Microsoft Q&A; the ID is not cataloged in official FSLogix docs.'
        Causes   = @('Container misconfiguration, e.g. Cloud Cache directory set without a primary location, or a container type enabled without any storage location', 'User''s disk from a previous session not detached, blocking the new logon')
        Fixes    = @('Review FSLogix configuration: ensure VHDLocations or CCDLocations (not both) is correctly defined for every enabled container', 'Verify the previous session''s container detached (check open handles on the share; sign the user out fully); consider CleanupInvalidSessions', 'Decode the ErrorCode as a Windows system error code and check C:\ProgramData\FSLogix\Logs\Profile for the matching [ERROR:xxxxxxxx] entries')
        Source   = 'https://learn.microsoft.com/en-us/answers/questions/831552/fslogix-errors-26-and-41-in-event-log'
        Verified = $false
    }
    '5' = @{
        Name     = 'CLOUDCACHE_PROXY_LOCK (unofficial label; officially documented event)'
        Meaning  = 'Officially documented verification event in Microsoft-FSLogix-CloudCache/Operational: Event ID 5 ''shows the lock on the proxy file''. Normal/healthy Cloud Cache operation - the local cache proxy file is locked for the active session. NOTE: this ID exists in the CloudCache channel; do not confuse with IDs in the Apps channels.'
        Causes   = @('Normal Cloud Cache attach: local cache (C:\ProgramData\FSLogix\Cache\<user>_<sid>) proxy file locked by the active session')
        Fixes    = @('No action - healthy indicator during Cloud Cache verification')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers'
        Verified = $true
    }
    '51' = @{
        Name     = 'CONTAINER_LOCKED_ATTACH_FAILED (unofficial label; no symbolic name documented)'
        Meaning  = 'Event in Microsoft-FSLogix-Apps/Operational generated when FSLogix fails to attach a profile container because it is ''in-use''/locked. The event includes the username, the locked profile path, and the machine currently holding the lock - which makes it the key event for automated locked-profile detection/remediation. Definitely a failure to alert on: the user typically receives ''FSLogix: Logon Failure - The user profile failed to attach'' (with PreventLoginWithFailure the sign-in is blocked by frxshell). Community-documented (ControlUp, Nerdio); not cataloged in official Microsoft docs, though Microsoft officially documents the locked-container scenario itself.'
        Causes   = @('Container still exclusively locked by another (possibly stale/disconnected) session - FSLogix default allows only a single concurrent connection per container', 'Previous sign-out did not complete (process/app held the container; abrupt session termination left artifacts)', 'User launching multiple desktops/apps against a single-session-configured container')
        Fixes    = @('Identify and close the lock holder: the event names the machine; on the file server use Get-SmbOpenFile / Close-SmbOpenFile or sign the stale session out', 'Enable CleanupInvalidSessions to clean stale session artifacts (official recommendation for the locked-container scenario)', 'If concurrent access is a business requirement, review official ''Concurrent or multiple connections'' concepts before changing ProfileType/VHDAccessMode', 'Tune LockedRetryCount/LockedRetryInterval and ReAttachRetryCount/ReAttachIntervalSeconds')
        Source   = 'https://www.controlup.com/resources/blog/how-to-fix-the-fslogix-issue-the-user-profile-failed-to-attach/'
        Verified = $false
    }
    '56' = @{
        Name     = 'CLOUDCACHE_PROVIDERS_ONLINE (unofficial label; officially documented event)'
        Meaning  = 'Officially documented verification event in Microsoft-FSLogix-CloudCache/Operational: Event ID 56 ''shows which providers are online'' - one event per CCDLocations provider indicating it is online/healthy. Healthy-state indicator for Cloud Cache configurations; its absence (or provider-offline error events) after user logon is the alert condition.'
        Causes   = @('Normal Cloud Cache operation: each configured provider (SMB/Azure page blob) registered and online at container attach')
        Fixes    = @('No action - use as the healthy signal that all CCDLocations providers are reachable', 'If a provider is missing/offline: verify connection strings (frx-protected for Azure), network reachability, storage permissions; HealthyProvidersRequiredForRegister governs whether logon proceeds with unhealthy providers')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/tutorial-cloud-cache-containers'
        Verified = $true
    }
    '57' = @{
        Name     = 'VHD_DISK_COMPACTION_RESULT (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Operational (Provider: Microsoft-FSLogix-Apps). Message: ''Disk was compacted: <true-or-false>. Sign out time increased by xx milliseconds. Disk size reduced by xx MB. (VHDPath: <path>)''. Structured EventData fields: Path, WasCompacted, MaxSupportedSizeMB, MinSupportedSizeMB, SizeBeforeMB, SizeAfterMB, SavedSpaceMB, TimeSpentMillis (Properties[0..7] via Get-WinEvent). Emitted at user sign-out when VHD Disk Compaction (FSLogix 2210+) evaluates/compacts the container. Informational/telemetry - a healthy detach-phase event; WasCompacted=false is normal when there is not enough recoverable space.'
        Causes   = @('Normal sign-out with VHDCompactDisk enabled (default in supported versions)', 'WasCompacted=false: thresholds not met / not enough recoverable space (also chronic with differencing disks: ProfileType=3 or VHDAccessMode=1/2/3)')
        Fixes    = @('No action needed - use for storage-savings and sign-out-duration metrics (Microsoft publishes ready-made PowerShell and KQL for exactly this event)', 'If compaction never runs on differencing-disk configurations, this is a known limitation', 'If sign-out delays matter, correlate with Winlogon Event 6006 (services exceeding the 60-second logoff threshold)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
    '58' = @{
        Name     = 'VOLUME_OPTIMIZATION_FAILED (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Operational. Message: ''Volume optimization failed, Path: <path>, Message: <message>, ExtendedMessage <extended-message>''. The defrag/optimize step of VHD Disk Compaction failed for the container volume. Failure event worth flagging (compaction skipped; disk keeps growing on disk).'
        Causes   = @('Optimize Drives (defragsvc) or Microsoft Storage Spaces SMP (smphost) service disabled or failing (official errors ERROR:00000422 ''defragsvc is disabled'' / ERROR:00000102 ''Failed to query minimum supported size'')', 'Volume/filesystem issues inside the container')
        Fixes    = @('Set-Service defragsvc -StartupType Manual; Set-Service smphost -StartupType Manual (Disabled is unsupported for compaction)', 'Review Message/ExtendedMessage in the event and the [ERROR: entries in C:\ProgramData\FSLogix\Logs\Profile')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
    '60' = @{
        Name     = 'COMPACTION_DEFRAGSVC_DISABLED (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Admin. Message: ''The VHDCompactDisk configuration setting is dependent on the defragsvc service. The service start type is set to disabled. Make sure the service start type is set to Manual or Automatic.'' Configuration problem event - alert once per host, fix is deterministic. CAUTION: some community sources wrongly describe Event 60/61 as container mount/dismount-success events; official docs define them as compaction events.'
        Causes   = @('defragsvc (Optimize Drives) service StartupType set to Disabled by image hardening/optimization tooling (common in VDI golden images)')
        Fixes    = @('Set defragsvc (and smphost) StartupType to Manual or Automatic in the golden image / via policy; the service state (Running/Stopped) does not matter, only StartupType')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
    '61' = @{
        Name     = 'COMPACTION_FIXED_SIZE_VHD (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Operational. Message: ''This vhd(x) can''t be compacted because it has a fixed size. VHD(x) Path: <path-to-vhd>''. Informational/expected when containers were created as fixed-size disks; not a failure of the attach/detach path.'
        Causes   = @('Container VHD(x) created with IsDynamic=0 (fixed size) - compaction only applies to dynamic disks')
        Fixes    = @('No action if fixed-size disks are intentional; otherwise set IsDynamic=1 for new containers or migrate existing containers to dynamic VHDX', 'Suppress this ID from alerting where fixed-size disks are policy')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
    '62' = @{
        Name     = 'COMPACTION_UNABLE (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Admin. Message: ''Unable to compact the disk, Message: <message>, Path: <path>, ExtendedMessage: <extended-message>''. Compaction could not run for this container - warning-grade; investigate if recurring for the same user/path.'
        Causes   = @('Environmental/service issues (defragsvc/smphost), disk in unexpected state, storage/permission problems - message-specific')
        Fixes    = @('Read Message/ExtendedMessage; verify defragsvc and smphost StartupType; check the container path is reachable and healthy', 'Cross-check Profile_*.log around sign-out for the corresponding [ERROR:/[WARN: code')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
    '63' = @{
        Name     = 'COMPACTION_FAILED (unofficial label; officially documented event)'
        Meaning  = 'Officially documented in Microsoft-FSLogix-Apps/Admin. Message: ''Failed during disk compaction, ErrorCode: <error code>, VHD(x) Path: <path>''. Compaction started but failed mid-operation - alert if recurring; the ErrorCode is a Windows system error code.'
        Causes   = @('I/O or storage errors against the VHD(x) during compaction; service crash/timeout (compaction is capped at 5 minutes, then sign-out continues)')
        Fixes    = @('Decode ErrorCode via Windows System Error Codes / Error Code Lookup Tool', 'Check storage latency/health for the container path; verify container not corrupt (chkdsk against mounted VHDX in maintenance window)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $true
    }
}
