# Launch an Adobe app with a complete Windows environment, even from a shell that strips variables (Codex).
# Why: CEP (PlugPlug.dll) throws in PlugPlugSetup when CommonProgramFiles / CommonProgramFiles(x86) /
#      CommonProgramW6432 are missing -> After Effects dies with "CEP suite could not be loaded".
# Usage: launch-adobe-fullenv.ps1 -Exe "C:\Program Files\Adobe\Adobe After Effects 2026\Support Files\AfterFX.exe" [-Arguments ...]
# No UI input. Refuses to start a second instance.
param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments)
if (-not [Environment]::Is64BitProcess) { 'VERDICT: FAIL x64-shell-required'; exit 1 }
if (-not (Test-Path -LiteralPath $Exe)) { "VERDICT: FAIL exe not found: $Exe"; exit 1 }
$name = [IO.Path]::GetFileNameWithoutExtension($Exe)
if (Get-Process $name -ErrorAction SilentlyContinue) { "VERDICT: FAIL $name already running - not starting a second one"; exit 1 }

# 1) machine + user variables from the registry (what Explorer would hand a normal app)
foreach ($scope in 'Machine', 'User') {
    $vars = [Environment]::GetEnvironmentVariables($scope)
    foreach ($k in $vars.Keys) {
        if ($k -ieq 'Path') { continue }
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($k))) { Set-Item "Env:$k" $vars[$k] }
    }
}
# 2) variables Windows computes at logon (not stored in the registry environment keys)
$computed = @{
    'CommonProgramFiles'      = [Environment]::GetFolderPath('CommonProgramFiles')
    'CommonProgramFiles(x86)' = [Environment]::GetFolderPath('CommonProgramFilesX86')
    'CommonProgramW6432'      = [Environment]::GetFolderPath('CommonProgramFiles')
    'ProgramFiles'            = [Environment]::GetFolderPath('ProgramFiles')
    'ProgramFiles(x86)'       = [Environment]::GetFolderPath('ProgramFilesX86')
    'ProgramW6432'            = [Environment]::GetFolderPath('ProgramFiles')
    'ProgramData'             = [Environment]::GetFolderPath('CommonApplicationData')
    'ALLUSERSPROFILE'         = [Environment]::GetFolderPath('CommonApplicationData')
    'PUBLIC'                  = (Join-Path (Split-Path ([Environment]::GetFolderPath('UserProfile'))) 'Public')
    'COMPUTERNAME'            = [Environment]::MachineName
    'APPDATA'                 = [Environment]::GetFolderPath('ApplicationData')
    'LOCALAPPDATA'            = [Environment]::GetFolderPath('LocalApplicationData')
    'USERPROFILE'             = [Environment]::GetFolderPath('UserProfile')
}
foreach ($k in $computed.Keys) { if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($k))) { Set-Item "Env:$k" $computed[$k] } }
# 3) drop POSIX locale overrides a sandbox shell may have injected
foreach ($k in 'LANG', 'LC_ALL', 'LC_CTYPE') { if (Test-Path "Env:$k") { Remove-Item "Env:$k" } }

$missing = 'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432' | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }
if ($missing) { "VERDICT: FAIL still missing: $($missing -join ', ')"; exit 1 }

$sp = @{ FilePath = $Exe; WorkingDirectory = (Split-Path $Exe); PassThru = $true; WindowStyle = 'Hidden'; ErrorAction = 'Stop' }
if ($Arguments) {
    # Start-Process joins its array with spaces. Quote each Windows argv value.
    $sp.ArgumentList = ($Arguments | ForEach-Object {
        '"' + ([regex]::Replace($_, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
}
try { $p = Start-Process @sp } catch { 'VERDICT: FAIL start-process'; exit 1 }
"VERDICT: OK started $name pid=$($p.Id) with full environment"
