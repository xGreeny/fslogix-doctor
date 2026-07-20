# Win32/FSLogix error codes as they appear in FSLogix logs and the per-session Error value.
# Generated from verified research; regenerate docs with tools/Export-ErrorCodeDoc.ps1.
@{
    '0x00000002' = @{
        Name     = 'ERROR_FILE_NOT_FOUND'
        Meaning  = 'The system cannot find the file specified. In FSLogix logs this is usually the container VHD/VHDX not found at the expected path, e.g. ''Failed to query size of VHD(x)''. Benign as a WARN at a user''s first sign-in (container not created yet); an ERROR if an existing container is expected but missing.'
        Causes   = @('First sign-in for the user (no container exists yet - normal)', 'VHDLocations points to the wrong folder, or folder/file naming settings (FlipFlopProfileDirectoryName, SIDDirNamePattern, VHDNamePattern) changed after containers were created', 'Container was deleted, moved or renamed on the share')
        Fixes    = @('Ignore if it is the user''s first logon and a container is then created', 'Verify VHDLocations and naming-pattern settings match the actual folder/file layout on the share', 'Confirm the user''s Profile_*.vhdx exists at the expected UNC path (browse it as the user)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    '0x00000003' = @{
        Name     = 'ERROR_PATH_NOT_FOUND'
        Meaning  = 'The system cannot find the path specified. The share may be reachable but the directory path (or a local path) does not exist. Microsoft''s FSLogix docs show the HRESULT-wrapped form 0x80070003 of this same code in profile logs.'
        Causes   = @('Typo or stale entry in VHDLocations/CCDLocations', 'Per-user subfolder missing and FSLogix lacks permission to create directories', 'Unexpanded/undefined environment variable inside a configured path')
        Fixes    = @('Validate VHDLocations/CCDLocations values (REG_SZ, semicolon-delimited for multiple entries) per the Microsoft old/temp/local-profiles troubleshooting article', 'Test the exact UNC path from the session host', 'Grant the create-folder NTFS rights required by the Microsoft SMB storage permissions how-to')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-'
        Verified = $false
    }
    '0x00000005' = @{
        Name     = 'ERROR_ACCESS_DENIED'
        Meaning  = 'Access is denied. The most common FSLogix attach failure: FSLogix could not open/create/attach the container or remove a directory because the user or computer identity lacks permissions, or the file is locked. Official docs show log lines such as ''Attach vhd(x) failed, file is locked... (Access is denied.)'' and ''Failed to attach VHD. (Access is denied.)''.'
        Causes   = @('Missing/incorrect NTFS ACLs or SMB share permissions on the container share', 'Azure Files: user/group missing the ''Storage File Data SMB Share Contributor'' RBAC role', 'Container file locked by another process while retrying attach', 'Antivirus/EDR blocking VHD(X) access', 'Wrong identity used against storage (e.g. Entra-joined hosts without proper Kerberos/AccessNetworkAsComputerObject configuration)')
        Fixes    = @('Configure permissions exactly per Microsoft''s ''Configure SMB Storage Permissions'' how-to', 'Azure Files: assign Storage File Data SMB Share Contributor (Elevated Contributor for admins) and re-check NTFS ACLs', 'Add AV exclusions for %ProgramFiles%\FSLogix and *.vhd/*.vhdx per Microsoft guidance', 'Test by browsing the share and creating a folder as the affected user')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    '0x00000013' = @{
        Name     = 'ERROR_WRITE_PROTECT'
        Meaning  = 'The media is write protected. The profile container attaches read-only or fails to attach because a policy denies write access to non-BitLocker-protected fixed drives (the mounted VHD is seen as an unprotected fixed drive).'
        Causes   = @('''Deny write access to fixed drives not protected by BitLocker'' enforced via Intune, Defender, or GPO', 'Container deliberately attached read-only (VHDAccessMode/ProfileType read-only settings)')
        Fixes    = @('Exclude session hosts from the BitLocker deny-write policy (Intune/Defender/GPO) as described by Nerdio''s mount-error guide', 'Review VHDAccessMode/ProfileType if read-only behavior is unexpected')
        Source   = 'https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors'
        Verified = $false
    }
    '0x0000001F' = @{
        Name     = 'ERROR_GEN_FAILURE'
        Meaning  = 'A device attached to the system is not functioning. Low-level failure of the virtual-disk stack while attaching the VHD(X); the profile fails to attach and the user typically gets a temp profile.'
        Causes   = @('Microsoft Virtual Disk (virtdisk) driver not fully installed/initialized on a freshly provisioned VDI image (works after a reboot or delay)', 'Corrupted VHDX', 'Underlying storage/driver fault')
        Fixes    = @('Reboot the session host; if it recurs on fresh provisions, warm up/reboot images before first logon', 'Update FSLogix to the latest release', 'Test-mount the container manually (Mount-VHD / frx) and run chkdsk inside it', 'Check System event log for disk/virtdisk errors')
        Source   = 'https://learn.microsoft.com/en-us/answers/questions/250546/fslogix-vhdx-not-attaching-on-first-login'
        Verified = $false
    }
    '0x00000020' = @{
        Name     = 'ERROR_SHARING_VIOLATION'
        Meaning  = 'The process cannot access the file because it is being used by another process. In FSLogix: the container VHD(X) is already open - the profile is attached in another session, or a stale/orphaned SMB handle from a crashed session still holds the file. Frequently seen in the per-session registry as Error=0x00000020 with Status 0x0000000C (ERROR_ATTACH_VHD).'
        Causes   = @('User signed in on another session host with the same container (default config allows only one connection)', 'Previous session crashed / VM force-restarted so the handle was never released', 'Orphaned file handle or lease on Azure Files / file server', 'Backup or antivirus holding the VHD(X) open')
        Fixes    = @('Check for and sign out other sessions (qwinsta, host pool user sessions)', 'Close open handles: Windows file server via Computer Management > Shared Folders > Open Files; Azure Files via portal/Az PowerShell (Close-AzStorageFileHandle) per Microsoft''s FSLogix open-file-handles article', 'Restart the VM that still holds the lock', 'Add AV/backup exclusions for VHD(X) files', 'If multi-session access is a business need, evaluate FSLogix concurrent-connections (differencing disk) configuration')
        Source   = 'https://learn.microsoft.com/en-us/answers/questions/1625025/fixing-error-code-0x00000020-when-logging-into-dev'
        Verified = $false
    }
    '0x00000021' = @{
        Name     = 'ERROR_LOCK_VIOLATION'
        Meaning  = 'The process cannot access the file because another process has locked a portion of the file. FSLogix failed to obtain its exclusive byte-range lock on the container: the profile is in use on another computer. Official docs show ''ErrorCode set to 33'' and ''LoadProfile failed... FrxStatus: 33'' for this scenario.'
        Causes   = @('Same profile container mounted by an active session on a different host', 'Stale lock from a session that did not sign out cleanly')
        Fixes    = @('Sign the user out of the original session before connecting elsewhere', 'Close orphaned SMB handles on the storage backend', 'Decide policy: allow temp profile, enable PreventLoginWithTempProfile, or configure multiple/concurrent connections per Microsoft''s concepts-multi-concurrent-connections article')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    '0x00000035' = @{
        Name     = 'ERROR_BAD_NETPATH'
        Meaning  = 'The network path was not found. The session host cannot reach the SMB endpoint hosting VHDLocations at all (network/DNS/port-level failure), so no container can be found or created.'
        Causes   = @('TCP port 445 outbound blocked (ISP, NSG, firewall)', 'DNS cannot resolve the file server / storage account FQDN (common with Azure private endpoints)', 'File server or storage account offline', 'NTLMv1-only client configuration (Azure Files requires NTLMv2/Kerberos)')
        Fixes    = @('Test-NetConnection <server> -Port 445 from the session host', 'Verify DNS resolution (private endpoint DNS zones for Azure Files)', 'Check NSG/firewall rules and run the AzFileDiagnostics tool per Microsoft''s Azure Files SMB troubleshooting doc', 'Confirm VHDLocations hostname is correct')
        Source   = 'https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity'
        Verified = $true
    }
    '0x00000040' = @{
        Name     = 'ERROR_NETNAME_DELETED'
        Meaning  = 'The specified network name is no longer available. The established SMB session to the container storage dropped while the container was attached or being attached - users may freeze, lose their session, or the container may be corrupted on repeated occurrences.'
        Causes   = @('Network instability / packet loss between session hosts and storage', 'Storage failover or maintenance closing SMB sessions', 'Storage throttling or an overloaded file server dropping connections')
        Fixes    = @('Check Microsoft-Windows-SMBClient event logs at matching timestamps', 'Review storage availability/throttling metrics (Azure Files transactions, IOPS caps)', 'Use SMB Continuous Availability capable storage (Premium Azure Files, ANF) or FSLogix Cloud Cache for resilience', 'Validate NIC/network path health')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-'
        Verified = $false
    }
    '0x00000043' = @{
        Name     = 'ERROR_BAD_NET_NAME'
        Meaning  = 'The network name cannot be found. The server responds but the share name in VHDLocations cannot be resolved - classic ''System error 67''. Documented by Microsoft for Azure file share mounts and reported in FSLogix profile creation cases (e.g. AVD on Azure Stack HCI).'
        Causes   = @('Misspelled share name in VHDLocations', 'File share does not exist (never created, or deleted)', 'SMB namespace/share path cannot be resolved even though the endpoint is reachable', 'Port 445 partially blocked')
        Fixes    = @('Verify the share exists and the exact spelling of \\server\share in VHDLocations', 'Browse the UNC from a session host on the same network', 'Check storage account network access restrictions (''Selected networks'' rules)', 'Follow the Error 53/67/87 section of Microsoft''s Azure Files SMB troubleshooting doc')
        Source   = 'https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity'
        Verified = $true
    }
    '0x00000047' = @{
        Name     = 'ERROR_REQ_NOT_ACCEP'
        Meaning  = 'No more connections can be made to this remote computer at this time because there are already as many connections as the computer can accept. Only the first N users get their containers mounted; later logons fail.'
        Causes   = @('Containers hosted on a client-SKU Windows machine (20 concurrent SMB connection limit)', 'NAS appliance with per-license SMB connection limits', 'File server at its configured session limit')
        Fixes    = @('Host containers on server-class or scalable storage (Windows Server file share, Azure Files, Azure NetApp Files)', 'Increase the NAS SMB connection/license limit', 'Distribute users across multiple shares if the backend cannot scale')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-'
        Verified = $false
    }
    '0x00000057' = @{
        Name     = 'ERROR_INVALID_PARAMETER'
        Meaning  = 'The parameter is incorrect. Seen when mounting the share or attaching the disk fails due to an invalid parameter - Microsoft documents ''System error 87'' for Azure file share mounts (commonly NTLMv1 clients); in FSLogix logs it can also indicate malformed configuration values.'
        Causes   = @('NTLMv1 enabled on the client (LmCompatibilityLevel < 3) against Azure Files', 'Invalid FSLogix registry values (wrong type/range, e.g. SizeInMBs)', 'Corrupt VHD metadata passed to the virtual disk API')
        Fixes    = @('Set HKLM\SYSTEM\CurrentControlSet\Control\Lsa\LmCompatibilityLevel to 3 or higher', 'Validate FSLogix registry value types against the Microsoft configuration settings reference', 'Recreate or repair the container if VHD metadata is damaged')
        Source   = 'https://learn.microsoft.com/en-us/troubleshoot/azure/azure-storage/files/connectivity/files-troubleshoot-smb-connectivity'
        Verified = $true
    }
    '0x00000070' = @{
        Name     = 'ERROR_DISK_FULL'
        Meaning  = 'There is not enough space on the disk. Either the storage backing VHDLocations is full (containers cannot be created or expanded) or the dynamically expanding container hit its maximum size. Microsoft documents storage-capacity exhaustion as a cause of temp/local profiles, hung sessions, and failed mounts/detaches.'
        Causes   = @('Azure Files share quota reached', 'File server volume out of space', 'Container reached its SizeInMBs maximum (disk full *inside* the VHD)')
        Fixes    = @('Increase the file share quota / expand the volume; monitor capacity per Microsoft''s storage-space guidance', 'Enable/verify VHD disk compaction (VHDCompactDisk) and clean container content with redirections.xml exclusions', 'Raise SizeInMBs if containers legitimately need more space (new size applies to dynamic disks)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $false
    }
    '0x00000079' = @{
        Name     = 'ERROR_SEM_TIMEOUT'
        Meaning  = 'The semaphore timeout period has expired. An SMB/storage operation (usually AttachVirtualDisk) timed out - the classic signature of a slow, congested, or lossy path to the container storage. Logged as ''ErrorCode set to 121'' / ''Failed to attach VHD (The semaphore timeout period has expired.)''.'
        Causes   = @('Network latency or packet loss to the file server / storage account', 'Storage throttling (Azure Files standard IOPS/burst limits) or overloaded file server', 'Antivirus scanning large VHD(X) files during attach', 'NIC/SMB multichannel or RSS misconfiguration')
        Fixes    = @('Check storage latency and throttling metrics; move to Premium Azure Files or scale the file server if saturated', 'Validate the network path (latency, MTU, drops) between hosts and storage', 'Add AV exclusions for VHD/VHDX and FSLogix processes', 'Stagger logon storms; review concurrent attach volume per host')
        Source   = 'https://learn.microsoft.com/en-us/answers/questions/521937/fslogix-semaphore-timeout'
        Verified = $false
    }
    '0x0000007B' = @{
        Name     = 'ERROR_INVALID_NAME'
        Meaning  = 'The filename, directory name, or volume label syntax is incorrect. FSLogix cannot parse a configured path - typically a syntactically malformed VHDLocations/CCDLocations or naming-pattern value.'
        Causes   = @('Quotes, trailing spaces/semicolons, or illegal characters inside the VHDLocations REG_SZ value', 'Environment variable in the path that does not exist at service time (profile attach happens before the shell defines user variables)', 'Bad VHDNamePattern/VHDNameMatch tokens')
        Fixes    = @('Re-enter VHDLocations without surrounding quotes; separate multiple paths with semicolons only', 'Use only variables that exist in the SYSTEM context at logon', 'Verify naming pattern settings against the Microsoft configuration settings reference')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-'
        Verified = $false
    }
    '0x00000091' = @{
        Name     = 'ERROR_DIR_NOT_EMPTY'
        Meaning  = 'The directory is not empty. Cleanup of a directory failed - most often FSLogix removing the local_%username% staging folder, a mount-point directory, or a leftover local profile at sign-out/sign-in. Usually a WARN and retried at next logon.'
        Causes   = @('Files inside the folder still open (antivirus, search indexer, backup agent)', 'Leftover data from a crashed session', 'Third-party agents writing into the profile path during logoff')
        Fixes    = @('Generally benign if occasional; FSLogix retries the cleanup at next logon', 'If persistent, identify the process holding files open and add AV/indexer exclusions', 'Reboot the host to clear stuck handles; remove stale local_* folders during maintenance')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-'
        Verified = $false
    }
    '0x000000A7' = @{
        Name     = 'ERROR_LOCK_FAILED'
        Meaning  = 'Unable to lock a region of a file. FSLogix''s ''AcquireExclusiveLock'' operation on the container failed - the profile is in use on another computer. Official docs show ''[ERROR:000000a7] Operation AcquireExclusiveLock failed. Retrying...'' followed by Status 1 (cannot load profile) and ErrorCode 33.'
        Causes   = @('Active session using the same container on another host', 'Stale SMB handle/lease still holding the previous lock')
        Fixes    = @('Sign the user out of their other session(s)', 'Close orphaned file handles on the storage backend (see Microsoft''s FSLogix open-file-handles article)', 'Consider concurrent-connection (differencing disk) configuration if simultaneous sessions are required')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    '0x000000B7' = @{
        Name     = 'ERROR_ALREADY_EXISTS'
        Meaning  = 'Cannot create a file when that file already exists. FSLogix tried to create a folder/file that is already present - official docs show ''[ERROR:000000b7] No Create access: \\server\share\user-SID... (Cannot create a file when that file already exists.)'' followed by LoadProfile failed.'
        Causes   = @('Leftover/orphaned profile directory or local_%username% folder from an earlier failed logon', 'Duplicate SID-named folder on the share (e.g. after SID history or username change)', 'Race condition between two hosts creating the same profile folder')
        Fixes    = @('Remove or rename the stale conflicting folder on the share (after backing it up)', 'Clean up leftover local_* staging folders on the session host', 'Ensure only one naming convention (FlipFlopProfileDirectoryName etc.) is in effect across all hosts')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    '0x00000428' = @{
        Name     = 'ERROR_EXCEPTION_IN_SERVICE'
        Meaning  = 'An exception occurred in the service when handling the control request. In FSLogix logs this is usually a *trailing* error on ''LoadProfile failed'' lines - the frxsvc service hit an exception after an earlier root-cause error; also matches known frxsvc crash bugs that give users temp profiles.'
        Causes   = @('A preceding error a few lines earlier in the Profile log is the real cause (per Nerdio''s guidance)', 'frxsvc.exe crash bugs in specific releases (e.g. FSLogix 2210 InstallAppxPackages crash, fixed in later versions)')
        Fixes    = @('Search the Profile log upward for the first [ERROR:...] entry before this one and diagnose that code instead', 'Update FSLogix to the latest release', 'Collect logs with the FSLogix Support Tool and open a support case if it persists')
        Source   = 'https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors'
        Verified = $false
    }
    '0x0000045D' = @{
        Name     = 'ERROR_IO_DEVICE'
        Meaning  = 'The request could not be performed because of an I/O device error. Read/write against the mounted container or the underlying SMB channel failed at device level - possible container corruption or storage-side fault.'
        Causes   = @('Network drops during heavy container I/O', 'Storage hardware or filesystem faults on the backend', 'Corrupted VHD(X) after an unclean detach/power loss')
        Fixes    = @('Mount the container manually and run chkdsk against the volume inside it', 'Check backend storage health and SMB client/server event logs', 'Restore the container from backup if corrupt', 'Consider Cloud Cache for redundancy against storage faults')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-'
        Verified = $false
    }
    '0x0000048F' = @{
        Name     = 'ERROR_DEVICE_NOT_CONNECTED'
        Meaning  = 'The device is not connected. Per Nerdio''s FSLogix mount-error guide, in practice this commonly surfaces when the Azure file share''s size limit/quota has been reached (writes to the ''device'' fail), or when the SMB connection dropped during attach.'
        Causes   = @('File share quota/size limit reached', 'Transient SMB disconnect between host and storage during the operation')
        Fixes    = @('Increase the file share size quota', 'Check storage capacity and connection metrics', 'Retry the logon after capacity/connectivity is restored')
        Source   = 'https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors'
        Verified = $false
    }
    '0x000004C3' = @{
        Name     = 'ERROR_SESSION_CREDENTIAL_CONFLICT'
        Meaning  = 'Multiple connections to a server or shared resource by the same user, using more than one user name, are not allowed. Windows already has an SMB session to the storage host under different credentials, so FSLogix''s connection attempt is rejected.'
        Causes   = @('cmdkey/Credential Manager entry with the storage account key (common Entra ID-joined workaround) conflicting with the user/computer Kerberos identity', 'Mapped drive or script mounting the same server as a different user', 'Mixed authentication paths to the same storage account from one host')
        Fixes    = @('Remove conflicting stored credentials and mappings (cmdkey /delete, net use \\server /delete)', 'Standardize on a single authentication method per host for the container share', 'Avoid user drive mappings to the same file server that hosts FSLogix containers')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1000-1299-'
        Verified = $false
    }
    '0x000004F1' = @{
        Name     = 'ERROR_DOWNGRADE_DETECTED'
        Meaning  = 'The system cannot contact a domain controller to service the authentication request. Kerberos authentication to the container share failed because no DC (or Entra Kerberos endpoint) could service the request - a frequent Azure Files + AVD failure.'
        Causes   = @('Domain controller unreachable (VNet DNS not pointing at DCs, DC offline)', 'Entra ID-joined-only hosts missing Cloud Kerberos configuration (CloudKerberosTicketRetrievalEnabled, credential key registry settings) for the storage account', 'Storage account Kerberos/AD object misconfigured', 'Conditional Access interfering with the storage service principal')
        Fixes    = @('Verify DC reachability and VNet DNS settings; test with nltest/klist', 'For Entra ID-joined: follow Microsoft''s ''Use Azure Files with Entra ID'' guidance (enable Entra Kerberos, set required session-host registry keys, exclude the storage app from CA policies)', 'Re-register/repair the storage account''s AD or Entra Kerberos configuration', 'Re-image or redeploy session hosts after changing these settings (per Nerdio)')
        Source   = 'https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors'
        Verified = $false
    }
    '0x0000052E' = @{
        Name     = 'ERROR_LOGON_FAILURE'
        Meaning  = 'The user name or password is incorrect. Authentication to the container share failed - official FSLogix docs show ''[ERROR:0000052e] FindFile failed for path: \\server\share\...Profile*.VHDX (The user name or password is incorrect.)'' with ''ErrorCode set to 1326'', leading to Status 27 (cannot find virtual disk).'
        Causes   = @('Azure Files identity-based auth misconfigured (AD DS/Entra Kerberos not enabled or broken on the storage account)', 'Expired or rotated storage account key still stored via cmdkey', 'Storage account''s AD computer object password/kerb keys out of sync', 'Time skew breaking Kerberos')
        Fixes    = @('Re-validate storage authentication: re-run the AzFilesHybrid join / rotate kerb keys, or update stored credentials', 'Follow Microsoft''s ''Configure SMB Storage Permissions'' and Azure Files identity-auth docs', 'Check time synchronization on hosts and DCs', 'Test share access interactively as the affected user')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-old-temp-local-profiles'
        Verified = $true
    }
    '0x0000052F' = @{
        Name     = 'ERROR_ACCOUNT_RESTRICTION'
        Meaning  = 'Account restrictions are preventing this user from signing in (blank passwords not allowed, sign-in times limited, or a policy restriction enforced). With Azure Files + Entra Kerberos this classically means Conditional Access/MFA is being applied to the storage account''s service principal, blocking the Kerberos ticket for the share.'
        Causes   = @('Storage account app registration not excluded from Conditional Access/MFA policies (Cloud Kerberos deployments)', 'Logon-hours or other account restrictions on the user', 'Policy restriction on the authenticating identity')
        Fixes    = @('Exclude the storage account''s app registration from all Conditional Access policies (disable MFA for it) per Microsoft''s Entra Kerberos guidance', 'Review account restrictions (logon hours, workstation restrictions) for the user')
        Source   = 'https://nmehelp.getnerdio.com/hc/en-us/articles/26124310088205-Troubleshoot-FSLogix-Profile-Mount-Errors'
        Verified = $false
    }
    '0x000005AA' = @{
        Name     = 'ERROR_NO_SYSTEM_RESOURCES'
        Meaning  = 'Insufficient system resources exist to complete the requested service. The session host ran out of kernel resources (paged/non-paged pool, memory) while attaching containers or servicing container I/O - typically on densely loaded multi-session hosts.'
        Causes   = @('Memory/pool exhaustion on heavily loaded session hosts', 'Many simultaneously mounted containers plus memory-hungry workloads', 'Handle or pool leaks from drivers/agents')
        Fixes    = @('Right-size session hosts (RAM, user density) and rebalance the host pool', 'Establish a reboot cadence for multi-session hosts', 'Update Windows, FSLogix, and third-party filter drivers; investigate pool usage with poolmon if recurring')
        Source   = 'https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-'
        Verified = $false
    }
    '0x0000A418' = @{
        Name     = 'STORAGE_SHRINK_VOLUME_ERRORS (unofficial label; Storage Management ErrCode 42008)'
        Meaning  = 'Storage Management result 42008 (hex 0xA418): ''Cannot shrink a partition containing a volume with errors''. Observed in Profile logs during VHD Disk Compaction when FSLogix queries the minimum supported size at sign-out (log line: ''SupportedSize ExtendedStatus: ... (ErrCode:42008 -> Cannot shrink a partition containing a volume with errors.)''). The NTFS volume INSIDE the user''s container has filesystem errors, so the shrink evaluation refuses and compaction is skipped. Attach/detach is unaffected, but filesystem errors inside a profile container deserve a maintenance check - and the disk keeps growing until repaired.'
        Causes   = @('Filesystem corruption / dirty NTFS volume inside the user''s VHD(X), typically after an abrupt detach (host crash, hard session teardown, storage hiccup)', 'Chronic recurrence: the same container fails the shrink evaluation at every sign-out until the volume is repaired')
        Fixes    = @('Identify the affected user/container from the surrounding Profile_*.log lines (same session and timestamp)', 'In a maintenance window with the user signed out: mount the VHDX (Mount-VHD) and run chkdsk /f against the contained volume, then unmount', 'Verify at the next sign-out that event 57 reports WasCompacted=true and the 42008 line is gone', 'If it recurs across many containers, investigate storage-level causes (latency, crashes, antivirus interference on *.vhdx)')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-vhd-disk-compaction'
        Verified = $false
    }
    '0x80070003' = @{
        Name     = 'HRESULT_ERROR_PATH_NOT_FOUND'
        Meaning  = 'HRESULT-wrapped ''The system cannot find the path specified'' (Win32 error 3 in facility WIN32). Official FSLogix docs show it in profile logs as ''[ERROR:80070003] Failed to save installed AppxPackages (The system cannot find the path specified.)'' - a path expected inside the profile/container is missing.'
        Causes   = @('Expected folder inside the user profile or container does not exist (e.g. AppX package state location)', 'Profile contents incomplete after an earlier failed load')
        Fixes    = @('Often non-fatal - verify whether the user''s profile loaded correctly otherwise', 'If recurring around AppX operations, review the InstallAppxPackages setting and update FSLogix', 'Check the profile container contents for the missing path')
        Source   = 'https://learn.microsoft.com/en-us/fslogix/troubleshooting-error-codes'
        Verified = $true
    }
    '0x80070005' = @{
        Name     = 'E_ACCESSDENIED'
        Meaning  = 'HRESULT-wrapped ''Access is denied'' (decimal 2147942405). Microsoft''s archived FSLogix troubleshooting FAQ calls ''[ERROR:0x80070005] SHSetKnownFolderPath error (Access is denied.)'' the most common exception seen in otherwise healthy Profile/Office logs - usually benign.'
        Causes   = @('Known-folder redirection call denied for a folder the user/service cannot modify (commonly benign)', 'Genuine ACL problems on profile folders or registry keys if the error is widespread and paired with user-visible issues')
        Fixes    = @('Ignore isolated occurrences when the profile loads and functions normally (per Microsoft''s FAQ)', 'If paired with real symptoms, audit NTFS ACLs on the profile folders and user-hive registry permissions')
        Source   = 'https://learn.microsoft.com/en-us/archive/msdn-technet-forums/8a495cb9-d025-4b34-a122-e1c387d35a0b'
        # Source is Microsoft-authored but an archived forum FAQ, not product docs.
        Verified = $false
    }
}
