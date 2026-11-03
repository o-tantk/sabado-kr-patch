# 배포판에 포함된 외부 구성 요소

한국어 패치는 BepInEx 공식 배포판의 바이너리를 수정 없이 포함합니다. 아래 라이선스 전문을 `licenses/`에 동봉합니다. 게임 원본 DLL, 게임 원본 에셋, Windows 글꼴은 포함하지 않습니다.

| 구성 요소 | 버전 | 라이선스 / 소스 |
| --- | --- | --- |
| BepInEx | 5.4.23.6 | MIT — https://github.com/BepInEx/BepInEx/tree/v5.4.23.6 |
| HarmonyX (`0Harmony.dll`) | 2.9.0 | MIT — https://github.com/BepInEx/HarmonyX/tree/v2.9.0 |
| BepInEx.Harmony, HarmonyXInterop, Harmony 호환 라이브러리 | BepInEx 5.4.23.6에 포함된 버전 | MIT — https://github.com/BepInEx/BepInEx.Harmony |
| Harmony 원저작물 고지 | 2.0 계열 호환 라이브러리 | MIT — https://github.com/pardeike/Harmony |
| Mono.Cecil | 0.10.4 | MIT — https://github.com/jbevain/cecil/tree/0.10.4 |
| MonoMod.RuntimeDetour, MonoMod.Utils | 22.1.29.1 | MIT — https://github.com/MonoMod/MonoMod/tree/v22.01.29.01 |
| UnityDoorstop (`winhttp.dll`) | 4.6.0 | LGPL-2.1 — https://github.com/NeighTools/UnityDoorstop/tree/v4.6.0 |

UnityDoorstop 4.6.0의 전체 소스 아카이브를 배포 ZIP의 `third-party-sources/UnityDoorstop-4.6.0-source.tar.gz`에 포함합니다. 커밋은 `1c3ece1f1e6c20f4aa74d5402baabf8a0098d282`이며 빌드 방법은 아카이브의 README 및 빌드 스크립트에 있습니다. 이 라이브러리를 수정·재빌드·교체할 수 있으며, LGPL이 허용하는 라이브러리 변경의 디버깅을 위한 역공학을 제한하지 않습니다. 설치 도구의 무결성 검사는 수정된 파일의 자동 덮어쓰기·삭제를 막으므로, 라이브러리를 직접 바꿀 때는 원본과 백업을 보관하세요.

이 고지는 외부 구성 요소에 관한 것이며 게임 및 해당 리소스의 권리를 부여하지 않습니다.
