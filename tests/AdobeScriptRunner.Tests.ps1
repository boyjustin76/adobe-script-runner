<#
    Runs with no Adobe software installed. Everything that touches an app is behind
    an injectable probe, which is also the reason the module is shaped this way.

    Each test names the failure it prevents. All of them happened.
#>

BeforeAll {
    $module = Join-Path $PSScriptRoot '..\src\AdobeScriptRunner\AdobeScriptRunner.psd1'
    Import-Module $module -Force
}

Describe 'ConvertTo-JsxPath' {
    It 'turns backslashes into forward slashes' {
        # "C:\temp\new.jsx" inside a JavaScript string literal contains a tab and a
        # newline. ExtendScript takes forward slashes on Windows.
        ConvertTo-JsxPath 'C:\temp\new.jsx' | Should -Be 'C:/temp/new.jsx'
    }
    It 'leaves an already-forward path alone' {
        ConvertTo-JsxPath 'C:/temp/x.jsx' | Should -Be 'C:/temp/x.jsx'
    }
}

Describe 'New-BridgeBody' {
    It 'sends a path, never the source' {
        # Escapes are re-processed in transit: a literal \t inside a job string
        # arrived at the target as a tab and executed as one.
        $body = New-BridgeBody -JobPath 'C:\jobs\build.jsx'
        $body | Should -Match 'evalFile'
        $body | Should -Match 'C:/jobs/build\.jsx'
    }
    It 'wraps the call so a thrown error comes back instead of vanishing' {
        New-BridgeBody -JobPath 'C:/a.jsx' | Should -Match 'JOBERR'
    }
}

Describe 'Read-Verdict' {
    It 'finds the verdict line among other output' {
        $text = "loading`r`nVERDICT: OK imported 157 clips`r`ndone"
        Read-Verdict -Text $text | Should -Be 'VERDICT: OK imported 157 clips'
    }
    It 'returns nothing when the job never stated a verdict' {
        # The point of the protocol: a return value is not proof. ExtendScript
        # returns the last expression it evaluated even if the script fell over.
        Read-Verdict -Text "all done!`r`ntrue" | Should -BeNullOrEmpty
    }
    It 'accepts a custom marker' {
        Read-Verdict -Text 'RESULT: OK' -Marker 'RESULT' | Should -Be 'RESULT: OK'
    }
    It 'is not fooled by the word appearing mid-line' {
        Read-Verdict -Text 'the VERDICT: is pending' | Should -BeNullOrEmpty
    }
    It 'survives empty output' {
        Read-Verdict -Text '' | Should -BeNullOrEmpty
    }
}

Describe 'Test-VerdictPassed' {
    It 'passes a plain OK' { Test-VerdictPassed 'VERDICT: OK 12 clips' | Should -BeTrue }
    It 'fails on FAIL'     { Test-VerdictPassed 'VERDICT: FAIL no sequence' | Should -BeFalse }
    It 'fails on JOBERR'   { Test-VerdictPassed 'VERDICT: JOBERR ReferenceError' | Should -BeFalse }
    It 'fails when there is no verdict at all' { Test-VerdictPassed $null | Should -BeFalse }
}

Describe 'Resolve-BridgeHost' {
    BeforeAll {
        # Pester 5+ does not carry Describe-scope variables into It blocks.
        $hosts = @(
            [pscustomobject]@{ Process = 'Photoshop';   ProgId = 'Photoshop.Application';   Exe = 'Photoshop.exe' }
            [pscustomobject]@{ Process = 'Illustrator'; ProgId = 'Illustrator.Application'; Exe = 'Illustrator.exe' }
        )
    }

    It 'prefers a relay that is running and answering' {
        $relay = Resolve-BridgeHost -Hosts $hosts -NoLaunch `
            -GetProcess { param($n) @{ Name = $n } } `
            -TestCom    { param($p) $true }
        $relay.Process | Should -Be 'Photoshop'
    }

    It 'skips a running app that does not answer COM' {
        # Measured: Photoshop sat on a "scratch disks are full" dialog with the disk
        # 95% full. The process existed; COM never replied. Illustrator relayed the
        # same message in 18 seconds.
        $relay = Resolve-BridgeHost -Hosts $hosts -NoLaunch `
            -GetProcess { param($n) @{ Name = $n } } `
            -TestCom    { param($p) $p -eq 'Illustrator.Application' }
        $relay.Process | Should -Be 'Illustrator'
    }

    It 'does not treat a running process as proof on its own' {
        # A closing window still answers Get-Process for a while after it has
        # stopped serving COM.
        $relay = Resolve-BridgeHost -Hosts $hosts -NoLaunch `
            -GetProcess { param($n) @{ Name = $n } } `
            -TestCom    { param($p) $false }
        $relay | Should -BeNullOrEmpty
    }

    It 'returns nothing rather than launching when told not to launch' {
        Resolve-BridgeHost -Hosts $hosts -NoLaunch `
            -GetProcess { param($n) $null } `
            -TestCom    { param($p) $false } | Should -BeNullOrEmpty
    }
}

Describe 'Test-RunnerPreflight' {
    It 'refuses an After Effects job while Premiere is running' {
        # The most confusing failure in this whole area: BridgeTalk routes AE jobs to
        # the AE engine *inside* Premiere. The script runs, reports success, and
        # changes nothing you can see.
        $problems = Test-RunnerPreflight -App 'aftereffects' `
            -RunningProcesses @('Adobe Premiere Pro', 'Photoshop')
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match 'Premiere'
    }
    It 'allows an After Effects job when Premiere is closed' {
        (Test-RunnerPreflight -App 'aftereffects' -RunningProcesses @('Photoshop')).Count | Should -Be 0
    }
    It 'does not block a Premiere job because Premiere is running' {
        (Test-RunnerPreflight -App 'premiere' -RunningProcesses @('Adobe Premiere Pro')).Count | Should -Be 0
    }
}

Describe 'Get-AdobeTarget' {
    It 'maps an app name to its process and BridgeTalk id' {
        (Get-AdobeTarget -App 'premiere').BridgeTalkApp | Should -Be 'premierepro'
        (Get-AdobeTarget -App 'aftereffects').Process   | Should -Be 'AfterFX'
    }
    It 'is case-insensitive' {
        (Get-AdobeTarget -App 'Premiere').Process | Should -Be 'Adobe Premiere Pro'
    }
    It 'names the known apps when given something else' {
        { Get-AdobeTarget -App 'nuke' } | Should -Throw '*Known*'
    }
}

Describe 'Write-JobPointer' {
    BeforeAll {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("asr-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    AfterAll { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'writes UTF-8 with no BOM' {
        # ExtendScript's File.read() hands the BOM back inside the string, and the
        # path it produces does not exist. ASCII is not an option either: real paths
        # here contain non-ASCII characters.
        #
        # The non-ASCII characters are built from code points on purpose. Windows
        # PowerShell 5.1 decodes a .ps1 with no BOM using the machine's ANSI
        # codepage, so a literal here would mean different things on different
        # machines -- which is a trap this very project has been bitten by twice.
        $nonAscii = [string][char]0xC791 + [char]0xC5C5      # Korean, 2 chars
        $jobPath = "C:\$nonAscii\build.jsx"

        $file = Write-JobPointer -WorkDir $dir -JobPath $jobPath
        $bytes = [System.IO.File]::ReadAllBytes($file)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
            Should -BeFalse -Because 'a BOM ends up inside the path ExtendScript reads'
        [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) |
            Should -Be "C:/$nonAscii/build.jsx"
    }
}
