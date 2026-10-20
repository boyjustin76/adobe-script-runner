# adobe-script-runner

**PowerShell 에서 프리미어 프로·애프터이펙트 안으로 스크립트를 넣어 돌립니다.**
두 앱에는 COM 자동화 API 가 없어서 — 포토샵을 거쳐 갑니다.

(영어판: [README.md](README.md))

```powershell
Import-Module .\src\AdobeScriptRunner

$r = Invoke-AdobeScript -App premiere `
                        -JobPath .\examples\hello-premiere.jsx `
                        -WorkDir $env:TEMP\asr

$r.Passed    # True
$r.Verdict   # VERDICT: OK premiere 26.5.2
$r.Relay     # Photoshop
```

## 왜 번거로운가

포토샵·일러스트레이터는 COM 자동화 ProgID 를 등록해서 PowerShell 로 한 줄에 부립니다.
**프리미어와 AE 는 없습니다.** `Premiere.Application` 같은 건 만들 수 없습니다.
보통은 CEP/UXP 패널을 깔거나 화면을 조작하는데, 둘 다 무겁고 빌드에서 못 부릅니다.

그런데 어도비 앱끼리는 전부 **BridgeTalk** 으로 말합니다.

```
PowerShell  --COM-->  포토샵  --BridgeTalk-->  프리미어 / 애프터이펙트
```

포토샵은 우체통입니다. 스크립트를 넘겨 줄 뿐 아무것도 하지 않습니다.

요령은 그게 전부고, 저장소의 나머지는 **그 요령이 통한 뒤에 터지는 열한 가지**입니다.
전부 오류를 안 냅니다.

## 성공처럼 보이는 실패

| 보이는 것 | 실제 |
|---|---|
| AE 스크립트가 "성공", AE 는 그대로 | 프리미어가 떠 있어서 **프리미어 안의 AE 엔진**에서 돌았다 |
| 로컬에선 되는데 중계로는 다르게 돈다 | 잡 소스를 본문에 실어 **이스케이프가 두 번** 처리됐다 (`\t` 가 탭으로 실행) |
| 제한 시간을 다 태우고 아무 말 없음 | 중계 앱이 떠 있지만 **COM 에 답하지 않는다** — 시작 화면이나 대화상자 |
| 70초쯤 뒤 `FAIL TIMEOUT`, 오류는 없음 | AE 가 **충돌 복구 창**에 멈춰 있다 — 직전에 내가 강제 종료해서 띄운 창이다. 잡은 닿지도 못했다 |
| 잡이 통과, 아무 일도 안 일어남 | **반환값은 증거가 아니다** — 삼킨 예외 뒤에도 마지막 식을 돌려준다 |
| 네 번을 고쳤는데 스틸이 그대로 | `saveFrameToPng` 은 **있는 파일을 안 덮어쓴다.** 말도 없다. 1차와 4차 시트가 바이트까지 같았다 |
| 편집은 먹는데 렌더만 안 된다 | `AfterFX.exe -r` 에서는 `saveFrameToPng` 이 **한 장도 안 쓴다** — 중계로는 10/10, `-r` 로는 0/10 |

하나하나 측정값과 함께 **[docs/traps.md](docs/traps.md)** 에 적었습니다.
이 모듈을 안 쓰더라도 그 파일은 읽을 값어치가 있습니다. 시간이 거기 들어갔습니다.

## 실행기가 하는 일

- **프로세스가 아니라 COM 을 찔러 본다.** 떠 있는 건 증거가 아니다 — 닫히는 중인 창도 한동안 `Get-Process` 에 잡힌다
- **다른 중계로 넘어간다.** BridgeTalk 은 누가 보내든 같다. 포토샵이 안 뜨던 날 일러스트레이터가 18초에 날랐다
- **프리미어가 떠 있으면 AE 잡을 거절한다.** 남이 편집 중일 수 있으니 우리가 닫지는 않는다
- **소스가 아니라 경로를 보낸다.** `$.evalFile(new File("..."))`
- **반환값이 아니라 판정 줄로 판단한다**
- **아무것도 클릭하지 않는다.** 빗나간 좌표 클릭이 한 번 엉뚱한 앱을 띄웠다. 막힌 걸 알리고 멈춘다

## 전송로는 둘

