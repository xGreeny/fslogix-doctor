$script:ModuleRoot = $PSScriptRoot
$script:FslDataCache = @{}

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in ($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load function file '$($file.FullName)': $_"
    }
}

Export-ModuleMember -Function $public.BaseName
