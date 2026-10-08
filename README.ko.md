# omasweep

[English](README.md) · **한국어**

[Omarchy](https://omarchy.org)의 디스크 공간을 되찾아 주는 도구입니다. 터미널 정리 도구(`oms`)와 Omarchy 셸
바 위젯으로 이루어져 있습니다. Arch + Hyprland 환경에서 용량이 쌓이는 곳을 알고 있습니다. pacman 캐시,
오래된 [mise](https://mise.jdx.dev) 도구 버전, Docker와 Podman, Omarchy가 설치하는 모든 언어의 패키지
캐시, 브라우저와 Electron 앱 캐시, Flatpak, Steam과 Wine, AI 모델 캐시, 손대지 않은 프로젝트의 빌드
결과물까지 60개가 넘는 대상을 다루며, 내 PC에 실제로 있는 것만 보여 줍니다.

<p align="center">
  <img src="docs/images/scan.png" alt="Ghostty에서 실행한 oms scan. 안전 항목, 검토 항목, 앱이 열려 있어 건너뛴 캐시가 나뉘어 보입니다" width="720">
</p>

## 특징

- **가치 순으로 정렬합니다.** 안전한 항목이 먼저, 큰 것부터 나오고 미리 선택되어 있습니다. 지우면 대가가
  따르는 항목(휴지통, 셰이더 캐시, 프로젝트 의존성, 고아 패키지)은 목록에만 보이고 직접 골라야 합니다.
- **고른 다음에 정리합니다.** [gum](https://github.com/charmbracelet/gum) 체크리스트에서 항목을 켜고 끈
  뒤 한 번만 확인하면 됩니다. `--dry-run`은 어떤 명령이 실행되고 어떤 폴더가 비워질지 그대로 보여 줍니다.
- **각 도구의 정리 명령을 씁니다.** 도구의 데이터를 몰래 지우는 대신 `mise prune`, `docker builder prune`,
  `paccache`, `journalctl --vacuum-time`, `uv cache prune`, `go clean`, `pnpm store prune`을 호출합니다.
- **실행 중인 앱은 건드리지 않습니다.** 열려 있는 브라우저, Electron 앱, Flatpak 앱, 게임 런처의 캐시는
  건너뛰고, 정리 직전에 한 번 더 확인합니다.
- **Omarchy에 맞춰져 있습니다.** 현재 테마(ANSI 팔레트와 Omarchy의 gum 색)를 따르고, `omarchy update`처럼
  패키지 버전을 두 개씩 남깁니다. 바에서 Omarchy의 플로팅 터미널로 열리며, 선택한 항목에 필요할 때만 그
  터미널에서 `sudo`를 요청합니다.
- **숫자를 정직하게 보여 줍니다.** 정리한 양과 실제로 늘어난 여유 공간을 함께 보여 주고, 둘이 다르면(Btrfs
  스냅샷이나 하드링크가 데이터를 붙잡고 있는 경우) 그렇다고 알려 줍니다.

## 설치

### 바 위젯과 CLI

```bash
omarchy plugin add https://github.com/e2goon/omasweep.git --enable
~/.config/omarchy/plugins/io.github.e2goon.omasweep/bin/oms link
```

첫 번째 명령은 위젯을 바에 설치합니다. 두 번째 명령은 `oms`를 `~/.local/bin`에 연결해 어느 터미널에서나
실행할 수 있게 합니다. `omarchy plugin update io.github.e2goon.omasweep`로 둘 다 업데이트됩니다.

<p align="center">
  <img src="docs/images/widget.png" alt="omasweep 바 위젯 팝업. 안전하게 정리할 수 있는 총량, 큰 항목, Sweep과 Preview 버튼이 보입니다" width="360">
</p>

위젯은 안전하게 정리할 수 있는 양과 큰 항목을 보여 줍니다. **Sweep**과 **Preview**를 누르면 Omarchy의
플로팅 터미널에서 `oms`가 열리고, 그곳에서 항목을 고르고 확인합니다.

### CLI만

```bash
git clone https://github.com/e2goon/omasweep.git ~/.local/share/omasweep
~/.local/share/omasweep/bin/oms link
```

필요한 것: Bash 5, coreutils, findutils, `jq`(`oms scan --json`과 위젯에 필요). `gum`은 있으면 쓰며
Omarchy에 기본으로 들어 있습니다. `mise`, `docker`, `paccache`(`pacman-contrib`), `uv`, `pnpm` 같은 도구는
설치되어 있을 때만 쓰고, 없으면 해당 대상을 건너뜁니다.

## 제거

```bash
rm ~/.local/bin/oms
omarchy plugin remove io.github.e2goon.omasweep
```

첫 번째 명령은 `oms` 연결을 지웁니다. 두 번째 명령은 위젯을 바에서 내리고 플러그인을 삭제합니다. CLI만
설치했다면 두 번째 명령 대신 `rm -rf ~/.local/share/omasweep`를 실행합니다. 화이트리스트와 작업 기록까지
지우려면 `rm -rf ~/.config/omasweep ~/.local/state/omasweep`를 실행합니다.

## 사용법

```bash
oms                         # 스캔, 선택, 확인, 정리
oms scan                    # 정리할 수 있는 양만 보여 주고 아무것도 바꾸지 않음
oms clean --dry-run         # 아무것도 지우지 않고 정리 과정을 미리 보기
oms clean --yes             # 묻지 않고 안전 항목을 모두 정리
oms clean --only mise,docker-build
oms clean --all --skip trash
oms whitelist               # 경로나 대상 전체를 보호
oms log                     # 지운 것, 건너뛴 것, 실패한 것
```

| 옵션 | 뜻 |
| --- | --- |
| `-n`, `--dry-run` | 정리를 미리 봅니다. 아무것도 지우지 않고 로그도 남기지 않습니다. |
| `-y`, `--yes` | 묻지 않습니다. `--all`이나 `--only`가 없으면 안전 항목만 정리합니다. |
| `-a`, `--all` | 검토 항목도 미리 선택합니다. |
| `--only ID,...` | 이 대상만 정리합니다. ID는 `oms scan`에 나옵니다. |
| `--skip ID,...` | 이 대상을 뺍니다. |
| `--debug` | 실행하는 명령과 출력을 모두 보여 줍니다. |
| `--hold` | 끝나기 전에 키 입력을 기다립니다. 바 위젯이 씁니다. |

터미널이 없으면 `oms clean`은 `--yes`나 `--dry-run` 없이는 실행되지 않습니다. root로 실행하는 것도
거부합니다. 필요할 때 직접 `sudo`를 요청합니다.

## 정리 대상

내 PC에 있는 대상만 나옵니다. `oms scan`으로 ID와 함께 확인할 수 있습니다.

### 대상을 고르는 기준

- **안전(safe)** 대상은 주인이 알아서 다시 만드는 데이터입니다. 다운로드 캐시, 빌드 캐시, 로그, 크래시
  덤프, 어떤 설정도 쓰지 않는 도구 버전이 여기에 속합니다. 대가는 다시 받거나 다시 빌드하는 시간뿐이며,
  미리 선택되어 있습니다.
- **검토(review)** 대상은 눈에 띄는 대가가 있거나 원하는 것이 들어 있을 수 있습니다. 휴지통, 오프라인
  음악, AI 모델, 셰이더 캐시(다시 만드는 동안 게임이 끊김), 프로젝트 의존성, 고아 패키지, 컨테이너
  이미지가 여기에 속하며, 목록에만 보이고 직접 골라야 합니다.
- **절대 건드리지 않는 것**: 로그인 정보, 쿠키, 방문 기록, 설정, 로컬 저장소, 메일, 게임 세이브, Wine
  prefix, Steam `compatdata`, Docker 볼륨과 컨테이너, 프로젝트 소스, Maven 저장소(직접 빌드한 결과물이
  있을 수 있음), NuGet 패키지, Ollama 모델(`ollama rm`을 쓰세요).
- 도구에 자체 정리 명령이 있으면 그 데이터를 직접 지우지 않고 그 명령을 호출합니다.
- 실행 중인 앱의 캐시는 건너뜁니다. Chromium 계열 브라우저와 Electron 앱은 프로필의 `SingletonLock`,
  Firefox 계열 브라우저는 프로필의 `lock`, Flatpak 앱은 `flatpak ps`, 나머지는 프로세스 이름으로
  판단합니다. 정리 직전에 한 번 더 확인합니다.
- 심볼릭 링크로 된 캐시 폴더는 따라가지 않습니다. `$HOME` 밖의 것은 아래 표에 적힌 고정된 `sudo` 명령으로만
  지웁니다.

### 시스템

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `pacman` | 오래된 패키지 버전 | safe, sudo | `paccache -rk2`와 `paccache -ruk0` |
| `pacman-downloads` | 중단된 업데이트가 pacman 캐시에 남긴 `download-*` 폴더 | safe, sudo | 삭제 |
| `journal` | 4주가 지난 저널 보관 파일 | safe, sudo | `journalctl --vacuum-time=4weeks` |
| `coredumps` | `systemd-coredump` 보관 파일 | safe, sudo | `/var/lib/systemd/coredump`의 파일 삭제 |
| `flatpak-unused` | 설치된 앱이 쓰지 않는 Flatpak 런타임 | safe, sudo | `flatpak uninstall --unused`(사용자와 시스템) |
| `thumbnails` | 썸네일 캐시 | safe | `~/.cache/thumbnails` 비우기 |
| `orphans` | 의존성으로 설치됐지만 이제 아무도 쓰지 않는 패키지 | review, sudo | `pacman -Qdtq` 목록에 `pacman -Rns` |
| `trash` | 휴지통 | review | `~/.local/share/Trash` 비우기 |
| `installers` | 다운로드 폴더에서 30일간 손대지 않은 `.deb`, `.rpm`, `.pkg.tar.*`, `.iso`, `.dmg`, `.exe`, `.msi` | review | 파일 삭제 |

### 컨테이너

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `docker-build` | Docker 빌드 캐시 | safe | `docker builder prune -af` |
| `docker-images` | 컨테이너가 쓰지 않는 모든 이미지(일부러 받아 둔 것 포함) | review | `docker image prune -af` |
| `podman-images` | Podman의 같은 항목 | review | `podman image prune -af` |

### 개발 도구

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `mise` | 어떤 mise 설정도 쓰지 않는 도구 버전 | safe | `mise prune` |
| `mise-cache` | mise 다운로드 캐시 | safe | `mise cache clear` |
| `ai-cli-versions` | Claude Code와 Cursor Agent의 옛 빌드(사용 중인 버전과 직전 버전 하나는 남김) | safe | 옛 빌드 삭제 |
| `aur` | yay, paru, pikaur 빌드 클론 | safe | 캐시 폴더 비우기 |
| `npm`, `pnpm`, `yarn`, `bun`, `deno`, `corepack` | JavaScript 패키지 캐시 | safe | 캐시 폴더 비우기 |
| `pnpm-store` | 어떤 프로젝트도 링크하지 않는 저장소 패키지 | safe | `pnpm store prune` |
| `uv`, `pip`, `poetry` | Python 패키지 캐시 | safe | `uv cache prune`, 나머지는 비우기 |
| `go-build` | Go 빌드 캐시 | safe | `~/.cache/go-build` 비우기 |
| `cargo`, `rustup` | crate 압축 파일과 rustup 다운로드(소스와 툴체인은 남김) | safe | 폴더 비우기 |
| `gradle` | Gradle 빌드 캐시와 데몬 로그(받아 둔 의존성은 남김) | safe | 폴더 비우기 |
| `composer`, `ruby`, `dotnet`, `beam`, `jvm-tools`, `zig`, `ccache`, `opam`, `android` | Composer, RubyGems와 Bundler, NuGet HTTP, Hex와 rebar3, Coursier, Zig, ccache, opam, Android 빌드 캐시 | safe | 캐시 폴더 비우기 |
| `tool-caches` | node-gyp, Electron, TypeScript, Vite, webpack, ESLint, Prettier, Ruff, mypy, pre-commit | safe | 캐시 폴더 비우기 |
| `go-mod` | Go 모듈 캐시 | review | `go clean -modcache` |
| `test-browsers` | Playwright, Puppeteer, Cypress 브라우저 | review | 캐시 폴더 비우기 |
| `jetbrains` | JetBrains IDE 캐시와 인덱스 | review | `~/.cache/JetBrains` 비우기 |

### 브라우저

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `chromium`, `chrome`, `edge`, `brave`, `vivaldi`, `opera` | `~/.cache/<브라우저>`와 프로필 안의 코드, GPU, 셰이더 캐시 | safe | 캐시 폴더 비우기 |
| `firefox`, `zen`, `librewolf` | `~/.cache/<브라우저>` | safe | 캐시 폴더 비우기 |

### 앱

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `app-caches` | `~/.config`에서 찾은 모든 Electron, Chromium 기반 앱(VS Code, Obsidian, Discord, Slack, Signal 등)의 캐시 폴더 | safe | `Cache`, `Code Cache`, `GPUCache`, `Dawn*Cache`, `CachedData`, `Crashpad` 비우기 |
| `flatpak-caches` | `~/.var/app/*/cache` | safe | 캐시 폴더 비우기 |
| `spotify` | Spotify 캐시(오프라인 저장한 곡 포함) | review | `~/.cache/spotify` 비우기 |
| `kdenlive` | Kdenlive 프록시 클립과 미리 보기 | review | `~/.cache/kdenlive` 비우기 |
| `gpu-shaders` | Mesa, RADV, NVIDIA 셰이더 캐시 | review | 캐시 폴더 비우기 |

### 게임

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `steam-cache` | Steam 상점 페이지 캐시와 로그 | safe | 폴더 비우기 |
| `steam-shaders` | Steam 셰이더 캐시 | review | `steamapps/shadercache` 비우기 |
| `wine-caches` | winetricks 다운로드, Lutris와 Heroic 캐시 | review | 캐시 폴더 비우기 |

### AI

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `huggingface` | Hugging Face hub 캐시 | review | 캐시 폴더 비우기 |
| `ml-models` | PyTorch hub와 Whisper 모델 | review | 캐시 폴더 비우기 |
| `lmstudio` | LM Studio 모델 | review | 모델 폴더 비우기 |

### 프로젝트

| ID | 대상 | 등급 | 방법 |
| --- | --- | --- | --- |
| `project-artifacts` | 30일간 손대지 않은 프로젝트의 `node_modules`, `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.angular`, Rust와 Maven `target`, Python `.venv`/`venv`, `.gradle`, `.dart_tool`, Composer `vendor` | review | 폴더 삭제 |

폴더 옆에 프로젝트 표식 파일(`package.json`, `Cargo.toml`, `pyvenv.cfg`, `composer.json` 등)이 있을 때만
대상이 됩니다. 가장 바깥쪽 폴더만 고르고, `$HOME` 바로 아래 폴더는 무시합니다. `deploy` 폴더(Solana 키)가
있는 `target`은 남기고, Go나 Rails의 `vendor` 폴더는 건드리지 않습니다. 지우기 직전에 프로젝트를 한 번
더 확인합니다.

Btrfs 스냅샷은 지우지 않습니다. snapper가 관리하는 루트에서 기대보다 적게 비워졌다면 `sudo snapper
list`를 확인해 보라고 알려 줍니다.

## 화이트리스트

`oms whitelist`는 `~/.config/omasweep/whitelist`를 엽니다. 한 줄에 하나씩 적습니다.

```
# 대상 전체를 건너뜀
docker-images

# 이 경로와 그 아래는 절대 지우지 않음. 글롭도 됩니다.
~/.cache/pnpm
~/Work/keep-this/node_modules
```

## 설정

| 변수 | 기본값 | 뜻 |
| --- | --- | --- |
| `OMS_PACMAN_KEEP` | `2` | pacman 캐시에 남길 패키지 버전 수 |
| `OMS_JOURNAL_KEEP` | `4weeks` | `journalctl --vacuum-time`으로 남길 저널 기간 |
| `OMS_STALE_DAYS` | `30` | 프로젝트 빌드 결과물이나 내려받은 설치 파일을 오래된 것으로 보는 날 수 |
| `OMS_PROJECT_DIRS` | `~/Projects:~/projects:~/Code:~/code:~/src:~/dev:~/Work:~/work` | 프로젝트 빌드 결과물을 찾을 위치 |
| `NO_COLOR` | 없음 | 색 끄기 |

위젯에는 설정이 두 개 있습니다. `showSize`는 아이콘 옆에 안전하게 정리할 수 있는 총량을 보여 주고,
`refreshIntervalMin`은 그 총량을 다시 스캔하는 간격입니다.

```bash
omarchy bar set io.github.e2goon.omasweep showSize true --json
omarchy bar set io.github.e2goon.omasweep refreshIntervalMin 60 --json
```

## 파일

| 경로 | 용도 |
| --- | --- |
| `~/.config/omasweep/whitelist` | 보호할 경로와 건너뛸 대상 |
| `~/.local/state/omasweep/operations.log` | 모든 삭제, 명령, 건너뜀, 실패 기록(5MB마다 교체) |

## 개발

```bash
git clone https://github.com/e2goon/omasweep.git ~/Work/omasweep
ln -s ~/Work/omasweep ~/.config/omarchy/plugins/io.github.e2goon.omasweep
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.e2goon.omasweep
tests/run.sh
```

`tests/run.sh`는 실제 시스템을 건드리지 않습니다.

- 문법을 검사하고, `shellcheck`가 있으면 실행합니다(`uvx --from shellcheck-py shellcheck`도 됩니다).
  Omarchy 셸 모듈을 기준으로 `qmllint`를 돌리고 플러그인 매니페스트를 검사합니다.
- `sudo`, `paccache`, `pacman`, `journalctl`, `mise`, `docker`, `uv`, `go`, `pnpm`, `flatpak`, `ps`를
  인자만 기록하는 가짜 명령으로 바꿔서, 모든 정리 명령을 정확히 검증합니다.
- 버려도 되는 홈 폴더에서 실제로 정리해 보고, 지워져야 할 것과 남아야 할 것(화이트리스트 경로, 심볼릭
  링크 대상, 실행 중인 앱의 캐시, 최근 프로젝트, `$HOME` 밖의 모든 것)을 확인합니다.

심볼릭 링크로 연결한 체크아웃에서 `BarWidget.qml`을 고쳤다면 `omarchy restart shell`로 다시 불러옵니다.

플러그인은 [Omarchy 셸 플러그인 매뉴얼](https://github.com/omacom/omarchy/blob/quattro/manual/32-shell-plugins.md)과
[셸 레퍼런스](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md)를 따릅니다.

## 감사의 말

CLI 흐름(미리 보기, 화이트리스트, 작업 로그, 사용 중인 앱 건너뛰기, 여유 공간 요약)은 tw93의 macOS 정리
도구 [Mole](https://github.com/tw93/mole)에서 아이디어를 얻었습니다. omasweep은 Mole과 코드를 공유하지
않으며 관련도 없습니다.

## 라이선스

[MIT](LICENSE)
