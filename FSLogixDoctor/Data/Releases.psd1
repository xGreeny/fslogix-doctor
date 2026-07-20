@{
    # Curated FSLogix release table - lets the version check give a verdict
    # offline instead of 'compare manually'. The table is a snapshot: AsOf
    # states when it was last updated, and the finding always names that date
    # so an aging table cannot silently pretend to be current.
    #
    # Newest first. Only field-verified or officially documented versions.
    AsOf     = '2026-07-20'
    Releases = @(
        @{
            Version = '3.26.102.18413'
            Notes   = 'Current release line (field-verified June 2026).'
        }
        @{
            Version = '3.25.626.21064'
            Notes   = 'Previous release line (2025); update recommended.'
        }
        @{
            Version = '2.9.8884.27471'
            Notes   = 'FSLogix 2210 hotfix 4 - last release of the legacy 2.9 line; upgrade strongly recommended.'
        }
    )
}
