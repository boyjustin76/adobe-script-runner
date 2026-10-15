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
| 70초쯤 뒤 `FAIL TIMEOUT`, 오류는 없음 | AE 가 **충돌 복구 창**에 멈춰 있다. 잡은 닿지도 못했다 |
| 잡이 통과, 아무 일도 안 일어남 | **반환값은 증거가 아니다** — 삼킨 예외 뒤에도 마지막 식을 돌려준다 |

하나하나 측정값과 함께 **[docs/traps.md](docs/traps.md)** 에 적었습니다.
이 모듈을 안 쓰더라도 그 파일은 읽을 값어치가 있습니다. 시간이 거기 들어갔습니다.

## 실행기가 하는 일

- **프로세스가 아니라 COM 을 찔러 본다.** 떠 있는 건 증거가 아니다 — 닫히는 중인 창도 한동안 `Get-Process` 에 잡힌다
- **다른 중계로 넘어간다.** BridgeTalk 은 누가 보내든 같다. 포토샵이 안 뜨던 날 일러스트레이터가 18초에 날랐다
- **프리미어가 떠 있으면 AE 잡을 거절한다.** 남이 편집 중일 수 있으니 우리가 닫지는 않는다
- **소스가 아니라 경로를 보낸다.** `$.evalFile(new File("..."))`
- **반환값이 아니라 판정 줄로 판단한다**
- **아무것도 클릭하지 않는다.** 빗나간 좌표 클릭이 한 번 엉뚱한 앱을 띄웠다. 막힌 걸 알리고 멈춘다

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
- 함정 문서의 항목은 전부 실제 잡에서 겪고 **잰** 것입니다
- 시험은 **어도비가 하나도 없는** GitHub 윈도 러너에서 돕니다

안 해 본 것: 이 모듈로 AE 를 끝까지 돌려 보지는 않았습니다(중계 길은 같고 AE 전용 가드는 단위
시험이 있습니다) · InDesign/Audition · 맥(COM 이 없습니다)

## 라이선스

MIT — [LICENSE](LICENSE)
