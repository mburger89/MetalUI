# 385 - the `metalui` CLI release (`SC-J`)

Branch `feat/cli-release` on master `73e1f5cc`. Class M, no divergence. Prepares `metalui` for Homebrew: the first release is 0.1.0 (tag `v0.1.0`).

**Problem.** Homebrew builds the CLI from the release's source archive in a temporary directory it deletes afterwards. `SC-I`'s lookup (`scaffolderCheckout` = `#filePath`, `lookUpPin`) finds no git checkout there, so `metalui new` silently wrote `.package(url:, branch: "master")`, unpinned.

**Change.** `Version.swift` holds `metaluiVersion`; `metalui --version` / `-V` prints `metalui 0.1.0`. `GitReference.release(String)`. Order (`SC-J`): checkout pin, else the release version on the default URL (`.upToNextMinor(from:)` for 0.x, `from:` from 1.0), else the branch and its note. `.github/workflows/release.yml` (tag `v*`): checks the tag against `metaluiVersion`, builds `metalui` in release, smoke-runs `--version` and `new Smoke`, creates the GitHub release with `metalui-<version>-macos-arm64.tar.gz` and its `.sha256`. `docs/packaging.md` "Releasing" lists the steps including the tap formula.

**Measured.** A `git archive HEAD` copy (not a git checkout) built in release; its `metalui new Probe` wrote `.package(url: "https://github.com/mburger89/MetalUI.git", .upToNextMinor(from: "0.1.0")),`; `swift package dump-package` parsed it as 0.1.0..<0.2.0, also with `--cross-platform` (traits). The same binary built in the worktree writes the commit pin. The workflow was not run (no tag pushed).

**Tests.** `ReleaseTests` (each of the three cases, a fork, explicit flags, the requirement text, `--version`, the CLI message); mutations are in its header.

**Deferred.** The tap repository and its formula (url + sha256 of the source archive) are made by hand after the first tag.

**Later: all platforms.** `release.yml` now has build jobs for macOS arm64, Linux x86_64 and aarch64 (`swift:6.4-noble`, `--static-swift-stdlib`) and Windows x64 (`-Xswiftc -static-stdlib`), one `publish` job (create, or upload with `--clobber`), a `workflow_dispatch` `tag` input for an existing tag, and a `pull_request` trigger that builds without publishing. Measured on PR #395: all four binaries are self-contained (Linux runs in plain `ubuntu:24.04`; Windows runs with only `System32` on `PATH`; no DLLs bundled), about 24 MB each; no CLI source change was needed. The publish job and the dispatch were not run.
