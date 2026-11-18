$script:RequiredAdobeEnvironment = @('CommonProgramFiles','CommonProgramFiles(x86)','CommonProgramW6432')

function Get-AdobeProcessEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)
    if (-not ('AdobeScriptRunner.ProcessEnvironment' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'ProcessEnvironment.cs') -ErrorAction Stop
    }
    [AdobeScriptRunner.ProcessEnvironment]::GetRequired($ProcessId)
}

function Test-AdobeEnvironment {
    <# Returns only missing names and a verdict, never an environment dump. #>
    [CmdletBinding()]
    param([int]$ProcessId = $PID, [string]$App = 'caller')
    try {
        if ($ProcessId -eq $PID) { $vars = [Environment]::GetEnvironmentVariables('Process') }
        else { $vars = Get-AdobeProcessEnvironment -ProcessId $ProcessId }
        $missing = @($script:RequiredAdobeEnvironment | Where-Object { [string]::IsNullOrWhiteSpace($vars[$_]) })
        $verdict = if ($missing.Count) { "VERDICT: FAIL env-missing app=$App pid=$ProcessId missing=$($missing -join ',')" }
                   else { "VERDICT: OK env-present app=$App pid=$ProcessId" }
        [pscustomobject]@{Passed=($missing.Count -eq 0); Verdict=$verdict; Missing=$missing}
    } catch {
        # Exception text can contain local paths; do not dump it to public logs.
        [pscustomobject]@{Passed=$false; Verdict="VERDICT: FAIL env-unreadable app=$App pid=$ProcessId"; Missing=@()}
    }
}

function Assert-AdobeEnvironment {
    param([int]$ProcessId=$PID, [string]$App='caller')
    $check = Test-AdobeEnvironment -ProcessId $ProcessId -App $App
    if (-not $check.Passed) {
        throw "$($check.Verdict)`nRelaunch with Start-AdobeApp or scripts/launch-adobe-fullenv.ps1 from a full environment; no job was sent. For env-unreadable, use a same-user, same-integrity x64 shell."
    }
}

function Assert-AdobeRunningEnvironment {
    param([Parameter(Mandatory)][string]$ProcessName)
    foreach ($process in @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
        Assert-AdobeEnvironment -ProcessId $process.Id -App $ProcessName
    }
}

function Start-AdobeApp {
    <# Starts one instance with restored environment; never interacts with its UI. #>
    [CmdletBinding(DefaultParameterSetName='App')]
    param(
        [Parameter(Mandatory,ParameterSetName='App')]
        [ValidateSet('aftereffects','photoshop','illustrator','premiere','ame')][string]$App,
        [Parameter(ParameterSetName='App')][string]$Version,
        [Parameter(Mandatory,ParameterSetName='Exe')][string]$Exe,
        [string[]]$Arguments
    )
    if ($PSCmdlet.ParameterSetName -eq 'App') {
        $names=@{aftereffects='AfterFX.exe';photoshop='Photoshop.exe';illustrator='Illustrator.exe';premiere='Adobe Premiere Pro.exe';ame='Adobe Media Encoder.exe'}
        $root=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Adobe'
        $candidates=@(Get-ChildItem -LiteralPath $root -Filter $names[$App] -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not $Version -or $_.FullName -match ('[\\/][^\\/]*\b'+[regex]::Escape($Version)+'[\\/]') })
        if ($candidates.Count -ne 1) { throw 'VERDICT: FAIL exe-ambiguous-or-missing; use -Exe with an explicit executable path.' }
        $Exe=$candidates[0].FullName
    }
    # Run the standalone launcher in a child shell so its repairs do not mutate
    # the caller. Its duplicate-instance and environment guards are shared.
    $launcher=Join-Path $PSScriptRoot '../../scripts/launch-adobe-fullenv.ps1'
    $shell=Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path $shell)) { $shell=Join-Path $PSHOME 'pwsh.exe' }
    $command="`$ProgressPreference='SilentlyContinue'; & '"+$launcher.Replace("'","''")+"' -Exe '"+$Exe.Replace("'","''")+"'"
    if ($Arguments) {
        $quoted=@($Arguments | ForEach-Object { "'"+$_.Replace("'","''")+"'" })
        $command+=' -Arguments @('+($quoted -join ',')+')'
    }
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    & $shell -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw 'VERDICT: FAIL launch-failed; see launcher verdict.' }
}
