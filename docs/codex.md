# Agent shells / Codex — English

An agent shell can filter environment variables before starting child processes.
An installed app can then fail at startup even though launching it manually works.
Do not diagnose an installation or version problem before comparing the environments.

## Launch, then attach

```powershell
.\scripts\Test-AgentEnv.ps1
.\scripts\launch-adobe-fullenv.ps1 -Exe 'C:\Program Files\Adobe\Adobe After Effects 2026\Support Files\AfterFX.exe'
Import-Module .\src\AdobeScriptRunner\AdobeScriptRunner.psd1
# Alternatively, the module finds a unique installed executable:
Start-AdobeApp -App aftereffects -Version 2026
```

Use **one** launcher, not both. An existing instance is refused, not closed or
replaced. If a recovery dialog appears, ask the person to handle it. Never click or
send keys. `VERDICT: OK started` means the process was created, not that its UI,
CEP extensions or scripting permissions are ready. Attach only after it is ready;
the script's own `VERDICT` remains the job's success criterion.

`Start-AdobeApp` supports aftereffects, photoshop, illustrator, premiere and ame.
Multiple installed matches require `-Version` or explicit `-Exe`. This does not
add AME as an Invoke-AdobeScript target.

## Persistent configuration

Merge these keys into your existing `~/.codex/config.toml`; do not create a second
table with the same name. These are examples for a standard Windows installation:
verify the actual paths on your machine.

```toml
[shell_environment_policy.set]
CommonProgramFiles = 'C:\Program Files\Common Files'
"CommonProgramFiles(x86)" = 'C:\Program Files (x86)\Common Files'
CommonProgramW6432 = 'C:\Program Files\Common Files'
ProgramData = 'C:\ProgramData'
ALLUSERSPROFILE = 'C:\ProgramData'
PUBLIC = 'C:\Users\Public'
```

Start a **new agent session** for configuration changes to apply. Until then use
the launcher. Neither editing configuration nor repairing the caller changes the
environment of an already-running app. The launcher fills missing/blank variables
from Windows machine/user settings and known folders, and removes POSIX locale
overrides. It does not change registry environment settings or system PATH.
The module wrapper performs those repairs in a child shell, leaving its caller intact.

## Diagnose before reinstalling

1. Run Test-AgentEnv in the actual calling shell. It checks six names; Invoke checks
   the three CommonProgramFiles variables and refuses to send if any are absent.
2. Compare the manually launched app and the agent-launched app, using their exact
   process IDs. Do this sequentially after the owner safely closes each instance.
   `Test-AdobeEnvironment -ProcessId 1234 -App aftereffects` prints presence verdicts.
   `Get-AdobeProcessEnvironment -ProcessId 1234` returns **only the three required
   variables**, allowing local value comparison. Do not publish user-specific paths.
3. With permission, reproduce A/B on an isolated process: full environment (A),
   only the three suspect variables removed (B). Keep app version and other settings
   constant; compare startup and CEP logs. Do not run this experiment against a
   user's working app. The repository tests use non-Adobe dummy processes.
4. If the blocks cannot be read, stop: `env-unreadable` is not proof of a missing
   variable. Use an x64 same-user shell at the same integrity level. Do not
   elevate or weaken permissions automatically.
5. A full environment does not prove every startup failure is fixed. Investigate
   other causes only after the environment comparison; do not infer the same cause
   for non-Adobe apps without reproducing it.

The native reader supports Windows x64 processes only. It reads the PEB with
NtQueryInformationProcess/ReadProcessMemory; private structure offsets can change
with Windows versions. Read failures and unsupported architectures fail closed.
It never writes process memory or dumps unrelated environment variables.

Sources: [Codex configuration](https://developers.openai.com/codex/config-reference/),
[PEB caveats](https://learn.microsoft.com/en-us/windows/win32/api/winternl/ns-winternl-peb),
[ReadProcessMemory](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-readprocessmemory),
[reported reproduction](https://github.com/boyjustin76/adobe-script-runner/issues/1).

---

# 에이전트 셸 / Codex — 한국어

앱 설치가 정상이어도 에이전트 셸이 자식 프로세스에 필요한 환경변수를 넘기지
않으면 시작 단계에서 실패할 수 있습니다. 재설치·버전 변경을 권하기 전에
사용자가 직접 실행한 앱과 에이전트가 실행한 앱의 환경부터 비교하세요.

- 위 **실행기 중 하나로만** 띄운 뒤 붙습니다. 이미 실행 중이면 새 인스턴스를
  만들지 않으며, 기존 앱을 닫거나 강제로 종료하지 않습니다.
- 복구창은 사용자에게 처리해 달라고 안내합니다. 화면 클릭·키 입력은 하지 않습니다.
- `Start-AdobeApp -App ... [-Version ...]` 또는 `-Exe`로 경로를 지정합니다.
  AME 실행은 지원하지만 Invoke-AdobeScript의 AME 작업 전송을 추가한 것은 아닙니다.
- 위 TOML 예시의 6개 값을 실제 Windows 경로에 맞춰 기존 설정에 병합합니다.
  **새 에이전트 세션부터 적용**되므로 그 전에는 실행기를 사용합니다.
  이미 켜진 앱의 환경은 설정을 고쳐도 바뀌지 않습니다.
- `Test-AgentEnv.ps1`는 현재 셸의 6개 변수 이름을 검사합니다. Invoke는
  CommonProgramFiles 3개가 빠진 호출 셸·대상·중계 앱에서 전송 전에 중단합니다.
- `Test-AdobeEnvironment -ProcessId ...`로 직접 실행/에이전트 실행의 판정을 비교하고,
  필요하면 `Get-AdobeProcessEnvironment`로 **3개 변수만** 로컬에서 대조합니다.
  전체 환경변수나 사용자 경로를 공개 로그에 붙이지 마세요.
- 승인된 격리 시험에서 A=정상 환경, B=의심 변수 3개만 제거로 나누어 시작 결과와
  CEP 로그를 비교합니다. 사용 중인 앱으로 시험하지 않습니다.
- `env-unreadable`이면 권한·프로세스 종료·x64 지원 범위를 확인합니다.
  읽지 못했다는 결과를 변수 누락으로 단정하거나 권한을 자동 변경하지 않습니다.
- `OK started`는 프로세스 생성 성공입니다. 실제 작업 성공은 작업이 출력한
  `VERDICT: OK`로 판단하며, 창이 보인다는 사실만으로 성공 처리하지 않습니다.

현재 검사기는 Windows x64 전용이며 Windows 내부 구조에 의존하므로 버전 변화로
읽지 못할 수 있습니다. 이런 경우 작업을 보내지 않습니다. 이번 확인된 원인을
다른 앱의 모든 시작 실패에 일반화하지 마세요.

If Invoke still reports `app=caller` after Start-AdobeApp, repair the calling shell too (or start a new configured agent session). Start-AdobeApp deliberately repairs only its child; it cannot fix an existing app or silently change the parent shell. Running the standalone `.ps1` in the current PowerShell applies its environment repairs to that shell.

Start-AdobeApp 이후에도 `app=caller`가 실패하면 호출 셸도 고치거나 설정을 적용한 새 에이전트 세션을 시작해야 합니다. 모듈 실행기는 자식 환경만 고칩니다. 단독 `.ps1`을 현재 PowerShell에서 실행하면 해당 셸에 환경 복원이 적용됩니다.
