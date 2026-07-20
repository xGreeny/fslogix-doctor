function Get-FslDataTable {
    <#
    .SYNOPSIS
        Loads and caches one of the module's data tables (Data\*.psd1).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ErrorCodes', 'SessionCodes', 'EventIds', 'BenignPatterns', 'Releases', 'ContextEvents')]
        [string]$Name
    )

    if (-not $script:FslDataCache.ContainsKey($Name)) {
        $path = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Data') -ChildPath ('{0}.psd1' -f $Name)
        $script:FslDataCache[$Name] = Import-PowerShellDataFile -Path $path
    }
    $script:FslDataCache[$Name]
}
