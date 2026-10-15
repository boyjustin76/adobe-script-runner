# Contributing

## Running the tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester -Path tests
```

They run with **no Adobe software installed**. Every call into an app sits behind an
injectable probe (`-TestCom`, `-GetProcess`, `-RunningProcesses`), which is why the
module is split the way it is. Keep it that way: a test that needs Creative Cloud is
a test that runs nowhere.

## The most valuable contribution is another trap

[docs/traps.md](docs/traps.md) is the real content of this repository. If you hit a
failure that looked like success, please add it, with:

- **the symptom** — what you saw, in the words you would have searched for
- **what was actually happening**
- **how you proved it** — the measurement, not the theory
- the app versions and the date

A trap without a measurement is a guess, and guesses are what sent us down the wrong
path in the first place.

## Also welcome

- **More targets.** InDesign, Audition and Animate all speak BridgeTalk. Adding one
  is an entry in `$script:Targets` plus whatever turns out to be special about it.
- **Newer or older Creative Cloud versions**, especially if `getSpecifier` behaves
  differently.
- **A relay that is not Photoshop or Illustrator.** Any Adobe app with a COM ProgID
  should work; we have only used those two.

## Design rules

- **Never click anything.** No coordinate clicks, no synthetic keystrokes. A stray
  click once brought an unrelated application to the front, and a tool that moves
  somebody's mouse has to be right every single time. Report and stop instead.
- **Never kill an app the user might be using.** Refuse, explain, offer a switch.
- **Probe capability, not presence.** A running process proves nothing; ask COM a
  question and see if it answers.
- Comments explain the symptom, not the mechanism. Someone reading this code is
  usually mid-incident.
