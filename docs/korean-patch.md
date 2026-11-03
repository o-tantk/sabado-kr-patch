# Sabado 한국어 패치 제작 기록

## 대상과 직접 확인한 사실

- 조사일: 2026-11-04 (한국 시간).
- 설치 폴더: `C:\Program Files (x86)\Steam\steamapps\common\Sabado`.
- 작업 폴더: `C:\Workspace\sabado-kr-patch`. 기존 Git 저장소를 사용한다.
- Steam App ID: `4986750`, 설치된 build ID: `26402944`. `appmanifest_4986750.acf`에서 확인했다.
- Unity: `6000.0.31f1`. `UnityPlayer.dll` 버전과 직렬화 파일 헤더에서 확인했다.
- Windows x64 / Mono. PE machine `0x8664`, `MonoBleedingEdge`, `Managed/Assembly-CSharp.dll`을 확인했다.
- 원본 메뉴 좌측 상단 표기는 `Full Version 1.0.1`이다. 런타임 `Application.version`은 `1.0.0`으로 서로 다르므로, 호환성은 Steam build ID와 원본 파일 SHA-256으로 검사한다.

## 텍스트와 폰트 구조

- `Sabado Day One_Data/resources.assets` 안의 TextAsset `localization` (path ID 160)이 CSV이다. 712개 데이터 행, 빈 키를 제외한 고유 키 556개, 마지막 중복 키가 우선하는 기준으로 영어가 있는 키 493개다. 497개라는 초기 숫자는 중복 제거 전의 영어 행 수였다.
- CSV는 `key`와 10개 언어 열을 가진다. 실제 `level1`의 `CSVLocalizationManager` 언어 목록도 English, Filipino, Turkish, French, Chinese, Russian, Ukrainian, Brazilian Portuguese, Spanish LATAM, Spanish Spain이며 한국어는 없다.
- `Assembly-CSharp.dll`의 `CSVLocalizationManager.LoadCSV()`는 `Resources.Load<TextAsset>("localization")`으로 읽는다. `GetText(key)`는 선택한 언어를 반환하며 열이 없을 때 English로 돌아간다.
- `Dialogue1`, `DialogueLine`, `LocalizedText`, `ObjectivePopup`이 번역 키를 사용한다. `DialogueManager`, `LocalizedText`, `ObjectivePopup`에 언어별 TMP 폰트 지정 코드가 있다.
- TextMeshPro와 Febucci TextAnimator 관련 DLL이 있다. TMP 폰트는 `resources.assets`, `sharedassets0~3.assets` 등에서 확인했다. 예: CuteDino, RUBIK, Molot, Anton, Bangers, Oswald, Roboto, LiberationSans. 전체 글리프의 한글 지원 여부는 이름만으로 단정하지 않는다.
- MonoBehaviour의 사용자 정의 데이터는 타입 트리가 생략된 경우가 있어 임의 바이너리 재작성보다 런타임 확장을 우선한다.

## 공식 언어·모드 지원

