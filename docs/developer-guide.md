# 개발자 안내 및 기존 README 보관

이 문서는 0.1.3까지의 README 내용을 이관한 기록입니다. 일반 사용자용 최신 설치·제거 안내는 [README](../README.md)를 참고하세요. 아래의 로컬 경로와 Python 명령은 개발 환경 기준입니다.

## 배포판 빌드 (현재 0.1.5)

아래에 보존한 소스 빌드 준비와 원본 조사까지 완료한 개발 환경에서 실행합니다.

```powershell
.\tools\build-release.ps1
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\tests\test-discovery.ps1
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\tests\test-installer.ps1
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\tools\test-display.ps1
```

`dist/SabadoKorean-v0.1.5-windows-x64.zip`과 `dist/SHA256SUMS.txt`를 릴리스에 첨부합니다. 체크섬 파일은 다운로드한 ZIP의 무결성을 수동으로 확인하려는 사용자를 위한 선택 파일이며 설치에 필요하지 않습니다. 일반 사용자 안내에서는 ZIP 다운로드만 안내합니다. ZIP에는 설치·제거·복구 배치 파일, Windows PowerShell 5.1 스크립트, 패키지 해시 목록, 플러그인·번역·편집 이미지·BepInEx, 사용자 설명서, 외부 라이선스와 UnityDoorstop 소스가 들어갑니다. 일반 사용자 PC에서는 Python을 실행하지 않습니다. Python과 Unity Editor는 배포를 만드는 개발 PC에서만 사용합니다.

배포판 설치 코드는 `installer/engine.ps1`, Steam 라이브러리 탐색은 `installer/discovery.ps1`, 창 표시는 `installer/setup.ps1`, ZIP 구성은 `tools/release.py`가 담당합니다. PowerShell 소스에는 5.1의 한글 인식을 위해 UTF-8 BOM을 유지하고, 배치 파일은 ASCII/CRLF로 패키징합니다. 실행 정책 변경은 해당 PowerShell 프로세스의 `Bypass` 옵션에 한정되며 사용자·시스템 정책을 저장하지 않습니다.

설치·업데이트·제거는 쓰기 전에 전체 백업과 복구 기록을 완성합니다. `SabadoKorean.pending.json`이 남은 경우 `복구.bat`가 작업 직전 상태를 복원합니다. 업데이트 시 기존 Python 설치 기록을 읽고, 원래 존재하던 파일의 백업을 새 백업 폴더로 복사합니다. 제거 시 지원 빌드 해시 검사를 다시 강제하지 않으므로 게임 업데이트 후에도 관리 파일이 유지되어 있으면 제거할 수 있습니다.

비대화형 검증은 배포 폴더에서 다음처럼 실행할 수 있습니다. 일반 사용자에게는 배치 파일 사용을 안내합니다. `-BackupRoot`는 테스트나 관리 목적의 선택 사항이며 기본값은 `%LOCALAPPDATA%\SabadoKorean\Backups`입니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer\setup.ps1 -Action Status -Game 'D:\SteamLibrary\steamapps\common\Sabado' -NonInteractive
```

## 보관된 0.1.3 README

# Sabado 한국어 패치

Windows Steam판 **Sabado**의 비공식 한국어 패치 초안이다. 대상은 App ID `4986750`, Steam build `26402944`, 메뉴 표기 **Full Version 1.0.1**, Unity `6000.0.31f1` / Mono x64이다. 다른 빌드는 원본 해시 검사에서 설치를 거부한다.

영어가 있는 고유 키 **493개**와 추가 UI 문구 **133개**를 번역했다. 추가 UI에는 캐릭터·아이템 이름, 챕터 선택, 상호작용 안내가 포함된다. 대사·목표·튜토리얼 번역은 포함하지만, 모든 장면을 플레이하며 검수한 완성판은 아니다. 실제 확인 범위와 미해결 항목은 [제작·검증 기록](development-log.md)에 구분했다.

현재 설치본은 **0.1.3**이다. 문에 붙은 이동 안내 메모와 튜토리얼 그림 속 상호작용·밀기·진정시키기 안내까지 **이미지 4개**를 추가했다. 메모의 한국어 표시·글자 잘림·투명 배경, French 전환 시 원본 복원, 한국어 재선택 시 재적용을 실제 게임에서 확인했다. 튜토리얼 3개는 편집 이미지와 패키지만 확인했으며 실제 튜토리얼 화면 검증은 남아 있다. [이미지 조사·제작 기록과 프롬프트](image-texts.md)를 참고한다.

이전 버전에서 실제 대사 화자 제이콥, 집어 든 공책, 챕터 목록과 불러오기 메뉴를 확인했다. 색상 태그·복제 번호·수치를 보존하고, 한글 폰트에서도 원래 자막의 외곽선·그림자·색을 유지한다. 0.1.3에서 이미지 파일을 포함한 실제 제거·원본 230개 파일 해시 검사·재설치를 검증했다. 모든 챕터와 해상도에 대한 검수는 남아 있다.

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
.\.venv\Scripts\python.exe tools/survey_textures.py
.\tools\fetch-deps.ps1
.\tools\build.ps1
.\.venv\Scripts\python.exe tools/patch.py package
.\.venv\Scripts\python.exe tools/check.py
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\tools\test-display.ps1
```

`survey.py`와 `survey_extra.py`는 설치 폴더를 읽기만 하며, 추출 자료는 `local/survey/`와 `local/survey-extra/`에 쓴다. 후자는 아이템 필드, 잡을 수 있는 물체 이름과 추가 UI 후보를 조사한다. 후보를 자동으로 번역하거나 원본에 쓰지 않는다. `fetch-deps.ps1`은 공식 BepInEx 릴리스를 내려받아 고정된 SHA-256을 검사한다. 컴파일러 위치가 다르면 `build.ps1 -Editor "편집기 설치 경로"`를 사용한다. 결과는 `dist/SabadoKorean/`에 생성된다. 위 과정은 이미 이 작업 폴더에서 수행했다.

`survey_textures.py`는 텍스처 목록과 번역 대상으로 지정된 이미지의 원본을 `local/survey-textures/`에 추출한다. 생성형 편집 결과 PNG는 `assets/textures/`, 번역·매칭 정보는 `translations/textures.json`에 있다. 게임의 `.assets` 파일은 수정하지 않으며, 한국어 선택 시 메모리의 재질·UI 스프라이트 참조만 교체한다. 장면 로드 직후에는 최대 약 1초의 교체 지연이 있을 수 있다. 다른 언어 선택 또는 패치 비활성화 시 원본 참조를 복원한다. 이미지도 같은 설치·제거 절차로 관리된다.

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

직접 작성한 패치 소스, 번역 데이터, 한국어로 편집한 이미지, 도구, 설정, 문서만 추적한다. `.venv/`, `local/`, `vendor/`, `build/`, `dist/`와 로그는 Git에서 제외한다. 게임 원본·추출 CSV·추출 원본 이미지·외부 DLL·시스템 폰트는 커밋하지 않는다. 이 저장소는 완성 바이너리 배포본이 아니며, 원본 리소스는 사용자의 설치본에서 읽는다.
