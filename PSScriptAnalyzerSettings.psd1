@{
    # These are interactive console scripts: Write-Host *is* the user interface, and
    # it is what the recorded demo shows. Everything else uses the default rules.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
}
