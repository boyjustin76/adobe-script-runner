#Requires -Version 5.1
# Report names only; never dump credentials from the environment.
$required=@('CommonProgramFiles','CommonProgramFiles(x86)','CommonProgramW6432','ProgramData','ALLUSERSPROFILE','PUBLIC')
$missing=@($required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_,'Process')) })
if($missing.Count){
    Write-Output "VERDICT: FAIL env-missing app=caller pid=$PID missing=$($missing -join ',')"
    Write-Output 'Use launch-adobe-fullenv.ps1 before attaching; configuration edits apply to new agent sessions.'
    exit 1
}
Write-Output "VERDICT: OK env-present app=caller pid=$PID"
exit 0
