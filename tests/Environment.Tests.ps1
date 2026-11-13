BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/AdobeScriptRunner/AdobeScriptRunner.psd1') -Force
}

Describe 'Static environment fixtures' {
    It 'accepts a complete fixture' {
        $fixture=Get-Content (Join-Path $PSScriptRoot 'fixtures/environment-present.json') -Raw | ConvertFrom-Json
        $map=@{}; foreach($p in $fixture.PSObject.Properties){$map[$p.Name]=$p.Value}
        InModuleScope AdobeScriptRunner -Parameters @{Fixture=$map} {
            param($Fixture)
            Mock Get-AdobeProcessEnvironment { $Fixture }
            (Test-AdobeEnvironment -ProcessId 123 -App fixture).Passed | Should -BeTrue
        }
    }
    It 'detects a single missing variable independently of process creation' {
        $fixture=Get-Content (Join-Path $PSScriptRoot 'fixtures/environment-missing.json') -Raw | ConvertFrom-Json
        $map=@{}; foreach($p in $fixture.PSObject.Properties){$map[$p.Name]=$p.Value}
        InModuleScope AdobeScriptRunner -Parameters @{Fixture=$map} {
            param($Fixture)
            Mock Get-AdobeProcessEnvironment { $Fixture }
            $check=Test-AdobeEnvironment -ProcessId 123 -App fixture
            $check.Passed | Should -BeFalse
            $check.Missing.Count | Should -Be 1
            $check.Missing[0] | Should -Be 'CommonProgramFiles'
        }
    }
    It 'treats whitespace values as missing' {
        InModuleScope AdobeScriptRunner {
            Mock Get-AdobeProcessEnvironment { @{'CommonProgramFiles'=' ';'CommonProgramFiles(x86)'='x';'CommonProgramW6432'='x'} }
            (Test-AdobeEnvironment -ProcessId 123 -App fixture).Passed | Should -BeFalse
        }
    }
}

