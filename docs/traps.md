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

**The half that is easy to miss: you create this dialog yourself.** Every force-kill
buys a blocked run later. A session that killed After Effects between jobs — to be
sure the next one started clean — spent the following hour unable to run a single
script, including scripts that had worked twenty minutes earlier. Let the job quit
the app (`app.quit()`); the direct transport's wrapper does exactly that, after the
result is on disk.

**How to tell this apart from a broken script, in one command:** run `aerender` on
any project. It spawns its own After Effects and is untouched by the dialog, so
`aerender` finishing normally while every scripting path is silent places the fault
in the UI layer, not in your job. That one check replaced a long detour into
syntax-checking a script that was fine.

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

## 12. `saveFrameToPng` will not overwrite, and will not tell you

**Symptom:** you change the project, re-run, and the stills look identical. So you
change something bigger. Still identical.

**Cause:** the file already exists. `saveFrameToPng` does not overwrite it, does not
throw, and returns nothing to check.

**How it was proved:** four rounds of "the change isn't landing" ended with a
pixel-level diff of the first and fourth contact sheets. `ImageChops.difference`
returned a bounding box of `None` — not similar, *identical*. The files had not been
written since the first run; every judgement in between was made on a stale image.

**Fix:** delete the target first, then assert the file exists and is non-empty after
the call. An output step that cannot fail loudly will fail quietly instead.

## 13. Under `-r`, After Effects renders nothing — silently

The direct transport (`AfterFX.exe -r job.jsx`) runs scripts fine, but
`saveFrameToPng` writes **no file at all** and raises nothing.

Measured on the same script and the same project: through the relay, 10 of 10 comps
produced a still; through `-r`, 0 of 10, with the instrumentation reporting the
files simply absent.

**Fix:** keep `-r` for scripted edits, and render frames with **`aerender`**, the
supported headless renderer — about 13 s per frame cold, and it runs happily while
somebody is using Premiere. Note that `aerender` ignores the extension on `-output`
unless an output-module template matches: asking for `scene.png` yields `scene.mp4`
on a default install. Either add a PNG output-module template, or render one frame
to video and pull the frame out.

## 14. `toComp()` is an expression method, not a scripting one

`layer.toComp([x, y], t)` is in every expression reference. Call it from
ExtendScript and you get *"function is not defined"*.

This matters because a **parented** layer's `position` is in its parent's
coordinates. Compute a comp-space rectangle from `position`/`anchorPoint`/`scale`
without folding the parent chain and plainly visible elements come back off-screen —
in our project, an avatar sitting mid-frame reported a centre of `(432, −317)`.

**Fix:** walk the chain yourself — apply the layer's own transform, then recurse into
`layer.parent` until there is none. About fifteen lines, and the only way to get a
true on-screen rectangle from a script.

## 15. A job that changes state must not decide from that state

**Symptom:** a re-run of a job that had been correct produced nonsense, and the log
showed source values that existed nowhere in the original file.

**Cause:** an earlier experiment had written throwaway values into the project. The
job classified each colour by reading the project's *current* value, so on the next
run it classified the throwaway values and mis-assigned all 124 of them.

**Fix:** write the reference values to a file **before** the first mutation, and have
the job read its decisions from that file. The job then produces the same result no
matter how many times it has already run — which is also what makes it safe to
iterate on.