기본은 중계입니다. AE 에만 두 번째 길이 있고, 있는 이유는 함정 2 입니다 —
**프리미어가 떠 있으면 중계가 AE 잡을 거절합니다.** BridgeTalk 이 프리미어 안의 AE 엔진으로
보내 버리기 때문입니다. 누가 오후 내내 프리미어로 편집 중이면 그 오후를 통째로 날립니다.

```powershell
Invoke-AdobeScript -App aftereffects -Transport direct `
                   -JobPath .\job.jsx -WorkDir $wd
```

`direct` 는 `AfterFX.exe -r` 로 제 AE 를 띄웁니다. 포토샵도 BridgeTalk 도 COM 도 안 끼고,
어느 엔진이 돌았는지 헷갈릴 일도 없습니다.

| | 중계 (기본) | direct |
|---|---|---|
| 대상 | 프리미어·AE·포토샵·일러스트레이터 | **AE 만** |
| 포토샵/일러스트레이터 필요 | 필요 | 불필요 |
| 프리미어 켜진 채로 | **안 됨** — 일부러 거절 | 됨 |
| 이미 떠 있는 AE 에 | 됨 | **안 됨** — 거절 |
| 프레임 렌더 | 됨 | **안 됨** (함정 13) |
| 차가운 상태 실측 | 16초 | 13초 |

쓰기 전에 둘만 알아 두면 됩니다.

**이미 떠 있는 AE 는 못 몹니다.** `-r` 은 시작 인자라, 두 번째로 띄우면 잡이 말없이
사라질 수 있습니다. 실행기가 검사해서 중계를 쓰라고 말합니다.

**프레임은 못 뽑습니다.** `-r` 에서 `saveFrameToPng` 은 아무것도 안 쓰고 던지지도 않습니다
(0/10, 중계는 10/10). 프레임은 **`aerender`** 로 뽑으세요 — 정식 헤드리스 렌더러이고
프리미어가 켜져 있어도 상관없습니다.

래퍼는 결과를 디스크에 쓴 **뒤에 AE 를 스스로 닫습니다.** 정리정돈이 아니라, 강제 종료된
AE 는 다음 실행 때 복구 창을 띄워 모든 스크립트를 조용히 막기 때문입니다(함정 5).

## 판정 줄

잡은 제 결과를 한 줄로 말합니다.

```javascript
return "VERDICT: OK imported 157 clips";
return "VERDICT: FAIL sequence came back with 0 clips";
```

실행기는 그 줄만 봅니다. 이 규칙을 넣던 날 잡 56개를 세어 보니 **판정 줄을 가진 것이 하나도
없었고**, 몇 개는 몇 주째 아무 일도 안 하면서 "통과" 중이었습니다.

## 깔기

```powershell
git clone https://github.com/boyjustin76/adobe-script-runner
Import-Module .\adobe-script-runner\src\AdobeScriptRunner
```

**필요한 것:** 윈도 · PowerShell 5.1+ · **중계용 포토샵이나 일러스트레이터** · 대상 앱.
전역에 아무것도 안 깔고, `-WorkDir` 로 준 폴더 안에만 씁니다.

## 어디까지 확인했나

- **프리미어 프로**(`app.version` 26.5.2) 윈도 11, 포토샵 경유 — 잡 전달·판정 읽기·보고 파일까지.
  차가운 상태 16초, 더운 상태 0.8초
- **애프터이펙트**(`app.version` 26.5x89) 윈도 11, **두 전송로 다**, 예제가 아니라 실제 잡으로 —
  중계로는 컴포지션 124개짜리 프로젝트를 고쳐 저장(`VERDICT: OK`, 더운 상태 4.6초),
  direct 로는 `examples/hello-aftereffects.jsx` 를 끝까지
  (`VERDICT: OK aftereffects 26.5x89`, 차가운 상태 12.8초, 보고 파일까지, AE 는 스스로 닫힘)
- 함정 문서의 항목은 전부 실제 잡에서 겪고 **잰** 것입니다
- 시험은 **어도비가 하나도 없는** GitHub 윈도 러너에서 돕니다

안 해 본 것: InDesign/Audition · 맥(COM 이 없습니다) · **이미 떠 있는 AE 에 direct** —
실행기가 짐작 대신 거절하는 쪽을 택했고, 그 거절 자체는 *멀쩡히* 떠 있는 AE 로는 안 재 봤습니다

## 라이선스

MIT — [LICENSE](LICENSE)
