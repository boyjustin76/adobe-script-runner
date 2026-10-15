# Traps

Everything here was hit in production and measured. Dates are when it was observed;
versions are what it was observed on (Windows, Creative Cloud 2025–2026).

None of these announce themselves. That is the point — each one costs a day because
the symptom points somewhere else.

---

## 1. Premiere and After Effects have no COM automation ProgID

`New-Object -ComObject Premiere.Application` does not exist. Photoshop and
Illustrator both have one. This is the whole reason for the relay:

```
PowerShell --COM--> Photoshop --BridgeTalk--> Premiere / After Effects
```

Photoshop is a postbox. It does nothing with the message.

## 2. BridgeTalk routes After Effects jobs into Premiere when Premiere is running

**Symptom:** your After Effects script runs. It returns a result. Nothing in After
Effects changed.

**Cause:** Premiere Pro embeds an After Effects engine. When Premiere is running,
`BridgeTalk.getSpecifier("aftereffects")` can resolve to *that* engine, and your
script executes inside Premiere where it can see none of your AE project.

**What the runner does:** refuses to start and says so. It does not close anybody's
Premiere — somebody may be editing in it.

## 3. Do not put the job source in the BridgeTalk message body

**Symptom:** a script that runs fine locally behaves differently through the relay.
We watched a literal `\t` inside a job string arrive at the target as a real tab
character and execute as one.

**Cause:** escapes are processed again in transit.

**Fix:** send `$.evalFile(new File("<path>"))` and let the target read the file off
disk. Side benefit: the message stays tiny, so BridgeTalk size limits never come up.

## 4. A running process is not a working process

**Symptom:** the job burns its entire timeout and reports nothing.

**Cause:** the relay app is up but not serving COM — stuck on a splash screen, or on
a modal dialog. `Get-Process` says it is there. It is not listening.

Seen twice:
- **2025-09-21** — Illustrator killed with `taskkill`, relaunched, froze on the start
  screen. The job sat on it for the full 600 s limit. CPU use rose 4 seconds in five
  minutes, which is how we spotted it.
- **2025-09-28** — the disk was 95% full. Photoshop opened a "scratch disks are full"
  dialog before finishing startup, so COM never answered and the relay script never
  ran. The runner burned 120 s and reported "no verdict".

**Fix:** probe `.Version` over COM. That is the cheapest question that proves the
automation surface is alive. And if the first relay will not answer, **use another
one** — BridgeTalk does not care which Adobe app sends the message. Illustrator
relayed the same job in 18 s that day.

Do not kill the app automatically. Somebody may have just launched it.

## 5. The After Effects crash-recovery dialog blocks everything, invisibly

**Symptom:** `FAIL TIMEOUT` after about 70 seconds, with no error from anywhere.

**Cause:** After Effects that was previously force-closed opens a "crash recovery
options" dialog on next launch. The job never reaches AE; BridgeTalk gives up on its
own after ~70 s.

**What the runner does:** detects it while waiting and stops early rather than
burning the timeout. It does **not** click the button. Clicking at a coordinate hit
the wrong window once and brought a different application to the front; a tool that
moves the mouse on somebody's desktop has to be right every time, and this one
cannot be.

## 6. A return value is not proof of success

**Symptom:** a job "passes" and nothing happened.

**Cause:** ExtendScript returns the last expression it evaluated, even if the script
threw three lines earlier and the error was swallowed. BridgeTalk faithfully reports
that as a successful round trip.

**Fix:** the verdict-line protocol. A job prints exactly one line:

```
VERDICT: OK imported 157 clips
VERDICT: FAIL sequence came back with 0 clips
```

The runner reads that line and nothing else. Of 56 jobs audited on 2025-09-21, none
had one, and several had been "passing" for weeks.

## 7. Capture the failure before you kill the app

**Symptom:** the timeout fires, the runner kills the app, and the screenshot shows an
empty desktop.

**Fix:** screenshot first, kill second. Obvious in hindsight; it was the other way
round for a week.

Related: **a full-screen screenshot does not show an occluded window.** If the modal
is behind something, the capture is worthless. Capture the window itself with
`PrintWindow(PW_RENDERFULLCONTENT)`, which renders a window even when it is covered.

And **delete the previous run's artefacts before starting.** Otherwise a run that
captured nothing shows you the last run's dialog, and you debug a problem you already
fixed.

## 8. Do not take over an app somebody is using

**2025-09-16** — a build was fired at an Illustrator instance a person had open for
their own work. The job opens a 24.7 MB source file and copies items between
documents; it tangled with the open document and the app stopped responding.

The runner checks for open documents in apps where that matters and refuses, with a
`-SkipDocGuard` escape. Photoshop is the exception: leaving a template open there is
normal and makes the second run faster.

## 9. `Remove-Job -Force` waits on a COM-blocked job

**2025-09-21** — a 45-second limit produced a 165-second wall clock, because tearing
down a job that is blocked inside a COM call takes as long as the call does.

**Fix:** measure elapsed time *before* cleaning up, and clean up after the app is
gone. Otherwise your own timeout reporting is wrong.

## 10. Write the job pointer as UTF-8 with no BOM

ExtendScript's `File.read()` returns the BOM as part of the string, so the path you
get back does not exist. ASCII is not an option either when the paths contain
non-ASCII characters — which, outside the English-speaking world, they do.

## 11. Forward slashes in paths inside ExtendScript strings

`"C:\temp\new.jsx"` in a JavaScript string literal contains a tab and a newline.
ExtendScript accepts forward slashes on Windows. Convert once, at the boundary.
