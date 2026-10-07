#!/bin/bash
# SwiftPM probe: can ONE package expose an SDL backend behind package traits so
# that (a) its own `swift build` and every consumer that does not ask for the
# backend see ZERO warnings and need no SDL, and (b) a consumer depending on it
# by git URL turns the backend on with `traits:`? Evidence for ruling PX-H
# (docs/superpowers/2026-10-07-portable-app-decisions.md).
#
# HOW TO RUN: bash run.sh <scratch-dir> <arm>
#   arms: make            write dep/ (a git repo) and app/ (depends on dep by file:// URL)
#         mac             macOS arms M1–M5 (needs `brew install sdl3` for M5)
#         noble           Linux arms L1–L2 in swift:6.4-noble (no SDL, no AccessKit)
#         portable        Linux arms L3–L5 in the metalui-portable image (SDL3 in
#                         /usr/local, AccessKit in /opt/accesskit; Backends/SDL/linux/Dockerfile)
#   variant: PKGCONFIG=1 bash run.sh <dir> make   declares the two system
#         libraries WITH pkgConfig: "sdl3" / "accesskit" (arms M1p, M2p)
#
# The toy: `Core` (no SDL), system libraries `CSDL` (<SDL3/SDL.h>, link SDL3)
# and `CAK` (<accesskit.h>, link accesskit), a C target `Bridge` whose SDL code
# is behind a trait-defined macro, and `Back` (Swift, `#if SDL`/`#if AccessKit`)
# — MetalUI's SDLBridge/MetalUISDL shape. Traits: SDL; AccessKit (enables SDL).
#
# RECORDED 2026-10-07 by the portable-app design session (macOS 27.0.1, Apple
# Swift 6.4 swiftlang-6.4.0.33.1; Homebrew sdl3 3.4.18; OrbStack, images
# swift:6.4-noble and metalui-portable built from 359444e's Dockerfile, aarch64):
#
#   M1p (pkgConfig variant) dep `swift build --build-tests`, default build system, no traits:
#     warning: 'dep': prohibited flag(s): -Wl,-rpath,/opt/homebrew/lib
#     warning: 'dep': couldn't find pc file for accesskit
#     Build complete!
#   M2p (pkgConfig variant) app `swift build` (consumer, macOS, default traits): the SAME two
#     warnings, attributed to 'dep' — every consumer would see them. (`--build-system
#     native`: no warning in either.)
#   M1  dep, no pkgConfig, default build system: Build complete!, 0 warnings; test prints "no sdl -1"
#   M2  dep, no pkgConfig, --build-system native: Build complete!, 0 warnings
#   M3  app, no pkgConfig, default build system: Build complete!, 0 warnings; runs "no sdl -1"
#   M4  dep `--traits SDL` with no flags: (not recorded separately; SDL3/SDL.h is not on
#       macOS's default include path, Homebrew's prefix must be passed)
#   M5  dep `swift build --traits SDL -Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib`:
#       Build complete!; test prints "sdl 3004018". One linker warning when the test
#       links: "ld: warning: building for macOS-14.0, but linking with dylib
#       .../libSDL3.0.dylib which was built for newer version 27.0" (Homebrew's dylib)
#   L1  noble, dep `swift build --build-tests`, no traits: Build complete!, 0 warnings; "no sdl -1"
#   L2  noble, app (traits SDL + AccessKit on Linux), no SDL installed:
#       Bridge.c: fatal error: 'SDL3/SDL.h' file not found; error: Build failed
#   L3  portable image, app, no flags: error: 'accesskit.h' file not found (SDL3's
#       header in /usr/local/include WAS found)
#   L3b portable image, app, CPATH=<accesskit include> LIBRARY_PATH=/opt/accesskit/lib:
#       error: 'accesskit.h' file not found — the Swift importer ignores CPATH
#   L4  portable image, app, -Xcc -I<accesskit include> -Xlinker -L/opt/accesskit/lib:
#       /usr/bin/ld.gold: error: cannot find -lSDL3 (libSDL3.so is in /usr/local/lib,
#       not on gold's default search path)
#   L5  portable image, app, L4's flags + -Xlinker -L/usr/local/lib:
#       Build complete!, 0 warnings; runs "sdl 3004016 ak 8"
#   N1  (separate check) a root target declared with `path: "Sub/Sources/Inner"` inside
#       a nested package directory `Sub/` (with its own Package.swift that depends on
#       the root by path and uses the product): both packages build, both build
#       systems, 0 warnings.
#
# READING NOTES.
# - A `.systemLibrary(pkgConfig:)` target is asked of pkg-config by the default
#   build system whether or not anything uses it — warnings in the declaring
#   package AND in every consumer (M1p/M2p). Without `pkgConfig:`, nothing
#   (M1–M3, L1). So MetalUI's root may declare the SDL system libraries only
#   WITHOUT pkgConfig.
# - Package traits gate the SDL code completely: target-dependency conditions,
#   cSettings defines and linker settings all take `.when(traits:)`, and a trait
#   is a Swift compilation condition in the declaring package (M5, L5).
# - Without pkg-config the consumer reaches headers and libraries through the
#   compiler's default paths (/usr/include, /usr/lib/<triple>) or through
#   `-Xcc -I… -Xlinker -L…` (L3–L5); CPATH does not reach the Swift importer.
set -euo pipefail
D=${1:?scratch dir}; ARM=${2:?arm}
case "$ARM" in
make)
  rm -rf "$D/dep" "$D/app"; mkdir -p "$D/dep/Sources/"{Core,CSDL,CAK,Back,Bridge/include} "$D/dep/Tests/BackTests" "$D/app/Sources/App"
  cd "$D/dep"
  if [ "${PKGCONFIG:-0}" = 1 ]; then CSDL='.systemLibrary(name: "CSDL", pkgConfig: "sdl3")'; CAK='.systemLibrary(name: "CAK", pkgConfig: "accesskit")'
  else CSDL='.systemLibrary(name: "CSDL")'; CAK='.systemLibrary(name: "CAK")'; fi
  cat > Package.swift <<EOF
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "Dep",
    products: [.library(name: "Core", targets: ["Core"]), .library(name: "Back", targets: ["Back"])],
    traits: [
        .trait(name: "SDL", description: "the SDL3 backend"),
        .trait(name: "AccessKit", description: "the backend's screen-reader bridge", enabledTraits: ["SDL"]),
    ],
    targets: [
        .target(name: "Core"),
        $CSDL,
        $CAK,
        .target(name: "Bridge",
                dependencies: [.target(name: "CSDL", condition: .when(traits: ["SDL"]))],
                cSettings: [.define("DEP_SDL", .when(traits: ["SDL"]))],
                linkerSettings: [.linkedLibrary("SDL3", .when(traits: ["SDL"]))]),
        .target(name: "Back",
                dependencies: ["Core", "Bridge", .target(name: "CAK", condition: .when(traits: ["AccessKit"]))]),
        .testTarget(name: "BackTests", dependencies: ["Back"]),
    ]
)
EOF
  echo 'public func core() -> Int { 1 }' > Sources/Core/Core.swift
  printf 'module CSDL [system] {\n  header "shim.h"\n  link "SDL3"\n  export *\n}\n' > Sources/CSDL/module.modulemap
  echo '#include <SDL3/SDL.h>' > Sources/CSDL/shim.h
  printf 'module CAK [system] {\n  header "shim.h"\n  link "accesskit"\n  export *\n}\n' > Sources/CAK/module.modulemap
  echo '#include <accesskit.h>' > Sources/CAK/shim.h
  echo 'int bridge_sdl_version(void);' > Sources/Bridge/include/Bridge.h
  printf '#include "Bridge.h"\n#ifdef DEP_SDL\n#include <SDL3/SDL.h>\nint bridge_sdl_version(void) { return SDL_GetVersion(); }\n#else\nint bridge_sdl_version(void) { return -1; }\n#endif\n' > Sources/Bridge/Bridge.c
  cat > Sources/Back/Back.swift <<'EOF'
