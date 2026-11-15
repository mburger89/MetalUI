# MetalUI website (GitHub Pages) — design

Date: 2026-11-15. Status: draft for approval.

## Intent

A public site that gets Swift developers to **try MetalUI today**. A visitor
should land, understand in seconds what it is, and have an app running in a
few minutes. Every element on the page serves that one action (user, 2026-11-14).

## Audience

Swift developers, especially ones who know SwiftUI, including those who want
a native UI on Linux or Windows where SwiftUI does not exist.

## Goals

- First screen: one-line pitch, the quick-start commands, the generated app's
  code beside a real screenshot of it running.
- "If you know SwiftUI, you know this": short side-by-side SwiftUI / MetalUI
  snippets.
- Linux and Windows shown on equal footing with macOS (the reason to pick
  MetalUI over SwiftUI).
- Showcase of real apps built on it: **Alloy, MetalCreator, MetalFlow**
  (user-approved 2026-11-14), each with a screenshot, one line, and a link to
  its public repo (github.com/mburger89/Alloy, /MetalCreator, /MetalFlow).
- Performance evidence from real use (e.g. one frame per keystroke, measured
  reductions from the Alloy work), stated with what was measured.
- "Experimental — the API still changes" said once, plainly, next to the
  install step.
- Links: GitHub repo, getting-started guide, the guides, the honest
  divergences list (`docs/divergences.md`), and the **DocC API reference**.

## Non-goals

- Rendering the repo's markdown docs as site pages (they stay on GitHub).
- The internal record, rules, specs and probes — never published on the site.
- Blog, newsletter, analytics, comments, search.
- iOS/iPadOS/tvOS/watchOS/visionOS — explicit product boundary (PB-A); the
  site must not imply support.

## Anti-goals (failure even if it "works")

- A quick start that fails from a fresh clone.
- Claims the code does not back (features, platforms, numbers). Every number
  cites what was measured.
- Mock-up or fabricated screenshots. Only real captures.
- Hiding that it is experimental.
- Heavy page: no JS framework, no tracking; fast on a phone.

## Approaches

- **A. Hand-built static page + Pages deploy workflow (chosen by the user).**
  HTML/CSS in `site/` on master, published by GitHub Actions. No build tools,
  full design control, cheap to change.
- B. VitePress/Jekyll docs site — rejected: adds Node/Ruby tooling and spends
  effort on docs rather than the try-it-today page; internal docs need
  filtering.
- C. DocC as the whole site — rejected as the front door (reference-style
  landing), **kept as the API reference** linked from the page (user,
  2026-11-15).

## Decided

- Landing page: hand-built, `site/` at repo root, plain HTML + CSS, at most a
  few lines of vanilla JS (e.g. copy-to-clipboard). Responsive, light and dark
  (`prefers-color-scheme`).
- Hosting: GitHub Pages via a GitHub Actions workflow (deploy-pages), from
  master. URL: `https://mburger89.github.io/MetalUI/`.
- API reference: DocC, static-hosted under `/MetalUI/api/`, built in the same
  Pages workflow on a macOS runner, **without adding a package dependency**
  (no swift-docc-plugin in Package.swift): emit symbol graphs from the build
  and run `docc convert --transform-for-static-hosting
  --hosting-base-path MetalUI/api`. Primary module: `MetalUI`. A DocC catalog
  (`Sources/MetalUI/MetalUI.docc`) with a landing article that points back to
  the site and to getting-started.
- Showcase: Alloy, MetalCreator, MetalFlow.

## Constraints

- Repo is public, MIT. Pages must be enabled with source "GitHub Actions"
  (repo setting) — **the user enables it, or explicitly approves Claude doing
  it via `gh api`**; Claude does not change repo settings unasked.
- Setting the repo's homepage URL to the site likewise needs the user's OK.
- Screenshots must be real captures. macOS: `docs/probes/window-capture/`
  method (window by id, no shadow; screen unlocked). Showcase apps: captured
  from current builds on this Mac (computer use is available; their sessions
  can also supply captures). Linux: SDL backend under Docker/llvmpipe (headless
  render to PNG). Windows: the UTM VM is currently unreachable, so a Windows
  screenshot may come from CI artifacts (Build and replay, Windows x64 D3D12)
  or be omitted until available — never faked.
- Quick start must be verified from a fresh clone on macOS and on Linux
  (Docker) before launch; the Docker container, image and volumes are deleted
  afterwards.
- DocC build must not break or slow the existing `swift.yml` CI; the Pages
  workflow runs only on master pushes (and manual dispatch).
- Fonts/assets self-hosted or system fonts; no third-party trackers.

## Answers to the builder check (2026-11-15)

Answered by the project:

- **Quick start per platform.** macOS is the README/getting-started block as
  is. Linux and Windows add `--cross-platform` to `metalui new` and need SDL3
  installed (`docs/guides/cross-platform.md`). The page shows the platforms as
  tabs (or blocks) and each is verified from a fresh clone. The generated
  `Package.swift` pins MetalUI to `git merge-base HEAD origin/master`, which
  always exists on GitHub (`SC-I`, getting-started.md).
- **Doc links** go to `github.com/mburger89/MetalUI/blob/master/docs/...`;
  the repo is public and those files live on master.
- **Performance numbers** come from `docs/record/` (e.g. FP-N/FP-O record for
  one frame per keystroke, records 300–306) and the measurements Alloy
  reported to this session; quote only ones written in the record, with what
  was measured.

Claude's calls (correct any):

- **Runner/toolchain:** the Pages workflow uses the same `xcode-27` runner as
  `swift.yml` (the package needs Swift 6.4; stock images can't build it). If
  the DocC job fails, the deploy fails and the previous site stays live — no
  landing page with a dead API link.
- **DocC scope:** one archive for `MetalUI` that includes the modules it
  `@_exported`s (`MetalUICore`, `MetalUILayout`, `MetalUIPlatform`,
  `MetalUIPrimitives`, `MetalUITextSystem`, `MetalUIRender`,
  `MetalUICodeBuffer`, `MetalUIMarkdown`), with a curated landing page and
  topic groups. `MetalUITesting` is a second, smaller archive if it builds
  cleanly; otherwise later.
- **DocC catalog:** `Sources/MetalUI/MetalUI.docc` is ignored by SwiftPM
  builds on every platform; the closeout scripts census Swift declarations
  only, so they are unaffected. Links back to the site are absolute URLs.
  The workflow must not change `swift.yml` or test counts.
- **Screenshots:** Claude captures them on this Mac (computer use, window-by-id
  method). Showcase apps are captured from their current builds with demo
  content only — sample project, no private files, sessions or tokens visible.
  Linux comes from the SDL backend in Docker. A missing Windows capture does
  **not** block launch: Windows is listed as supported (CI-verified on every
  PR) with its screenshot added when the VM is back. Never faked.
- **Images** are committed under `site/` as optimised PNG/WebP, budget about
  1.5 MB total.
- **Base path** `/MetalUI/`, no custom domain, `.nojekyll`, a small 404 page.

## Left to the builder

- Visual design (palette, type, layout), within: code-forward, quiet, fast,
  dark-mode aware. A natural start is the framework's own theme tokens.
- Exact copy, snippet choice, section order below the fold.
- Which performance numbers to quote (from docs/record and the Alloy work),
  as long as each states what was measured.
- Whether DocC also covers MetalUITesting / other products.
- Image formats and sizes (keep total page weight small).
