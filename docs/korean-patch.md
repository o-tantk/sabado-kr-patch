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

BepInEx 5.4.23.6 Mono x64와 직접 작성한 C# 플러그인을 사용한다. `GetText`의 결과를 한국어로 바꾸되 **원래 English 슬롯에서만** 동작한다. 언어의 저장 번호를 바꾸지 않으며 음성 언어를 변경하지 않는다. 언어 메뉴의 English 표시는 한국어(패치)로 바꾼다. 나머지 언어는 원래 게임 기능을 사용한다. 원본 `.assets`와 게임 DLL은 수정하지 않는다.

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

## 검증 계획 / 아직 확인할 사항

1. 원본 메뉴와 언어 설정을 확인한다.
2. 대표 메뉴 몇 개를 먼저 번역해 실행·폰트·문구 잘림을 검증한다.
3. 성공 후 CSV의 대사·목표·도움말로 번역을 확대한다.
4. 변수, 서식 태그와 조작 키를 자동 검사한다.
5. 적용 전 대상 파일의 존재 여부·해시와 백업을 남긴다. 제거 후 원본 파일 해시를 비교한다.
6. 대사 타이핑, 실제 플레이, 해상도별 줄바꿈과 모든 분기는 검증 범위를 구분해 기록한다.

## 출처

- [BepInEx 공식 릴리스](https://github.com/BepInEx/BepInEx/releases): 로더와 의존성.
- [UnityPy](https://github.com/K0lb3/UnityPy): 읽기 전용 에셋 조사.
- [TextMeshPro TMP_FontAsset API](https://docs.unity3d.com/Packages/com.unity.textmeshpro@3.0/api/TMPro.TMP_FontAsset.html): 동적 글꼴 생성 참고. 실제 게임 DLL의 API와 실행 결과를 우선한다.
