@{
    RootModule        = 'AdobeScriptRunner.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8f2c1d44-5b6e-4a37-9c0e-1a7d2b3f6e90'
    Author            = 'JungChan LEE'
    Copyright         = '(c) 2026 JungChan LEE. MIT.'
    Description       = 'Run ExtendScript inside Adobe Premiere Pro or After Effects from PowerShell, by relaying through Photoshop over BridgeTalk.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-AdobeScript'
        'Get-AdobeTarget'
        'Resolve-BridgeHost'
        'Test-ComResponds'
        'Test-RunnerPreflight'
        'New-BridgeBody'
        'ConvertTo-JsxPath'
        'Write-JobPointer'
        'Read-Verdict'
        'Test-VerdictPassed'
        'Find-AdobeExecutable'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags       = @('Adobe', 'Premiere', 'AfterEffects', 'ExtendScript', 'BridgeTalk', 'Automation', 'Windows')
            LicenseUri = 'https://github.com/boyjustin76/adobe-script-runner/blob/main/LICENSE'
            ProjectUri = 'https://github.com/boyjustin76/adobe-script-runner'
        }
    }
}
