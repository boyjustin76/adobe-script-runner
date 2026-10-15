#Requires -Version 5.1
<#
    Run an ExtendScript job inside Adobe Premiere Pro or After Effects from PowerShell.

    Premiere and After Effects expose no COM automation ProgID on Windows, so you
    cannot drive them the way you drive Photoshop. They do speak BridgeTalk, and
    Photoshop does have a ProgID -- so Photoshop becomes a relay:

        PowerShell --COM--> Photoshop --BridgeTalk--> Premiere / After Effects

    See docs/traps.md for what each guard in here is protecting you from. Every one
    of them cost a day.
#>

Set-StrictMode -Version Latest

# Apps that can host the relay, in preference order. Any Adobe app with a ProgID
# will do -- BridgeTalk does not care who sends the message.
$script:BridgeHosts = @(
    [pscustomobject]@{ Process = 'Photoshop';   ProgId = 'Photoshop.Application';   Exe = 'Photoshop.exe' }
    [pscustomobject]@{ Process = 'Illustrator'; ProgId = 'Illustrator.Application'; Exe = 'Illustrator.exe' }
)

# Target apps, by the name you pass to Invoke-AdobeScript.
$script:Targets = @{
    'premiere'      = [pscustomobject]@{ Process = 'Adobe Premiere Pro'; BridgeTalkApp = 'premierepro' }
    'aftereffects'  = [pscustomobject]@{ Process = 'AfterFX';            BridgeTalkApp = 'aftereffects' }
    'photoshop'     = [pscustomobject]@{ Process = 'Photoshop';          BridgeTalkApp = 'photoshop' }
    'illustrator'   = [pscustomobject]@{ Process = 'Illustrator';        BridgeTalkApp = 'illustrator' }
}


function Get-AdobeTarget {
    <#
    .SYNOPSIS
        Look up the process name and BridgeTalk app id for a supported target.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$App)

    $key = $App.ToLowerInvariant()
    if (-not $script:Targets.ContainsKey($key)) {
        throw "Unknown app '$App'. Known: $($script:Targets.Keys -join ', ')"
    }
    $script:Targets[$key]
}


function Test-ComResponds {
    <#
    .SYNOPSIS
        Can we actually talk to this ProgID right now?
    .DESCRIPTION
        Not "is the process running" -- a running app can be stuck on a splash screen
        or a modal dialog and never answer COM. Asking for .Version is the cheapest
        question that proves the automation surface is alive.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProgId)

    try {
        $com = New-Object -ComObject $ProgId
        $null = $com.Version
        return $true
    } catch {
        return $false
    }
}


function Resolve-BridgeHost {
    <#
    .SYNOPSIS
        Pick an Adobe app to relay the BridgeTalk message through.
    .DESCRIPTION
        Order of attempts:
          1. a host that is already running AND answering COM
          2. launch one and wait for COM to answer
          3. the next host in the list

        Step 3 is not paranoia. Photoshop refused to start one day because the disk
        was 95% full -- it sat on a "scratch disks are full" dialog, COM never
        answered, and the job burned its whole timeout. Illustrator relayed the same
        message in 18 seconds.

        Note what step 1 checks. A *window* is not proof: a closing window answers
        Get-Process for a while after it has stopped serving COM.
    .PARAMETER TestCom
        Injectable probe, for tests. Defaults to the real COM check.
    .PARAMETER GetProcess
        Injectable process lookup, for tests.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Hosts = $script:BridgeHosts,
        [scriptblock]$TestCom,
        [scriptblock]$GetProcess,
        [int]$LaunchTimeoutSec = 120,
        [switch]$NoLaunch
    )

    if (-not $TestCom)    { $TestCom    = { param($p) Test-ComResponds -ProgId $p } }
    if (-not $GetProcess) { $GetProcess = { param($n) Get-Process -Name $n -ErrorAction SilentlyContinue } }

    foreach ($h in $Hosts) {
        $running = & $GetProcess $h.Process
        if ($running -and (& $TestCom $h.ProgId)) {
            Write-Verbose "relay: $($h.Process) (already running)"
            return $h
        }
    }
    if ($NoLaunch) { return $null }

    foreach ($h in $Hosts) {
        $exe = Find-AdobeExecutable -FileName $h.Exe
        if (-not $exe) { continue }
        if (-not (& $GetProcess $h.Process)) { Start-Process $exe | Out-Null }
        $deadline = (Get-Date).AddSeconds($LaunchTimeoutSec)
        do {
            Start-Sleep -Seconds 3
            $ready = & $TestCom $h.ProgId
        } until ($ready -or (Get-Date) -gt $deadline)
        if ($ready) {
            Write-Verbose "relay: $($h.Process) (launched)"
            return $h
        }
        Write-Warning "$($h.Process) is not answering COM - trying the next relay. Check the screen for a dialog."
    }
    throw ("No Adobe app could relay the message (none answered COM). " +
           "Look at the screen: a modal dialog on the relay app is the usual cause.")
}


