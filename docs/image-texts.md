# 이미지 문구 조사와 제작 기록

대상: Steam build 26402944 / Unity 6000.0.31f1. `tools/survey_textures.py`로 설치 폴더를 읽기 전용 조사한다. 추출 원본과 전체 목록은 Git에서 제외한 `local/survey-textures/`, 추가 후보는 `local/extracted/textures/`에 보관한다.

## 조사 범위

`.assets` 파일에서 Texture2D 705개를 목록화했다. 이름으로 추린 메모·지도·칠판·포스터·튜토리얼과 RGB 계열 물체 텍스처를 개별 이미지로 확인했다. 705개 모두를 육안 검수했다는 뜻은 아니다.

| 이미지 | 확인한 내용 | 처리 |
| --- | --- | --- |
| PaperNote | 다음 목적지(2층의 문이 열린 방)를 안내하는 문 메모 | 한국어 이미지 제작, 런타임 교체 |
| CHESA MOODS1 | 그림 속 E to Interact | E 키: 상호작용으로 편집 |
| PUSHHER | 그림 속 E to Push | E 키: 밀기로 편집 |
| CALMHER | 그림 속 E to Calm Her, Chesa, 울음소리 | E 키: 진정시키기 / 체사 / 흐흑…으로 편집 |
| ExitSign_Albedo / Emissive / Normal | EXIT 표지와 발광·법선 표현 | 세 맵의 정합성을 유지하는 별도 작업 필요 |
| poster 2 / poster 1 | 응원 문구, 학교 체육 행사 포스터 | 배경 장식, 우선순위 낮음 |
| TestPaper | 흐릿한 시험지 본문과 F+ | 읽을 수 없는 본문을 추측 번역하지 않음 |
| Map / Board | 지도·게시판 장식 | 명확한 진행 문구 없음 |
| PlainNotes / postitnotesbatch | 빈 종이와 메모 재질 | 이미지 자체에 번역할 글자 없음 |
| CHESA MOODS2 / FIND ITEMS / GetOut / Healing / HealUI | 상황 그림·숫자·회복 효과 | 독립적인 영어 안내 문구 없음 |
| RGB 3 | 칠판 지우개 상품 포장 | 배경 장식, 우선순위 낮음 |
| 기타 확인한 RGB 계열 | 지갑·팔찌·도구·책 등 | 진행 문구 없음 |

## 문 메모

`sharedassets2.assets` path ID 630, `PaperNote`, 1024×1024 RGBA. Material path ID 110 `Drywall`의 `_MainTex`가 참조한다. 텍스처 이름·원본 크기·재질 이름·속성을 모두 일치시킨다. 해당 `.assets`의 원본 SHA-256도 설치 호환성 검사에 추가했다.

번역: **2층에서 / 문이 열린 방으로 / 가세요**. 이미지 도구 결과는 1254×1254 RGBA이며 정사각형 비율을 유지한다. 런타임에서는 정규화 UV로 매핑한다. 생성형 편집으로 종이 가장자리와 격자에도 미세한 차이가 있으므로 픽셀 단위 보존이라고 주장하지 않는다. 실제 장면에서 방향·글자·투명 영역을 검수한다.

직접 작성한 번역과 편집 결과만 `translations/textures.json`, `assets/textures/`에 포함한다. 추출 원본은 커밋하지 않는다. 원본 게임 파일과 Texture2D는 그대로 두고, 메모 재질의 텍스처 참조를 메모리에서 바꾼다. 다른 언어 또는 패치 비활성화에서는 원래 참조로 복원한다. 설치 파일은 기존 백업·제거 저널에 포함한다.

## 생성 도구와 최종 프롬프트

내장 `image_gen` 도구를 사용했다. CLI/API 키 방식은 사용하지 않았다. 입력 이미지를 먼저 직접 확인했고 결과의 한국어 철자를 확인했다.

최종 파일: `assets/textures/second-floor-note.png`.

