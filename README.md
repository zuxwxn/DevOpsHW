# 이미지 대표 색상 추출 웹앱

사진을 업로드하면 이미지의 대표 색상을 분석해 HEX 코드와 함께 보여주는 로컬 FastAPI 웹앱입니다. 색상 카드를 클릭하면 HEX 코드가 클립보드에 복사됩니다.

외부 유료 API, 계정, 로그인, GPU, 대용량 AI 모델을 사용하지 않습니다. 업로드 파일은 요청 처리 중에만 메모리에서 분석하며 별도로 저장하지 않습니다.

## 주요 기능

- JPG, PNG, WEBP, GIF 이미지 업로드와 미리보기
- 대표 색상 최대 5개 및 RGB/HEX 코드 표시
- HEX 코드 클릭 복사
- 분석 진행 상태와 오류 메시지 표시
- 10MB 초과 파일, 비이미지 파일, 손상된 이미지 거부

## 요구 사항

- Windows, macOS 또는 Linux
- Python 3.10 이상
- 인터넷 연결: 최초 패키지 설치 시에만 필요

## 설치

프로젝트를 내려받은 뒤 PowerShell(Windows) 또는 터미널에서 프로젝트 폴더로 이동합니다.

```powershell
cd image-color-extractor
python -m pip install -r requirements.txt
```

가상환경은 필수가 아닙니다. 시스템에 설치된 Python으로 바로 실행할 수 있습니다.

## 모델 준비 방법

별도의 AI 모델, 가중치 파일, API 키는 필요하지 않습니다. Pillow 라이브러리의 **median-cut 색상 양자화**를 사용하므로 `requirements.txt`의 패키지를 설치하는 것만으로 준비가 끝납니다.

CPU 부담을 줄이기 위해 이미지를 최대 600×600 크기로 축소한 뒤 5개 색상 군집을 만듭니다. 따라서 일반 노트북 CPU에서도 빠르게 동작합니다.

## 실행

```powershell
python -m uvicorn app:app --host 127.0.0.1 --port 8000
```

브라우저에서 다음 주소를 엽니다.

```text
http://127.0.0.1:8000
```

서버 종료는 실행 중인 터미널에서 `Ctrl+C`를 누릅니다.

## Docker 실행

Docker Desktop을 실행한 뒤, 프로젝트 최상위 폴더에서 이미지를 빌드하고 컨테이너를 시작합니다.

```powershell
docker build -t image-color-extractor:local .
docker run --rm -p 8000:8000 image-color-extractor:local
```

브라우저에서 `http://127.0.0.1:8000`을 엽니다. 컨테이너는 루트 권한이 아닌 전용 사용자로 실행됩니다.

## GitHub Actions 및 Docker Hub 배포

`.github/workflows/ci.yml`은 pull request에서는 Docker 이미지를 빌드해 검증하고, 모든 push와 `workflow_dispatch` 실행에서는 Docker Hub에 이미지를 업로드합니다. 기본 브랜치에 push하면 `latest` 태그도 함께 생성됩니다. Docker Hub 로그인은 GitHub Secrets를 환경 변수로 전달하고 Docker CLI의 `--password-stdin` 방식으로 수행하므로 토큰이 로그에 출력되지 않습니다.

GitHub 저장소의 **Settings → Secrets and variables → Actions**에서 다음 Repository secrets를 등록해야 합니다.

- `DOCKERHUB_USERNAME`: Docker Hub 사용자명
- `DOCKERHUB_TOKEN`: Docker Hub에서 발급한 액세스 토큰

`DOCKERHUB_USERNAME`에는 Docker ID만 입력합니다. URL, `docker.io/` 접두사, 공백, 따옴표, 이메일 주소를 포함하면 안 됩니다. `DOCKERHUB_TOKEN`에는 Docker Hub **Personal Access Token**의 값만 붙여넣으며, `Bearer ` 접두사나 따옴표를 넣지 않습니다. 계정 비밀번호는 사용하지 마세요.

이미지는 `docker.io/<DOCKERHUB_USERNAME>/image-color-extractor`로 업로드됩니다. Docker Hub에서 같은 이름의 저장소를 미리 생성하고, 토큰에 해당 저장소의 읽기·쓰기 권한을 부여해 주세요. 인증 오류가 발생하면 기존 `DOCKERHUB_TOKEN` Secret을 삭제하고 새 Personal Access Token으로 다시 생성한 다음, 새 Secret을 등록하세요.

## Self-hosted Runner 자동 배포

`.github/workflows/deploy.yml`은 **Build and publish Docker image** 워크플로가 기본 브랜치에서 성공한 뒤 Windows Self-hosted Runner에서 실행됩니다. 이 Runner는 Docker Hub의 `latest` 이미지를 pull하고, `image-color-extractor`라는 이름의 컨테이너만 교체합니다. 새 컨테이너가 `http://127.0.0.1:8000/`에서 HTTP 200을 반환해야 배포가 성공으로 처리됩니다.

배포 Runner에는 다음이 필요합니다.

- 기본 라벨 `self-hosted`, `Windows`, `X64`를 가진 온라인 GitHub Self-hosted Runner
- Runner와 같은 Windows 사용자 계정에서 실행 가능한 Docker Desktop
- GitHub Repository secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`
- 로컬 포트 `8000`을 이미 다른 프로그램이 사용하지 않는 상태

배포가 실패하면 새 컨테이너를 제거하고, 기존 컨테이너 이미지가 있었으면 해당 이미지로 되돌립니다. Runner 설치 폴더와 작업·진단·자격 증명 파일은 `.gitignore`로 Git에서 제외합니다.

## 사용 방법

1. 업로드 영역을 클릭하거나 이미지 파일을 끌어 놓습니다.
2. 표시된 미리보기를 확인하고 **색상 추출**을 누릅니다.
3. 결과의 색상 카드를 클릭해 HEX 코드를 복사합니다.

지원하는 형식은 JPG, PNG, WEBP, GIF이며, 파일 최대 용량은 10MB입니다. 서버는 실제 이미지 형식을 검증하고 5천만 픽셀보다 큰 이미지를 거부합니다.

## 구성

```text
.
├── app.py                 # FastAPI 서버 및 이미지 색상 분석
├── requirements.txt       # Python 의존성
├── static/
│   ├── index.html         # 화면 구조
│   ├── style.css          # 반응형 화면 디자인
│   └── app.js             # 업로드·미리보기·API 호출·복사 기능
├── .gitignore
└── README.md
```
