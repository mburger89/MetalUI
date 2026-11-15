# Quick start, verified

Source of truth for the landing page's code blocks (not published). Verified 2026-11-15 from a fresh
clone of the public URL, with Swift 6.4.2 (`swift-6.4.2-RELEASE`). MetalUI master at the time:
`bda5d8fb8cc7ed6e621e43191d940363f8ab975e` (the commit the generated app pinned).

## macOS

Verified on macOS 27.2, arm64 (Apple Silicon), Swift 6.4.2.

```sh
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp
cd MyApp && swift run MyApp
```

Output of `metalui new` (last lines):

```text
Created /…/MyApp

  cd /…/MyApp
  swift run MyApp

MetalUI is pinned to bda5d8fb8cc7ed6e621e43191d940363f8ab975e; README.md says how to update it.
```

Result: `swift run MyApp` builds and the process stays running with its window open (still alive after
8 s; stopped by hand). `swift test` in `MyApp` passes: `pressingTheButtonCountsThePress()` (1 test, 0
failures). Not verified here: x86_64 Macs, macOS 14 to 26.

## Linux

Verified in a clean `swift:6.4-noble` container (Ubuntu 24.04, Swift 6.4.2, **aarch64**), the image
family of the repo's Linux CI. The image has no SDL3, so the SDL3 step below is required (Ubuntu 24.04
ships only SDL2). Run as root; with `sudo` on a normal machine.

```sh
# 1. SDL 3.4 or later, from source (needs git, cmake, a C compiler; the image has the compiler)
apt-get install -y cmake ninja-build pkg-config libx11-dev libxext-dev libxrandr-dev \
  libxcursor-dev libxi-dev libxfixes-dev libxss-dev libxtst-dev libxkbcommon-dev \
  libwayland-dev wayland-protocols libegl-dev libdecor-0-dev
git clone --depth 1 --branch release-3.4.16 https://github.com/libsdl-org/SDL.git
cmake -S SDL -B SDL/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DSDL_AUDIO=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build SDL/build && cmake --install SDL/build && ldconfig

# 2. The app
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp --cross-platform
cd MyApp

# 3. AccessKit's C bindings, once (needs python3, curl; on aarch64 also a Rust toolchain)
swift package resolve
python3 .build/checkouts/MetalUI/Backends/SDL/scripts/fetch-accesskit.py --prefix /usr

# 4. Build and run
swift run MyApp
```

Verified: steps 1 to 3, then `swift build` and `swift test` in `MyApp` both succeed
(`pressingTheButtonCountsThePress()` passes; `SDL_VIDEO_DRIVER=offscreen` set for the test run).
`swift run MyApp` was not run: the container has no display, and an app never falls back to
offscreen. On aarch64 the AccessKit script printed `no prebuilt AccessKit for Linux aarch64; building
from source with cargo`, so a Rust toolchain was installed first
(`curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal`); on x86_64 it downloads a prebuilt
library (not run here). `metalui new --cross-platform --no-accesskit` skips step 3 entirely.

## Windows

CI-verified, not run here. Copied from `docs/guides/cross-platform.md` and `docs/getting-started.md`:

```sh
swift run --package-path MetalUI metalui new MyApp --cross-platform
```

Windows needs SDL3's prebuilt Visual C++ package (`SDL3-devel-3.4.16-VC.zip`) unpacked and its paths
handed to SwiftPM, plus AccessKit's flags from `fetch-accesskit.py --print-flags`; `SDL3.dll` and
`MetalUISDLShaders` go beside the executable. A generated app has not been built on Windows (human
check X4).

## Doc fixes made by this verification

- `docs/getting-started.md`, "What a Linux machine needs", item 1: it said to build SDL from source
  but gave no commands; the Ubuntu 24.04 commands above were added.
