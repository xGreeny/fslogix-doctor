function New-FslFinding {
    <#
    .SYNOPSIS
        Creates the standardized finding object used by all FSLogixDoctor checks.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object only.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Environment', 'Configuration', 'SessionState', 'LogFile', 'EventLog', 'ProfileStore', 'ContextEvents')]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Info', 'Warning', 'Critical')]
        [string]$Severity,

        [string]$Target = $env:COMPUTERNAME,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Evidence = '',

        [string]$Recommendation = '',

        [string]$HelpUri = ''
    )

    [pscustomobject]@{
        PSTypeName     = 'FSLogixDoctor.Finding'
        Category       = $Category
        Check          = $Check
        Severity       = $Severity
        Target         = $Target
        Message        = $Message
        Evidence       = $Evidence
        Recommendation = $Recommendation
        HelpUri        = $HelpUri
    }
}
