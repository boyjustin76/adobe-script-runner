# adobe-script-runner

**Run a script inside Adobe Premiere Pro or After Effects from PowerShell.**
They have no COM automation API — so we go through Photoshop.

[![tests](https://github.com/boyjustin76/adobe-script-runner/actions/workflows/tests.yml/badge.svg)](https://github.com/boyjustin76/adobe-script-runner/actions/workflows/tests.yml)
[![powershell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://learn.microsoft.com/powershell/)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

```powershell
Import-Module .\src\AdobeScriptRunner

$r = Invoke-AdobeScript -App premiere `
                        -JobPath .\examples\hello-premiere.jsx `
                        -WorkDir $env:TEMP\asr

$r.Passed    # True
$r.Verdict   # VERDICT: OK premiere 26.0.0
$r.Elapsed   # 11.4
$r.Relay     # Photoshop
```

---

## Why this is awkward in the first place

Photoshop and Illustrator register a COM automation ProgID, so PowerShell can drive
them in one line. **Premiere Pro and After Effects do not.** There is no
`Premiere.Application` to create. The usual answers are to install a CEP/UXP panel,
or to drive the GUI — both heavy, and neither scriptable from a build.

But every Adobe app speaks **BridgeTalk** to every other Adobe app. So:

```
PowerShell  --COM-->  Photoshop  --BridgeTalk-->  Premiere Pro / After Effects
```

Photoshop is a postbox. It does nothing with your script except hand it over.

That is the trick. The rest of this repo is the dozen things that go wrong once the
trick works — because none of them raise an error.

## The failures that look like success

| what you see | what is happening |
|---|---|
| AE script "succeeds", AE unchanged | Premiere was open, so BridgeTalk ran it in the **AE engine inside Premiere** |
| works locally, misbehaves through the relay | job source in the message body gets its **escapes processed twice** — a literal `\t` arrived as a tab and executed |
| job burns the whole timeout, says nothing | relay app is running but **not answering COM** — splash screen, or a "scratch disks are full" dialog |
| `FAIL TIMEOUT` after ~70 s, no error anywhere | After Effects is sitting on its **crash-recovery dialog**; your job never arrived |
| job passes, nothing happened | **a return value is not proof** — ExtendScript returns the last expression it evaluated even after a swallowed throw |

Each one is written up with its measurement in **[docs/traps.md](docs/traps.md)**.
Read that file even if you never use this module; it is the part that took the time.

## What the runner does about them

- **Probes COM, not the process list.** A running app proves nothing: a closing
  window still answers `Get-Process` after it has stopped serving COM.
- **Falls back to another relay.** BridgeTalk does not care who sends the message.
  The day Photoshop would not start, Illustrator relayed the same job in 18 seconds.
- **Refuses an AE job while Premiere is open**, and says why. It does not close
  anybody's Premiere — somebody may be editing in it.
- **Sends a path, never source.** `$.evalFile(new File("..."))`, so nothing is
  escaped twice and the message stays small.
- **Judges on a verdict line, not a return value** (see below).
- **Never clicks anything.** Clicking a coordinate on somebody's desktop has to be
  right every time, and it was not: a stray click once brought up an unrelated app.
  The runner reports a blocking dialog and stops.

## The verdict line

Jobs end with one line stating their own result:

```javascript
return "VERDICT: OK imported 157 clips";
// or
return "VERDICT: FAIL sequence came back with 0 clips";
```

The runner reads that line and nothing else. Of 56 jobs audited the day this was
introduced, none had one — and several had been "passing" for weeks while doing
nothing.

Use `-Marker` if you prefer a different word.

## Install

```powershell
git clone https://github.com/boyjustin76/adobe-script-runner
Import-Module .\adobe-script-runner\src\AdobeScriptRunner
```

**Requires:** Windows, PowerShell 5.1 or later, and **Photoshop or Illustrator
installed** to act as the relay — plus whichever app you are targeting. Nothing is
installed globally, and the module writes only inside the `-WorkDir` you pass.

Supported targets: `premiere`, `aftereffects`, plus `photoshop` and `illustrator`
directly (no relay needed for those).

## Writing a job

See [`examples/hello-premiere.jsx`](examples/hello-premiere.jsx). The shape:

1. Do the work in a try/catch per step, so one failure does not hide the rest.
2. Write the detail to a file in the work directory — it survives a timeout, a
   return value does not.
3. Return exactly one `VERDICT:` line.

## The pieces, if you only want one

Everything is exported, and the useful parts are testable on their own:

| | |
|---|---|
| `Resolve-BridgeHost` | pick a relay that actually answers; fall back |
| `New-BridgeBody` | the one-line `evalFile` message |
| `Read-Verdict` / `Test-VerdictPassed` | the verdict protocol |
| `Test-RunnerPreflight` | refuse the Premiere/AE collision |
| `ConvertTo-JsxPath`, `Write-JobPointer` | path and encoding boundaries |
| `src/AdobeScriptRunner/bridge.jsx` | the relay script itself |

## What it does not do

- **No screenshots, no modal-dialog reading.** Capturing an occluded window and
  classifying what the dialog says is a separate problem with its own repo. This
  module reports that something is blocking and stops.
- **No macOS.** The transport is COM.
- **No CEP/UXP panels, no GUI driving.**
- It will not click a dialog for you, and that is on purpose.

## Verified on

- **Premiere Pro** (`app.version` 26.5.2) on Windows 11, relayed through Photoshop:
  job delivered, verdict read, report file written — 16 s from cold, 0.8 s warm.
- The traps in [docs/traps.md](docs/traps.md) were each observed on a real job and
  measured, not inferred.
- The test suite runs on GitHub's Windows runners, which have **no Adobe software at
  all** — so CI proves the logic, and the line above proves the transport.

Not verified: After Effects on this exact module (the relay path is shared with
Premiere and the AE-specific guard is unit-tested, but nobody has run the AE example
end to end yet), InDesign/Audition targets, macOS (there is no COM there).

## Testing

Tests run with **no Adobe software installed** — every app interaction is behind an
injectable probe, which is also why the module is shaped the way it is.

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester -Path tests
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The most valuable contribution is another
trap: a failure that looked like success, with how you proved what it actually was.

## License

MIT — see [LICENSE](LICENSE).

한국어 설명은 [README.ko.md](README.ko.md).