```text
Use case: text-localization. Edit target: the provided 1024 by 1024 Unity game texture of a graph-paper note. Translate ONLY the black English lettering, replacing all three English lines with these exact Korean lines, centered in the same paper writing area, black rounded handwritten lettering with thick strokes for game readability:
2층에서
문이 열린 방으로
가세요
Preserve the exact full square texture layout and UV mapping, paper silhouette, existing edge padding/color bleed, grid, paperclip, yellow sheet, colors and transparency. Do not crop, rotate, reframe, add a background or add any new illustration. Keep the writing inside the original writing area, generously spaced, clearly legible correct Korean. Output 1024x1024 PNG. Everything outside the text area should remain unchanged.
```

요청 크기와 실제 출력 크기가 달랐으며 실제 값은 위에 기록했다. 생성 결과의 비율과 PNG 형식을 패키징 단계에서 검사한다. 비율 오차가 0.2%를 넘으면 거부한다.

## 튜토리얼 이미지 3개

`sharedassets3.assets`의 path ID 92(`CHESA MOODS1`), 67(`PUSHHER`), 68(`CALMHER`)이다. 원본 각각 1920×1080, 전체 사각형 Sprite, pixelsPerUnit 100, border 0으로 확인했다. 같은 이름·텍스처 크기·전체 사각형·무패킹·border 0 조건이 맞는 `UnityEngine.UI.Image.sprite`만 교체한다. 원래 RectTransform을 유지하고, 픽셀 해상도 차이에 맞춰 pixelsPerUnit을 조정한다. 이름이 다른 스프라이트와 아틀라스 일부는 치환하지 않는다.

최종 파일:

- `assets/textures/tutorial-interact.png`
- `assets/textures/tutorial-push.png`
- `assets/textures/tutorial-calm.png`

각 파일에 내장 `image_gen`을 한 번씩 사용했다. 실제 출력은 각각 1672×941 RGBA이며 원본 비율과의 차이는 약 0.053%다. 투명 배경을 지정하고 생성된 알파를 유지했다. 생성 이미지의 한국어와 배치를 확인했지만 **실제 게임 튜토리얼 UI의 표시 검증은 남았다**. 문 메모는 실제 화면과 언어 전환 양방향 복원을 확인했다.

상호작용 최종 프롬프트:

```text
Use case: text-localization. Edit target: this 1920x1080 (16:9) game tutorial illustration. Replace ONLY the small white English UI text 'E to Interact' on the left with exactly 'E 키: 상호작용'. White bold Korean letters with dark outline, slightly larger for readability, centered at the original label position. Preserve the same 16:9 composition, yellow rounded frame, transparency at corners, both panels, all characters, facial expressions, pose, clothing, paper, furniture, lighting and every other visual detail. This is a localization of an existing game screenshot; do not redraw or reinterpret the characters or environment. Do not add a title or new objects. Output a 1920x1080 PNG preserving layout.
```

밀기 최종 프롬프트:

```text
Use case: text-localization. Edit target: this 1920x1080 (16:9) game tutorial illustration. Replace ONLY the small white English UI text 'E to Push' on the left with exactly 'E 키: 밀기'. White bold Korean letters with dark outline, slightly larger for readability, centered at the original label position. Preserve the same 16:9 composition, yellow rounded frame, transparency at corners, both panels, all characters, facial expressions, pose, clothing, furniture, lighting and every other visual detail. This is a localization of an existing game screenshot; do not redraw or reinterpret the characters or environment. Do not add a title or new objects. Output a 1920x1080 PNG preserving layout.
```

진정시키기 최종 프롬프트:

```text
Use case: text-localization. Edit target: this 1920x1080 (16:9) game tutorial illustration. Replace ONLY the English UI labels on the left panel: 'E to Calm Her' becomes exactly 'E 키: 진정시키기' in bold white Korean with a dark outline at the same location; the magenta speaker name 'Chesa' becomes '체사'; the white bottom dialogue 'Huhuhuhu' becomes '흐흑…'. Keep labels legible within their original areas. Preserve the same 16:9 composition, yellow rounded frame, transparency at corners, both panels, all characters, expressions, poses, clothing, progress bar, furniture, lighting and every other visual detail. This is localization of an existing game screenshot; do not redraw or reinterpret characters or environment. Do not add a title or new objects. Output 1920x1080 PNG preserving layout.
```
