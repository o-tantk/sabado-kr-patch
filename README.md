# Sabado 한국어 패치

Windows Steam판 **Sabado**의 비공식 한국어 패치 초안이다. 대상은 App ID `4986750`, Steam build `26402944`, 메뉴 표기 **Full Version 1.0.1**, Unity `6000.0.31f1` / Mono x64이다. 다른 빌드는 원본 해시 검사에서 설치를 거부한다.

영어가 있는 고유 키 **493개**와 추가 UI 문구 **133개**를 번역했다. 추가 UI에는 캐릭터·아이템 이름, 챕터 선택, 상호작용 안내가 포함된다. 대사·목표·튜토리얼 번역은 포함하지만, 모든 장면을 플레이하며 검수한 완성판은 아니다. 실제 확인 범위와 미해결 항목은 [제작·검증 기록](docs/korean-patch.md)에 구분했다.

현재 설치본은 **0.1.2**이다. 실제 화면에서 대사 화자 제이콥, 집어 든 공책, 챕터 목록과 불러오기 메뉴의 한국어 표시를 확인했다. 게임이 글자를 설정하는 순간 번역하고, 색상 태그·복제 번호·수치는 보존한다. 한글 폰트에서도 원래 자막의 외곽선·그림자·색을 유지한다. 0.1.1에서 실제 설치본 제거·원본 230개 파일 해시 검사·재설치를 검증했다. 모든 챕터와 해상도에 대한 검수는 남아 있다.

## 적용 방식과 요구 사항

BepInEx 5.4.23.6 Mono x64와 C# 플러그인이 **English 텍스트 슬롯**을 한국어로 표시한다. 음성 언어는 별도 설정이며 번역하지 않는다. 원본 게임 에셋과 DLL은 수정하지 않는다. Windows의 `C:\Windows\Fonts\malgun.ttf`(맑은 고딕)가 필요하며, 폰트 파일은 배포하지 않는다.

작업 폴더는 `C:\Workspace\sabado-kr-patch`이다. Python 3.13과 이 폴더의 가상 환경을 사용한다. 소스 재빌드에는 Unity Editor에 포함된 Mono C# 컴파일러가 필요하다. 여기서는 이미 설치된 Editor `6000.3.11f1`을 사용했다.

## 소스에서 패키지 만들기

아래 명령은 작업 폴더에서 PowerShell로 실행한다. 기본 게임 경로는 `C:\Program Files (x86)\Steam\steamapps\common\Sabado`이다.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-tools.txt
.\.venv\Scripts\python.exe tools/survey.py
.\.venv\Scripts\python.exe tools/survey_extra.py
.\tools\fetch-deps.ps1
.\tools\build.ps1
.\.venv\Scripts\python.exe tools/patch.py package
.\.venv\Scripts\python.exe tools/check.py
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\tools\test-display.ps1
```

`survey.py`와 `survey_extra.py`는 설치 폴더를 읽기만 하며, 추출 자료는 `local/survey/`와 `local/survey-extra/`에 쓴다. 후자는 아이템 필드, 잡을 수 있는 물체 이름과 추가 UI 후보를 조사한다. 후보를 자동으로 번역하거나 원본에 쓰지 않는다. `fetch-deps.ps1`은 공식 BepInEx 릴리스를 내려받아 고정된 SHA-256을 검사한다. 컴파일러 위치가 다르면 `build.ps1 -Editor "편집기 설치 경로"`를 사용한다. 결과는 `dist/SabadoKorean/`에 생성된다. 위 과정은 이미 이 작업 폴더에서 수행했다.

## 설치·업데이트

1. 게임을 완전히 종료한다.
2. 게임 설치 폴더에 쓸 수 있는 PowerShell에서 다음을 실행한다. `Program Files` 권한이 부족하면 관리자 권한이 필요하다.

```powershell
Set-Location C:\Workspace\sabado-kr-patch
.\.venv\Scripts\python.exe tools/patch.py install
.\.venv\Scripts\python.exe tools/patch.py status
```

3. Steam에서 게임을 실행하고 설정의 텍스트 언어에서 **한국어**를 선택한다. 이전 빌드나 표시 갱신 전에는 **English**로 보일 수 있으며 같은 슬롯이다. 음성 언어는 원하는 기존 언어를 유지한다.

설치 도구는 실행 중인 게임, 호환되지 않는 원본 파일, 다른 모드 로더, 임의로 수정된 기존 패치 파일을 발견하면 중단한다. 덮어쓸 파일을 모두 `local/backups/<UTC시각>/files/`에 먼저 백업하고 `recovery.json`을 만든 뒤 적용한다. 설치 목록은 게임 폴더의 `SabadoKorean.install.json`에 기록한다. 백업과 이 목록은 제거할 때까지 보관한다.

## 제거·복원

게임을 종료한 다음 작업 폴더에서 실행한다.

```powershell
.\.venv\Scripts\python.exe tools/patch.py remove
.\.venv\Scripts\python.exe tools/patch.py status
```

설치 목록과 파일 해시를 검사하고, 설치 전에 존재하던 파일은 해당 백업으로 복원하며 새로 추가한 관리 대상 파일만 삭제한다. BepInEx가 실행 중 만든 로그·캐시·설정과 빈 폴더는 남지만 로더가 제거되므로 패치는 실행되지 않는다. 세이브·게임 설정·Steam 도전 과제는 제거 대상이 아니다.

설치 중 쓰기 실패는 직전 파일 상태로 자동 복구한다. 전원 중단 등으로 자동 복구가 끝나지 않았다면 게임을 종료하고 해당 `recovery.json`의 `before` 목록을 확인한다. `exists: true`인 항목은 같은 백업의 `files/<상대경로>`로 되돌리고, `exists: false`인 항목은 이번 설치로 추가된 파일인지 해시와 목록을 확인한 뒤 제거한다. 업데이트 전 설치 목록은 `previous-manifest.json`에 있다. 변경된 패치 파일 때문에 도구가 중단하면 그 파일을 별도로 보존하고 원인을 확인해야 한다.

## 저장소 범위

직접 작성한 패치 소스, 번역 데이터, 도구, 설정, 문서만 추적한다. `.venv/`, `local/`, `vendor/`, `build/`, `dist/`와 로그는 Git에서 제외한다. 게임 원본·추출 CSV·외부 DLL·시스템 폰트는 커밋하지 않는다. 이 저장소는 완성 바이너리 배포본이 아니며, 원본 리소스는 사용자의 설치본에서 읽는다.
