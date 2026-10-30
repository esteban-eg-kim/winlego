# <img src="docs/logo/winlego-512.png" alt="" width="40"> winlego

[English](README.md) · **한국어** · [웹사이트](https://xkorfun.github.io)

**창을 영역에 맞춰 넣고, 그 자리를 지킵니다.**

모니터가 여러 대면 창이 자꾸 흩어집니다. 앱이 제멋대로 예전 자리로 돌아가고,
모니터가 깨어나면 전부 뒤섞이고, 아침마다 창을 끌어다 놓는 데 시간을 씁니다.
winlego 는 디스플레이마다 영역 레이아웃을 정하고, 창을 영역에 넣고, 그 자리를
지켜 주는 작은 macOS 메뉴바 앱입니다.

<p align="center">
  <img src="docs/media/demo-ko.gif" alt="winlego 데모: ⇧ 를 누른 채 끌어 창을 영역에 넣고, ⌃ 로 영역을 합치고, 두 창 사이 경계를 끌고, 앱이 창을 옮겨도 제자리로 돌아오는 모습" width="720">
</p>

<p align="center"><a href="docs/media/demo-ko.mp4">고화질로 보기 (MP4)</a></p>

## 기능

- **디스플레이마다 레이아웃.** 반반, 3열, ⅔ + ⅓, 2×2 격자, 넓은 열 + 옆에 둘 쌓기,
  세로 모니터용 상하, 작은 모니터용 전체 화면. 에디터로 직접 그릴 수도 있습니다.
- **창을 넣는 방법 네 가지.** `⇧` 를 누른 채 끌어서 영역에 놓기. 끌기 시작한 뒤 `⌃` 까지
  누르면 지나간 영역들을 하나로 합쳐 채우기. `⌃⌥←` / `⌃⌥→` 로 영역 순환, `⌃⌥↑` / `⌃⌥↓` 로
  디스플레이 이동(단축키는 바꿀 수 있음). 메뉴바에서 영역 고르기. 또는 규칙:
  *터미널은 항상 메인 디스플레이 오른쪽 1/3.*
- **자리를 지킵니다.** 앱이 창을 옮기거나 모니터가 절전에서 깨어나 창이 밀려나면
  되돌립니다. 직접 끌어다 놓으면 배정이 풀립니다. winlego 는 사용자와 싸우지 않습니다.
- **실제 화면에서 영역 크기 조절.** 배정된 창 두 개가 맞닿은 경계를 끌면 양쪽 창이
  실시간으로 따라옵니다. 놓으면 새 비율을 그 디스플레이의 레이아웃으로 저장할지 묻습니다.
- **권한 하나, 네트워크 없음.** 손쉬운 사용 권한만 씁니다. 수집하는 것 없음.
- **한국어와 영어.** 시스템 언어를 따릅니다.

## 설치

```sh
brew install --cask esteban-eg-kim/tap/winlego
```

또는 [Releases](https://github.com/esteban-eg-kim/winlego/releases) 에서 `winlego-x.y.z.zip` 을
받아 `winlego.app` 을 `/Applications` 로 옮기고, 한 번만 실행하세요:

```sh
xattr -dr com.apple.quarantine /Applications/winlego.app
```

서명은 했지만 공증은 하지 않아서(유료 Apple 개발자 계정 없음) 이 줄이 없으면 macOS 가
열기를 거부합니다. Homebrew 로 설치하면 알아서 처리합니다. macOS 13 이상,
Apple silicon 과 Intel 모두 지원합니다.

## 빠른 시작

1. winlego 를 열고 시스템 설정 › 개인정보 보호 및 보안 › **손쉬운 사용**(macOS 27 에서는
   **기기 제어 및 데이터 접근**)에서 허용합니다.
2. 메뉴바의 격자 아이콘 › **Layouts** 에서 디스플레이마다 레이아웃을 고릅니다.
3. `⇧` 를 누른 채 창을 끌어 영역에 놓습니다. 또는 `⌃⌥→`.
4. 마음에 들면 **Remember This Window Here**. 이제 그 앱의 창은 늘 거기서 열립니다.

메뉴 항목, 규칙, 레이아웃 에디터, 문제 해결은 **[매뉴얼](docs/manual.ko.md)** 에
있습니다 ([English](docs/manual.md)).

<p align="center"><img src="docs/img/menu.png" alt="winlego 메뉴: Move Window to, 디스플레이, 영역" width="560"></p>

<p align="center"><img src="docs/img/boundary-ko.png" alt="두 창 사이 경계를 끈 뒤 새 비율을 저장할지 묻는 팝업" width="720"></p>

## 단축키

| 키 | 동작 |
|---|---|
| `⌃⌥←` / `⌃⌥→` | 이 디스플레이의 이전 / 다음 영역 |
| `⌃⌥↑` / `⌃⌥↓` | 이전 / 다음 디스플레이의 같은 영역 |
| `⌃⌥↩` | 모든 창을 규칙대로 정렬 |
| `⌃⌥⌫` | 현재 창을 영역에서 해제 |
| `⇧` + 드래그 | 영역 표시, 놓아서 배정 |
| `⇧` + 드래그, 그다음 `⌃` | 지나간 영역을 합치기, 놓으면 전부 채움 |

단축키는 설정 › General 에서 바꿀 수 있습니다.

## 동작 원리

winlego 는 macOS 손쉬운 사용(Accessibility) API 로 다른 앱의 창을 읽고 옮깁니다.
Rectangle, Amethyst, Magnet 이 쓰는 것과 같은 공개 API 이며, 앱마다 창이 열리고
움직이고 크기가 바뀌는 것을 감시합니다. 레이아웃은 분할 트리라서 두 영역 사이의
경계는 분할 하나의 비율입니다. 경계를 끌면 그 비율이 바뀌고 영향 받는 영역의 창이
전부 따라옵니다. 순수 로직(레이아웃, 영역 기하, 규칙, 유지 정책)은 `WinlegoCore` 에
단위 테스트와 함께 있고, 앱 타깃은 그 위의 AppKit·SwiftUI 껍데기입니다.

맥 앱스토어는 샌드박스를 요구하고 샌드박스 앱은 손쉬운 사용 API 를 쓸 수 없기
때문에, 2012년 이후 나온 다른 창 관리 앱들처럼 winlego 도 직접 배포합니다.

## 개발

```sh
scripts/test.sh                      # 단위 테스트 (WinlegoCore)
swift build                          # 디버그 빌드
ARCHS=arm64 scripts/bundle.sh        # build/winlego.app, 서명 포함
scripts/release.sh 0.2.1             # dist/winlego-0.2.1.zip
docs/media/make.sh                   # 스크린샷과 데모 (Chrome, Node 22)
scripts/make-icon.sh                 # Resources/AppIcon.icon 으로 앱 아이콘 (Xcode)
```

로그: `/usr/bin/log show --last 5m --info --predicate 'subsystem == "io.github.esteban-eg-kim.winlego"'`.

## 라이선스

MIT. [LICENSE](LICENSE) 참고.