[Steam 공식 상점](https://store.steampowered.com/app/4986750/Sabado/)은 10개 언어를 명시하며 한국어는 포함하지 않는다. 조사 시점의 상점 기능 목록에 Workshop은 없다. 설치 폴더에서 모드 로더나 공개 모드 SDK는 발견하지 못했다. 이는 공식 모드 지원이 절대 없다는 증거는 아니며, 별도 개발사 문서는 확인되지 않았다.

## 선택한 패치 방식과 이유

BepInEx 5.4.23.6 Mono x64와 직접 작성한 C# 플러그인을 사용한다. `GetText`의 결과를 한국어로 바꾸되 **원래 English 슬롯에서만** 동작한다. 언어의 저장 번호를 바꾸지 않으며 음성 언어를 변경하지 않는다. 언어 메뉴의 English 표시는 한국어로 바꾼다(현재 설치된 이전 시험본은 한국어 (패치)). 나머지 언어는 원래 게임 기능을 사용한다. 원본 `.assets`와 게임 DLL은 수정하지 않는다. 별도 MCP 서버는 필요하지 않았다.

Windows에 설치된 `Fonts/malgun.ttf`를 게임 내 TMP의 파일 경로 생성 함수로 읽어 동적 폰트를 만든다. 시스템 폰트를 복사하거나 배포하지 않는다. 첫 시험에서 OS 폰트 이름을 통한 Unity Font 생성은 TMP 폰트 데이터가 없어 실패했으며, 게임 DLL에서 확인한 내부 파일 경로 생성 함수로 해결했다. 이 내부 API 때문에 TMP DLL 해시도 호환성 검사 대상이다.

번역 자료는 원문 키의 SHA-256과 직접 작성한 한국어만 저장한다. 키 기반 번역 외에 CSV 영어 문구와 짧은 UI 문구의 정확한 일치 치환을 사용한다. 같은 영어에 서로 다른 번역이 있으면 일반 UI 치환은 제외하고 키 기반 대사 번역을 유지한다. 원본 CSV와 게임 DLL은 커밋하지 않는다.

## 첫 시험 결과 (직접 확인)

- 원본 메뉴·설정에서 영어 UI, English 텍스트/음성 선택, 1600×900 창 모드를 확인했다.
- 대표 10개 키로 패키지를 만들어 실제 설치본에서 실행했다.
- 메인 메뉴의 시작·설정·제작진·종료가 한글로 보이며 해당 문구의 깨짐이나 잘림은 발견하지 못했다.
- TMP 사전 글리프 검사: 33자, `complete=True`, 누락 없음.
- 설치/업데이트/제거, 무관한 파일 보존, 수정된 파일 삭제 거부, 다른 빌드 거부, 쓰기 실패 복구, 경로 탈출 거부, 토큰 검사를 7개 단위 테스트로 검증했다.
- 실제 설치 작업의 최초 백업·복구 기록: `local/backups/20261103T152236330913Z/`. 첫 시험은 새 파일 추가이므로 덮어쓴 게임 원본은 없다. 이후 업데이트에서는 기존 플러그인 파일을 백업했다.
- 이 시점에는 전체 대사와 장시간 플레이 검증은 수행하지 않았다.

## 번역 확대

첫 메뉴 시험 성공 후 영어가 있는 고유 키 493개 전체를 번역했다. 메뉴·설정·대사·목표·튜토리얼·안내 문구가 포함된다. `translations/ko.json`에는 원문 키의 SHA-256과 한국어만 저장한다. 원문 영어와 필요한 Filipino 문맥을 참고해 작성한 초안이며, 사람의 전체 문맥 교정은 남아 있다. `translations/glossary.json`에 인명과 용어 기준을 기록했다.

`translations/ui.json`에는 Continue, 품질 단계, 켜짐/꺼짐, Steam 리뷰 안내 등 CSV 외의 추가 UI 문구 11개가 있다. 영어가 비어 있는 고유 키 63개는 번역하지 않았다. 이미지에 그려진 글자, 음성, 모든 동적 문자열을 포괄한다고 주장하지 않는다.

게임의 CSV 파서는 ASCII 큰따옴표를 제거하므로 원본 키와 제거 후 키를 함께 지원한다. 결과는 키 별칭 494개, 정확한 영어 UI 일치 504개이며 서로 다른 번역이 충돌하는 UI 항목은 0개였다. 변수·서식 태그·대괄호 조작 키 27개를 원문과 비교해 보존을 확인했다.

## 확대 시험 결과와 한계

| 항목 | 직접 확인한 결과 |
| --- | --- |
| 실제 게임 메뉴 | 시작·설정·제작진·종료, 새 게임·이어하기가 한국어로 표시됨 |
| 실제 게임 설정 | 게임, 음악/음성 음량, 언어, 음성 언어, 돌아가기 표시 확인. 음성 선택은 English 유지 |
| 리뷰 안내 | 메인 메뉴 하단 두 줄 한국어 안내 확인 |
| 다른 언어 | French 전환 시 원래 프랑스어와 폰트로 돌아가고 한국어 재선택 가능 |
| 한글 글리프 | 확대 시험본 런타임에서 565자 사전 생성, `complete=True`, 누락 없음 |
| 줄바꿈·잘림 | 메뉴와 리뷰 안내는 읽을 수 있었음. 로딩·언어 선택·일부 조작 안내는 overflow 로그가 있어 추가 수정함 |
| 장면 진입 | 새 게임으로 Chapter 1 진입 로그 확인. 캡처는 대부분 흰색으로 보여 실제 대사를 읽거나 플레이 가능 상태를 확인하지 못함 |
| 자동 검사 | 영어 키 493/493, 토큰 27개 보존, 컴파일 성공, 설치·복원 관련 테스트 8/8 통과 |
| 원본 파일 보존 | 최초 조사한 게임 원본 230개 전체 SHA-256 일치, 변경·누락 0개 |

French 선택 중 한국어 옵션에 네모 글자가 나타나고 한국어 전환 직후 폰트 갱신이 늦는 현상을 발견했다. 소스에서는 TMP 텍스트/폰트 설정 시 한글 폰트를 먼저 준비하고 기존 폰트에 fallback을 연결하도록 수정했다. 좁은 UI는 기존 크기의 65%까지 자동 축소하며 다른 언어에서는 기존 레이아웃을 복원한다. 로딩 문구를 짧게 바꾸고 언어 선택 표시를 한국어로 줄였다.

**이 마지막 폰트·레이아웃 수정본은 빌드와 패키징만 완료했고 실제 게임에 적용하거나 화면으로 검증하지 못했다.** 사용자가 실수로 Esc를 눌러 컴퓨터 사용이 중지되었다. 이후 명시적으로 재개를 승인했지만 도구가 다시 중지 상태를 반환해 추가 게임 조작을 하지 않았다. 현재 설치본은 아래 확대 시험본이며 최신 소스와 다르다.

장면 진입 시 Player.log에 `SlimUI.ModernMenu.UIMenuManager.Start`의 NullReferenceException이 있었다. 흰 화면과의 관련성, 원래 게임에서도 발생하는지, 패치 영향인지는 확인하지 못했다. 이전 설치본에는 CuteDino의 한글 글리프 경고도 있었으므로 최신 fallback 수정 후 재검증이 필요하다. 이를 해결됐다고 간주하지 않는다.

## 백업·현재 설치 상태

- 최초 시험: `local/backups/20261103T152236330913Z/`.
- 폰트 생성 방식 수정: `local/backups/20261103T152424699820Z/`.
- 493개 번역 확대 시험, **현재 실제 설치본**: `local/backups/20261103T153126218884Z/`.
- 최초 설치는 24개 로더·플러그인 파일을 추가했으며 게임 원본을 덮어쓰지 않았다. 업데이트는 기존 패치 파일을 모두 백업한 뒤 진행했다.
- 게임 폴더의 `SabadoKorean.install.json`이 설치 파일과 최초 상태를 추적한다. 적용·제거·중단 복구 절차는 [README](../README.md)에 있다.
- 실제 설치본에서 제거 후 재실행하는 검증은 **미수행**이다. 임시 게임 폴더를 사용한 설치·업데이트·제거·재설치 테스트는 통과했다.
- `local/verification/prototype.log`, `expanded-before-final-fixes.log`, `corpus.json`, `final-state.json`에 로컬 검증 근거를 보관한다. 원본 문자열과 로컬 경로가 포함될 수 있어 Git에서는 제외한다.

게임 실행 시험은 게임 설정과 진행 상태를 변경할 수 있다. 새 게임 진입 전에 `HKCU\Software\Kiwi Dreams\Sabado`의 PlayerPrefs를 `local/backups/playerprefs-before-play.reg`로 내보냈다. 시험 중 Chapter 1 진행 기록과 `W_D` 도전 과제 해제 로그가 발생했다. 패치 제거는 이를 되돌리지 않는다. 설정 복원이 꼭 필요하면 게임과 Steam 동기화 상태를 확인하고 현재 설정을 추가 백업한 뒤 이 파일을 검토해야 한다. 레지스트리 복원으로 Steam 도전 과제를 취소할 수는 없다.

## 남은 작업

1. 게임 조작 도구가 정상화되면 게임을 종료하고 최신 패키지를 설치해 폰트 전환·축소·로딩 문구를 재검증한다.
2. 원본 실행과 패치 실행을 비교해 Chapter 1 흰 화면 및 메뉴 관리자 예외의 원인을 확인한다. 대사 타이핑, 첫 목표·튜토리얼을 실제 화면에서 검증한다.
3. 실제 설치본에서 제거 → 원본 메뉴 실행 → 재설치 순서로 복원을 검증한다.
4. 모든 챕터·분기·엔딩을 플레이하며 번역 문맥, 발화자, 존댓말과 용어를 교정한다.
5. 다른 해상도·창 모드에서 긴 대사, 줄바꿈, 오버플로 로그를 확인하고 필요한 문구를 개별 조정한다.
6. 게임 업데이트가 나오면 원본 해시·텍스트·TMP 내부 API를 재조사한다. 현재 빌드 외의 호환성은 미확인이다.

## 출처

- [BepInEx 공식 릴리스](https://github.com/BepInEx/BepInEx/releases): 로더와 의존성.
- [UnityPy](https://github.com/K0lb3/UnityPy): 읽기 전용 에셋 조사.
- [TextMeshPro TMP_FontAsset API](https://docs.unity3d.com/Packages/com.unity.textmeshpro@3.0/api/TMPro.TMP_FontAsset.html): 동적 글꼴 생성 참고. 실제 게임 DLL의 API와 실행 결과를 우선한다.
