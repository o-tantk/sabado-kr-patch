# Sabado 한국어 패치

Windows Steam판 **Sabado**, App ID `4986750`, 설치 빌드 `26402944`를 대상으로 제작하는 비공식 한국어 패치입니다. 엔진은 Unity `6000.0.31f1`, 실행 방식은 Mono x64입니다.

## 현재 상태

제작 중입니다. 설치 파일은 원본 게임과 분리해 생성하며, 실제 화면 검증 후 아래에 적용·제거 절차와 확인 범위를 기록합니다.

## 작업 환경

Python 3.13과 프로젝트 전용 `.venv`를 사용합니다.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-tools.txt
.\.venv\Scripts\python.exe tools/survey.py --game "C:\Program Files (x86)\Steam\steamapps\common\Sabado"
```

조사는 설치 폴더를 읽기만 합니다. 추출한 원본 CSV, 파일 목록, 해시는 `local/survey/`에 저장하며 Git에서 제외합니다.

## 저장소 범위

직접 작성한 패치 소스, 한국어 번역, 도구와 문서만 추적합니다. `local/`, `vendor/`, `build/`, `dist/`, `.venv/`의 게임 원본, 원본 추출물, 백업, 외부 바이너리, 임시 파일은 커밋하지 않습니다.

자세한 조사와 검증 기록은 [docs/korean-patch.md](docs/korean-patch.md)에 있습니다.
