# Sabado 한국어 패치 제작 기록

## 대상과 직접 확인한 사실

- 조사일: 2026-11-04 (한국 시간).
- 설치 폴더: `C:\Program Files (x86)\Steam\steamapps\common\Sabado`.
- 작업 폴더: `C:\Workspace\sabado-kr-patch`. 기존 Git 저장소를 사용한다.
- Steam App ID: `4986750`, 설치된 build ID: `26402944`. `appmanifest_4986750.acf`에서 확인했다.
- Unity: `6000.0.31f1`. `UnityPlayer.dll` 버전과 직렬화 파일 헤더에서 확인했다.
- Windows x64 / Mono. PE machine `0x8664`, `MonoBleedingEdge`, `Managed/Assembly-CSharp.dll`을 확인했다.
- 사람이 읽는 별도 게임 버전 번호는 아직 확인하지 못했다. Steam build ID와 원본 파일 SHA-256을 기준으로 호환성을 검사한다.

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

BepInEx Mono x64와 직접 작성한 C# 플러그인을 사용해 게임의 기존 번역 경로에 한국어를 연결한다. 원본 `.assets`와 게임 DLL을 수정하지 않고 플러그인 파일을 추가하는 방식을 우선 시험한다. 이 방식은 원본 전체 에셋을 배포할 필요가 없고, 로더와 플러그인 제거로 되돌릴 수 있다.

한국어 글꼴은 외부 폰트에서 실행 중 TMP 폰트를 만들 수 있는지 먼저 시험한다. 번역 자료는 원문 키의 SHA-256과 직접 작성한 한국어만 저장하고, 원문 전체 CSV와 게임 DLL은 `local/`에만 둔다.

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