function Find-AdobeExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$Root = "$env:ProgramFiles\Adobe"
    )
    if (-not (Test-Path $Root)) { return $null }
    $hit = Get-ChildItem $Root -Directory -Recurse -Depth 3 -Filter $FileName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $hit) {
        $hit = Get-ChildItem $Root -Recurse -Filter $FileName -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($hit) { $hit.FullName } else { $null }
}


function Test-RunnerPreflight {
    <#
    .SYNOPSIS
        Reasons not to start, given what is running. Returns a list of strings; empty
        means go.
    .DESCRIPTION
        One rule, and it is the single most confusing failure in this whole area:

        **If Premiere Pro is running, BridgeTalk sends After Effects jobs to the
        After Effects engine *inside Premiere*, not to the After Effects
        application.** Your script runs. It reports success. It changes nothing you
        can see, because it ran somewhere else.

        We do not close anybody's Premiere; somebody may be editing in it. We refuse
        and say why.
    .PARAMETER RunningProcesses
        Process names currently running. Injectable for tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$App,
        [string[]]$RunningProcesses
    )

    if ($null -eq $RunningProcesses) {
        $RunningProcesses = @(Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName)
    }
    $problems = @()
    if ($App.ToLowerInvariant() -eq 'aftereffects' -and ($RunningProcesses -contains 'Adobe Premiere Pro')) {
        $problems += ("Premiere Pro is running. BridgeTalk would send this job to the After Effects " +
                      "engine inside Premiere, where it will appear to succeed and change nothing. " +
                      "Close Premiere and run again.")
    }
    , $problems
}


function New-BridgeBody {
    <#
    .SYNOPSIS
        The one line of ExtendScript the relay sends to the target app.
    .DESCRIPTION
        It says "read this file and run it" -- it does **not** carry the job source.

        Putting the source in the message body looks simpler and is a trap: escapes
        are processed again in transit. We watched a literal "\t" inside a job string
        arrive at Premiere as a tab character and execute as one. Sending a path
        avoids the whole class of problem, and keeps the message small enough that
        BridgeTalk size limits never come up.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$JobPath)

    $forward = ConvertTo-JsxPath $JobPath
    'var __r; try { __r = $.evalFile(new File("' + $forward + '")); }' +
    ' catch (e) { __r = "JOBERR " + e.toString() + " @line " + e.line; } __r;'
}


function ConvertTo-JsxPath {
    <#
    .SYNOPSIS
        Windows path -> a path safe to embed in an ExtendScript string literal.
    .DESCRIPTION
        Backslashes are escape characters in JavaScript strings, so "C:\temp\new.jsx"
        contains a tab and a newline. ExtendScript accepts forward slashes on Windows.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $Path -replace '\\', '/'
}


function Write-JobPointer {
    <#
    .SYNOPSIS
        Write the job path where bridge.jsx will look for it.
    .DESCRIPTION
        UTF-8 **without** a BOM, deliberately. ExtendScript's File.read() hands the
        BOM back as part of the string, and the resulting path does not exist.
        ASCII is not an option either: these paths contain non-ASCII characters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$JobPath
    )
    $file = Join-Path $WorkDir '_job.txt'
    [System.IO.File]::WriteAllText($file, (ConvertTo-JsxPath $JobPath),
                                   (New-Object System.Text.UTF8Encoding($false)))
    $file
}


function Read-Verdict {
    <#
    .SYNOPSIS
        Find the job's verdict line in its output. Returns the line, or $null.
    .DESCRIPTION
        **A return value is not proof that a job worked.** ExtendScript will happily
        return the last expression it evaluated from a script that fell over three
        lines earlier, and BridgeTalk will report that as a successful round trip.

        So a job states its own result on a line of its own:

            VERDICT: OK imported 157 clips
            VERDICT: FAIL sequence had 0 clips

        The runner trusts that line and nothing else.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Marker = 'VERDICT'
    )

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^$([regex]::Escape($Marker))\s*:") { return $trimmed }
    }
    return $null
}


