# Changelog

**English** · [한국어](#한국어)

## 0.2.0

Made for Omarchy 4.5. Update with `omarchy plugin update io.github.e2goon.omasweep`.

### What's new

- **Docker works again on Omarchy 4.5.** Omarchy 4.5 no longer adds you to the `docker` group, so
  Docker cleanup quietly disappeared. omasweep now runs it through `sudo`. If sudo needs your
  password, the Docker items show "unknown" size and wait until you pick them. Docker that never
  ran on your machine is not listed.
- **A warning before `omarchy update` fails.** `omarchy update` needs 10 GB free on `/`. When you
  have less, the bar icon turns red, and `oms scan` and `oms clean` say so.
- **An optional reminder after each update.** Install the post-update hook (see the README). It
  checks in the background after `omarchy update` and sends a notification with a **Sweep** button
  when more than 5 GB can be cleaned safely. It never deletes anything itself.
- **The terminal looks like the rest of Omarchy.** Sweep and Preview now open through Omarchy's
  own floating terminal, with the Omarchy logo and its Done/Failed prompt. A failed sweep now says
  "Failed" instead of "Done".
- **Vertical bars** show only the icon.

### New things it can clean

| Item | What it is |
|---|---|
| Unfinished downloads | `.crdownload` and `.part` files in Downloads, untouched for 7 days and not open |
| Qt app caches | Rebuildable caches of Qt apps, including Omarchy's omawrite, omacalc, hype, monologue, and omacut |
| Zed | Temp files, logs, and its npm cache (your extensions and settings stay) |
| OpenCode | Downloaded provider packages (your sessions stay) |
| GitHub CLI, kubectl, gcloud, Azure CLI | API caches and logs (your logins and configs stay) |
| Copilot CLI | Old versions, keeping the one in use and one before it |
| Prisma, pyenv | Download caches |
| Browser AI models | Chrome and Edge on-device AI models, often several GB. Opt-in, since they download again |
| More project build folders | Python (`.tox`, `.pytest_cache`, `.mypy_cache`, ...), Zig, Astro, Expo, `.output`, `coverage` in projects untouched for 30 days. Opt-in |

### Safer than before

- A folder git tracks files in is never deleted as "build output", whatever it is called. If git
  can't read a project, its folders are kept.
- `dist`, `build`, `bin`, and `obj` are never touched; they too often hold real files.
- These are never touched on Omarchy:
  - browser Service Worker storage (Omarchy web apps live in it)
  - AI agent sessions and worktrees (the bar's agents widget reads them)
  - Superwhisper recordings and models
  - `~/.aws` logins
  - `~/Work/tries` as a whole
  - AppImages
  - Omarchy's own state
  - snapshots
- Go caches are cleaned with Go's own command, from a neutral folder, so a project's `go.mod`
  can't make Go download a toolchain while you're trying to free space.

### Changed

- **Orphaned packages are no longer offered.** `omarchy update` already removes them every time.
  If a script of yours still says `--only orphans`, it keeps working and just prints a note.
- **Old package versions** mostly come up empty now, because `omarchy update` already trims the
  pacman cache. omasweep still removes cached copies of packages you uninstalled.

## 한국어

## 0.2.0

Omarchy 4.5에 맞춘 버전입니다. `omarchy plugin update io.github.e2goon.omasweep`로 업데이트하세요.

### 새로워진 점

- **Omarchy 4.5에서 Docker 정리가 다시 됩니다.** Omarchy 4.5부터 사용자가 `docker` 그룹에 들어가지
  않아서, Docker 항목이 아무 말 없이 사라졌습니다. 이제 `sudo`로 정리합니다. sudo에 비밀번호가
  필요하면 Docker 항목은 크기를 "unknown"으로 보여 주고, 직접 고를 때까지 기다립니다. 한 번도 실행한
  적 없는 Docker는 목록에 나오지 않습니다.
- **`omarchy update`가 실패하기 전에 알려 줍니다.** `omarchy update`는 `/`에 10 GB가 비어 있어야
  실행됩니다. 그보다 적으면 바 아이콘이 빨갛게 바뀌고, `oms scan`과 `oms clean`도 알려 줍니다.
- **업데이트 후 알림 (선택).** post-update 훅을 설치하면(README 참고) `omarchy update`가 끝난 뒤
  백그라운드에서 확인하고, 안전하게 정리할 양이 5 GB를 넘으면 **Sweep** 버튼이 달린 알림을 보냅니다.
  훅이 직접 지우는 것은 없습니다.
- **터미널이 Omarchy와 같은 모양으로 열립니다.** Sweep과 Preview가 Omarchy의 플로팅 터미널로 열리고,
  Omarchy 로고와 Done/Failed 안내가 나옵니다. 정리가 실패하면 "Done" 대신 "Failed"가 뜹니다.
- **세로 바**에서는 아이콘만 보입니다.

### 새로 정리하는 항목

| 항목 | 내용 |
|---|---|
| 받다 만 다운로드 | 다운로드 폴더에서 7일 넘게 그대로이고 열려 있지 않은 `.crdownload`, `.part` 파일 |
| Qt 앱 캐시 | Qt 앱이 다시 만드는 캐시. Omarchy의 omawrite, omacalc, hype, monologue, omacut 포함 |
| Zed | 임시 파일, 로그, npm 캐시(확장과 설정은 남김) |
| OpenCode | 내려받은 프로바이더 패키지(세션은 남김) |
| GitHub CLI, kubectl, gcloud, Azure CLI | API 캐시와 로그(로그인과 설정은 남김) |
| Copilot CLI | 옛 버전(사용 중인 버전과 직전 버전은 남김) |
| Prisma, pyenv | 다운로드 캐시 |
| 브라우저 AI 모델 | Chrome·Edge의 온디바이스 AI 모델. 수 GB가 되기도 하고 다시 받아야 하므로 직접 골라야 함 |
| 프로젝트 빌드 폴더 추가 | 30일간 손대지 않은 프로젝트의 Python(`.tox`, `.pytest_cache`, `.mypy_cache` 등), Zig, Astro, Expo, `.output`, `coverage`. 직접 골라야 함 |

### 더 안전해진 점

- git이 추적하는 파일이 든 폴더는 이름이 무엇이든 "빌드 결과물"로 보고 지우지 않습니다. git이 읽지
  못하는 프로젝트의 폴더도 남깁니다.
- `dist`, `build`, `bin`, `obj`는 실제 파일이 들어 있는 경우가 많아 건드리지 않습니다.
- Omarchy에서 다음은 절대 건드리지 않습니다.
  - 브라우저 Service Worker 저장소(Omarchy 웹앱이 여기에 데이터를 둠)
  - AI 에이전트 세션과 worktree(바의 agents 위젯이 읽음)
  - Superwhisper 녹음과 모델
  - `~/.aws` 로그인
  - `~/Work/tries` 폴더 통째
  - AppImage
  - Omarchy 자체 상태
  - 스냅샷
- Go 캐시는 Go 자체 명령으로, 프로젝트와 상관없는 위치에서 정리합니다. 그래서 공간을 비우는 도중에
  프로젝트의 `go.mod` 때문에 Go 툴체인을 새로 받는 일이 없습니다.

### 바뀐 점

- **고아 패키지는 더 이상 정리 대상이 아닙니다.** `omarchy update`가 매번 지웁니다. 스크립트에
  `--only orphans`가 남아 있어도 멈추지 않고 안내만 보여 줍니다.
- **오래된 패키지 버전** 항목은 이제 대부분 비어 있습니다. `omarchy update`가 pacman 캐시를 이미
  정리하기 때문입니다. 삭제한 패키지의 캐시는 omasweep이 계속 지웁니다.