import Core
import Bridge
#if AccessKit
import CAK
#endif
public func backend() -> String {
    #if SDL
    var s = "sdl \(bridge_sdl_version())"
    #else
    var s = "no sdl \(bridge_sdl_version())"
    #endif
    #if AccessKit
    s += " ak \(MemoryLayout<accesskit_node_id>.size)"
    #endif
    return s
}
EOF
  printf 'import Testing\nimport Back\n@Test func t() { print(backend()) }\n' > Tests/BackTests/T.swift
  git init -q && git add -A && git -c user.email=probe@local -c user.name=probe commit -qm dep
  REV=$(git rev-parse HEAD); cd "$D/app"
  cat > Package.swift <<EOF
// swift-tools-version: 6.4
import PackageDescription
#if os(Linux) || os(Windows)
let depTraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let depTraits: Set<Package.Dependency.Trait> = [.defaults]
#endif
let package = Package(
    name: "App",
    dependencies: [.package(url: "file://$D/dep", revision: "$REV", traits: depTraits)],
    targets: [.executableTarget(name: "App", dependencies: [.product(name: "Back", package: "Dep")])]
)
EOF
  printf 'import Back\nprint(backend())\n' > Sources/App/main.swift ;;
mac)
  cd "$D/dep"; echo "M1"; swift build --build-tests 2>&1 | grep -E "warning|error|Build complete" || true
  echo "M2"; swift build --build-system native --build-tests --scratch-path .bn 2>&1 | grep -E "warning:|error|Build complete" | grep -v deprecated || true
  cd "$D/app"; echo "M3"; swift build 2>&1 | grep -E "warning|error|Build complete" || true
  cd "$D/dep"; echo "M5"; swift test --traits SDL -Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib --scratch-path .b5 2>&1 | grep -E "warning|error|^sdl|^no sdl" || true ;;
noble)
  docker run --rm -v "$D":"$D" -w "$D/dep" swift:6.4-noble bash -c '
    echo L1; swift build --build-tests --scratch-path /tmp/b 2>&1 | grep -E "warning|error|Build complete"; swift test --skip-build --scratch-path /tmp/b 2>&1 | grep -E "^(no sdl|sdl)"
    echo L2; cd ../app; swift build --scratch-path /tmp/a 2>&1 | grep -E "warning|error|Build complete" | head -3' ;;
portable)
  docker run --rm -v "$D":"$D" -w "$D/app" metalui-portable bash -c '
    I=$(ls -d /opt/accesskit/accesskit-c-*/include)
    echo L3; swift build --scratch-path /tmp/a 2>&1 | grep -E "warning|error:|Build complete" | head -3
    echo L3b; CPATH=$I LIBRARY_PATH=/opt/accesskit/lib swift build --scratch-path /tmp/a2 2>&1 | grep -E "warning|error:|Build complete" | head -3
    echo L4; swift build --scratch-path /tmp/a3 -Xcc -I$I -Xlinker -L/opt/accesskit/lib 2>&1 | grep -E "warning|error:|Build complete" | head -3
    echo L5; F="-Xcc -I$I -Xlinker -L/opt/accesskit/lib -Xlinker -L/usr/local/lib"
    swift build --scratch-path /tmp/a4 $F 2>&1 | grep -E "warning|error:|Build complete" | head -3; $(swift build --scratch-path /tmp/a4 $F --show-bin-path)/App' ;;
esac
