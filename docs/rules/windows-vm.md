# Windows locally: the UTM VM

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

- **Windows locally: the UTM VM** (Windows 11 ARM64, where the machine has
  one; `ssh metalui-win`, PowerShell — `utmctl exec` does not work, ARM64 guest
  tools ship no `qemu-ga`). It runs the CI Windows jobs' commands with SDL's
  `lib\arm64` and AccessKit's ARM64 prebuilt. **Clone with `git clone -c
  core.symlinks=true`** — the shader header is a git symlink and a plain clone
  fails at its line 1. **SDL window tests, `PortableReplay` and `DemoCapture`
  fail over SSH** (session 0, DXGI `0x887A0022`): run them in the console
  session through a temporary `-LogonType Interactive` scheduled task, then
  unregister it. Scripts copied to it are ASCII-only (PowerShell 5.1). Fixtures
  come from `swift run Replay --portable --record` on the Mac. Baseline on
  `c2b8f48`: root 311 (Linux's minus the compiled-out legacy-symbol test),
  PortableTests 32, `Backends/SDL` 24 + 62 (three are macOS-only), replay 8/8
  on WARP.
  **x64 (CI's architecture) runs there under emulation**: `--build-system
  native --triple x86_64-unknown-windows-msvc --scratch-path .build-x64` —
  **the default build system ignores `--triple` and silently emits ARM64**
  (check the PE machine reads `8664`). Running needs the x64 Swift runtime,
  extracted from `Redistributables\6.4.0\rtl.shared.amd64.msm` (`MsiDb.exe -x
  MergeModule.CABinet` under `Start-Process -Wait`, then `expand`), plus the
  SDK's `Testing-6.4.0\usr\bin64` and `XCTest-6.4.0\usr\bin64` first on
  `PATH`, SDL's `lib\x64` and AccessKit's `x86_64` library passed by hand.
  Same counts and pixel deltas as ARM64 on `c2b8f48`.
