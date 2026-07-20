@{
    # Known-benign FSLogix log/event message patterns.
    #
    # These messages are logged at ERROR level by FSLogix but are documented or
    # widely observed as harmless noise on otherwise healthy hosts. Matching is
    # wildcard (-like) against the message text with the bracketed prefix blocks
    # stripped; every pattern starts and ends with '*' so it tolerates arbitrary
    # surroundings and localized Windows error text in parentheses (the FSLogix
    # message body itself is always English).
    #
    # A match never hides a finding - it downgrades severity and says why.
    Patterns = @(
        @{
            Pattern = '*Failed to query activity id*'
            Reason  = 'Internal ETW/tracing correlation call of the FSLogix service; cosmetic and seen in bulk on healthy hosts where every session attaches cleanly.'
        }
        @{
            Pattern = '*Import group policy DataStore key failed*'
            Reason  = 'frxsvc imports GPO-based settings from the DataStore registry key; the import fails harmlessly on hosts where FSLogix is configured directly via HKLM\SOFTWARE\FSLogix instead of the ADMX/GPO DataStore.'
        }
        @{
            Pattern = '*Failed to get computer''s group SIDs*'
            Reason  = 'Documented Microsoft known issue on Entra-joined-only devices: app rule set LDAP queries to a Domain Controller fail at every boot/logon; expected and safe to ignore.'
        }
        @{
            Pattern = '*Querying computer''s fully qualified distinguished name failed*'
            Reason  = 'Documented Microsoft known issue on Entra-joined-only devices: app rule set LDAP queries to a Domain Controller fail at every boot/logon; expected and safe to ignore.'
        }
        @{
            Pattern = '*SHSetKnownFolderPath error*'
            Reason  = 'Microsoft''s archived FSLogix troubleshooting FAQ calls this the most common exception in otherwise healthy Profile/Office logs; usually benign.'
        }
    )
}