Describe 'Real dummy process environment (no Adobe)' {
    BeforeAll {
        # Compile a uniquely named, sleeping console app, never an Adobe process.
        $dummy=Join-Path $TestDrive ('envdummy'+[guid]::NewGuid().ToString('N')+'.exe')
        # PowerShell 7 cannot emit a console executable; use the Windows PowerShell
        # compiler in both test hosts. The resulting app only sleeps.
        $build="Add-Type -TypeDefinition 'public class EnvDummy { public static void Main(){System.Threading.Thread.Sleep(120000);} }' -OutputAssembly '"+$dummy.Replace("'","''")+"' -OutputType ConsoleApplication"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($build))
        & (Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe') -NoProfile -EncodedCommand $encoded
        if($LASTEXITCODE -ne 0){throw 'Dummy compilation failed'}
        $children=New-Object System.Collections.ArrayList
        Add-Type -Path (Join-Path $PSScriptRoot 'NativeDummy.cs')
    }
    AfterEach {
        foreach($child in $children){if(-not $child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()};$children.Clear()
    }
    It 'detects all three missing variables in a real child without exposing unrelated secrets' {
        $child=Get-Process -Id ([NativeDummy]::Start((Join-Path ([Environment]::SystemDirectory) 'PING.EXE'),$true)); $null=$children.Add($child)
        Start-Sleep -Milliseconds 200
        $check=Test-AdobeEnvironment -ProcessId $child.Id -App dummy
        (Get-AdobeProcessEnvironment -ProcessId $child.Id).ContainsKey('CommonProgramFiles') | Should -BeFalse -Because 'the child must really lack the variable'
        $check.Passed | Should -BeFalse
        $check.Verdict | Should -Match 'FAIL env-missing.*missing=CommonProgramFiles,CommonProgramFiles\(x86\),CommonProgramW6432$'
        $vars=Get-AdobeProcessEnvironment -ProcessId $child.Id
        $vars.ContainsKey('PRIVATE_TEST_SENTINEL') | Should -BeFalse
        $vars.Count | Should -Be 0
    }
    It 'accepts all three variables and reads them case-insensitively' {
        $child=Get-Process -Id ([NativeDummy]::Start((Join-Path ([Environment]::SystemDirectory) 'PING.EXE'),$false)); $null=$children.Add($child)
        Start-Sleep -Milliseconds 200
        (Test-AdobeEnvironment -ProcessId $child.Id -App dummy).Passed | Should -BeTrue
    }
    It 'fails closed for an invalid process id' {
        (Test-AdobeEnvironment -ProcessId 2147483647 -App dummy).Verdict | Should -Match 'FAIL env-unreadable'
    }
    It 'repairs the child environment and refuses a second instance using the standalone launcher' {
        $saved=[Environment]::GetEnvironmentVariable('CommonProgramFiles')
        try {
            [Environment]::SetEnvironmentVariable('CommonProgramFiles',$null,'Process')
            $lines=Start-AdobeApp -Exe $dummy
            ($lines -join "`n") | Should -Match 'VERDICT: OK started'
            $line=$lines | Where-Object {$_ -match 'pid=(\d+)'} | Select-Object -Last 1
            $null=$line -match 'pid=(\d+)'
            $child=Get-Process -Id ([int]$Matches[1]); $null=$children.Add($child)
            (Test-AdobeEnvironment -ProcessId $child.Id -App dummy).Passed | Should -BeTrue
            [Environment]::GetEnvironmentVariable('CommonProgramFiles') | Should -BeNullOrEmpty
            { Start-AdobeApp -Exe $dummy } | Should -Throw '*launch-failed*'
        } finally { [Environment]::SetEnvironmentVariable('CommonProgramFiles',$saved,'Process') }
    }
}

Describe 'No dispatch when the environment check fails' {
        BeforeEach {
            Mock Start-Job -ModuleName AdobeScriptRunner { throw 'Must not submit a job' }
            Mock Test-ComResponds -ModuleName AdobeScriptRunner { throw 'Must not activate COM' }
            Mock Start-AdobeApp -ModuleName AdobeScriptRunner { throw 'Must not launch' }
        }
        It 'rejects the caller before path writes even with SkipPreflight' {
            Mock Test-AdobeEnvironment -ModuleName AdobeScriptRunner { [pscustomobject]@{Passed=$false;Verdict='VERDICT: FAIL env-missing app=caller';Missing=@('CommonProgramFiles')} }
            { Invoke-AdobeScript -App photoshop -JobPath nonexistent -WorkDir nonexistent -SkipPreflight } | Should -Throw '*env-missing*'
            Should -Invoke Start-Job -ModuleName AdobeScriptRunner -Times 0
        }
        It 'rejects a broken target before doing anything with the job' {
            Mock Get-Process -ModuleName AdobeScriptRunner { [pscustomobject]@{Id=123;ProcessName='Photoshop'} }
            Mock Test-AdobeEnvironment -ModuleName AdobeScriptRunner {param($ProcessId) [pscustomobject]@{Passed=($ProcessId -ne 123);Verdict='VERDICT: FAIL env-missing app=Photoshop';Missing=@()} }
            { Invoke-AdobeScript -App photoshop -JobPath nonexistent -WorkDir nonexistent } | Should -Throw '*env-missing*'
            Should -Invoke Start-Job -ModuleName AdobeScriptRunner -Times 0
        }
        It 'rejects a broken relay before its COM probe' {
            Mock Assert-AdobeEnvironment -ModuleName AdobeScriptRunner {}
            { Resolve-BridgeHost -GetProcess { [pscustomobject]@{Id=123} } -TestEnvironment { throw 'VERDICT: FAIL env-missing app=relay' } } | Should -Throw '*env-missing*'
            Should -Invoke Test-ComResponds -ModuleName AdobeScriptRunner -Times 0
            Should -Invoke Start-AdobeApp -ModuleName AdobeScriptRunner -Times 0
        }
        It 'checks the exported direct entry before launching' {
            Mock Assert-AdobeEnvironment -ModuleName AdobeScriptRunner {throw 'VERDICT: FAIL env-missing app=caller'}
            { Invoke-DirectAfterEffects -JobPath nonexistent -WorkDir nonexistent -SkipPreflight } | Should -Throw '*env-missing*'
            Should -Invoke Start-AdobeApp -ModuleName AdobeScriptRunner -Times 0
        }
}
