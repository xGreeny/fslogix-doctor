@{
    Severity     = @('ParseError', 'Error', 'Warning', 'Information')

    ExcludeRules = @(
        # Findings/reports legitimately aggregate output before emitting.
        'PSUseOutputTypeCorrectly'
    )

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSPlaceOpenBrace      = @{
            Enable     = $true
            OnSameLine = $true
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
    }
}