function Test-VerdictPassed {
    <#
    .SYNOPSIS
        Does this verdict line report success?
    #>
    [CmdletBinding()]
    param([AllowNull()][string]$Verdict)
    if (-not $Verdict) { return $false }
    if ($Verdict -match '(?i)\b(FAIL|ERROR|JOBERR)\b') { return $false }
    return $true
}


function Invoke-AdobeScript {
    <#
    .SYNOPSIS
        Run an ExtendScript file inside Premiere Pro or After Effects.
    .EXAMPLE
        Invoke-AdobeScript -App premiere -JobPath .\examples\hello-premiere.jsx -WorkDir $env:TEMP
    .OUTPUTS
        A result object: Passed, Verdict, Elapsed, Relay, TimedOut, Output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('premiere', 'aftereffects', 'photoshop', 'illustrator')]
        [string]$App,
        [Parameter(Mandatory)][string]$JobPath,
        [Parameter(Mandatory)][string]$WorkDir,
        [int]$TimeoutSec = 300,
        [string]$Marker = 'VERDICT',
        [switch]$SkipPreflight
    )

    if (-not (Test-Path $JobPath)) { throw "Job not found: $JobPath" }
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
    $JobPath = (Resolve-Path $JobPath).Path
    $WorkDir = (Resolve-Path $WorkDir).Path
    $target  = Get-AdobeTarget -App $App

    if (-not $SkipPreflight) {
        foreach ($problem in (Test-RunnerPreflight -App $App)) { throw $problem }
    }

    $resultFile = Join-Path $WorkDir '_result.txt'
    Remove-Item $resultFile -Force -ErrorAction SilentlyContinue

    $direct = $App -in @('photoshop', 'illustrator')
    if ($direct) {
        $relay = $script:BridgeHosts | Where-Object { $_.Process -eq $target.Process } | Select-Object -First 1
        $scriptToRun = $JobPath
    } else {
        $relay = Resolve-BridgeHost
        Write-JobPointer -WorkDir $WorkDir -JobPath $JobPath | Out-Null
        Set-Content -Path (Join-Path $WorkDir '_target.txt') -Value $target.BridgeTalkApp -Encoding UTF8
        # Run a copy of the relay script from the work directory, so that "the folder
        # I am in" tells bridge.jsx where to find _job.txt and where to leave the
        # result. DoJavaScriptFile cannot pass arguments.
        $scriptToRun = Join-Path $WorkDir 'bridge.jsx'
        Copy-Item (Join-Path $PSScriptRoot 'bridge.jsx') $scriptToRun -Force
    }

    # Run in a background job so a hung app cannot hang this session. COM calls are
    # not cancellable: if the app wedges, the only exit is the timeout.
    $worker = {
        param($progId, $scriptPath)
        $app = New-Object -ComObject $progId
        if ($progId -like 'Photoshop*') { $app.DisplayDialogs = 3 }   # psDisplayNoDialogs
        [pscustomobject]@{ Version = $app.Version; Result = $app.DoJavaScriptFile($scriptPath) }
    }
    $started = Get-Date
    $handle = Start-Job -ScriptBlock $worker -ArgumentList @($relay.ProgId, $scriptToRun)
    $finished = Wait-Job $handle -Timeout $TimeoutSec
    # Measure here. Remove-Job -Force waits on a COM-blocked job -- we have seen a
    # 45-second limit produce a 165-second wall clock.
    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $timedOut = ($null -eq $finished)

    $output = $null
    if (-not $timedOut) {
        $output = Receive-Job $handle -ErrorAction SilentlyContinue
        Remove-Job $handle -Force -ErrorAction SilentlyContinue
    }

    $logText = ''
    if (Test-Path $resultFile) { $logText = Get-Content $resultFile -Raw -Encoding UTF8 }
    if ($output -and $output.Result) { $logText += "`n" + [string]$output.Result }

    $verdict = Read-Verdict -Text $logText -Marker $Marker
    [pscustomobject]@{
        App       = $App
        Passed    = (-not $timedOut) -and (Test-VerdictPassed $verdict)
        Verdict   = $verdict
        TimedOut  = $timedOut
        Elapsed   = $elapsed
        Relay     = $relay.Process
        Output    = $logText
        ResultFile = $resultFile
    }
}


Export-ModuleMember -Function @(
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
