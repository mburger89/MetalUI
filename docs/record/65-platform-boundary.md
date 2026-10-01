# 65 — Platform boundary (plan task 14)

Branch `docs/platform-boundary` from `5bba2b4` (master, plan task 13 landed,
record §64). No spec: the plan's task 14 text asks for a decision, not a
design — ruling `PB-A`, `docs/superpowers/2026-09-30-platform-boundary-decisions.md`
(next unused `PB-B`). No probe: the task claims no new SwiftUI behaviour, so
there is nothing for a probe to measure.

**Status: LANDED — plan task 14 is TICKED.** This is a documentation-only
change: `git diff --stat` against `5bba2b4` touches no file under `Sources/`
or `Tests/`. Suite, guard and golden counts are unmoved from record §64's
**1959 / 0 / 119**; `swift build --build-tests` was re-run to confirm 0
`error:` on the unchanged sources.

## §1 The question and the answer

Plan task 14's text is conditional: build iOS/iPadOS platform conformers,
touch input, safe areas, lifecycle and native accessibility if "complete
SwiftUI alignment" is read to include SwiftUI's Apple-platform scope;
otherwise record macOS-only as an explicit boundary. The user decided
2026-09-30: **record the boundary. No iOS/iPadOS work.**

The task's own premise is dated. It was written against "MetalUI is
macOS-only today" — true when the plan was drafted (2026-09-12), false by
the time this task is reached: the cross-platform roadmap
(`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`) has since
landed `Backends/SDL`, running MetalUI on Linux and Windows through SDL3's
GPU backends (D3D12, Vulkan, Metal) with the portable text pipeline, at pixel
parity with the AppKit/Metal path (`XP-A`, `XP-B`, record §39/§40 and every
numbered stage after it that keeps Linux/Windows CI green). So `PB-A`
records the boundary as it actually stands now, not as the task text
describes it:

- **Supported:** macOS (AppKit + Metal, the default), Linux and Windows
  (`Backends/SDL`).
- **Not supported, none planned:** iOS, iPadOS, tvOS, watchOS, visionOS — no
  UIKit conformer, no touch input, no safe areas, no `UIApplication`/scene
  lifecycle, no `UIAccessibility` bridge.

`PB-A` also names what lifting the boundary would need (a `PlatformWindow`
conformer over UIKit filling the two already-defaultless member pairs
`AB-R`/`EV-AB` name, a touch input model realizing the design spec's
reserved `InputEvent.touch` case, safe-area environment values, a scene
lifecycle, a `UIAccessibility` bridge, and a touch/gesture re-run of every
SwiftUI probe) — an inventory for a future ruling to start from, not work
done here.

## §2 Gaps on the supported platforms

The task also asked that this record state what a reader might otherwise
assume is covered on macOS/Linux/Windows but is not — read from `CLAUDE.md`
directly rather than re-derived:

- `PlatformWindow`'s `onAccessibilityRequest`, `publishAccessibilityTree(_:)`,
  `controlActiveState` and `onControlActiveStateChange` have **no default
  implementations** (`CLAUDE.md`'s own opening paragraph, `AB-R`, `EV-AB`).
  Both conformers that exist (`AppKitPlatform`/`AppKitWindow`,
  `SDLPlatform`/`SDLWindow`) implement all four; this ruling changes nothing
  about that obligation for a third conformer on an already-supported
  platform.
- VoiceOver has never been run by a human on any platform yet — the macOS
  script is written but unrun
  (`docs/verification/voiceover-script.md`, plan task 12 part 2, still
  unticked pending that run, record §63). AccessKit's Linux (AT-SPI) and
  Windows (UI Automation) surfaces are exercised by `Backends/SDL`'s own
  automated tests, not by an equivalent human script.
- The real-window capture debt recorded throughout this file (record §03)
  has only ever been taken against a macOS window, when taken at all; no
  Linux or Windows window has ever been captured by a human. This task
  neither closes nor extends that debt.
- Desktop windowing itself has no touch, safe-area or foreground/background
  lifecycle concept on any of the three supported platforms — not a
  partially-built feature, just absent from the platform, unchanged by this
  ruling.

## §3 Documents touched

- `docs/superpowers/2026-09-30-platform-boundary-decisions.md` (new):
  ruling `PB-A`.
- `docs/superpowers/specs/2026-08-24-metalui-design.md` §2: the "v1 targets
  macOS and iOS/iPadOS" line amended with a dated note citing `PB-A`; the
  original sentence kept as quoted history, per the practices doc's
  "state what the grep reads" rule.
- `README.md`: the "no iOS support" line and the "Open: platform
  completeness (task 14)" / "Not done: ... iOS ..." lines updated to the
  closed boundary.
- `CLAUDE.md` (and its byte-identical copy `AGENTS.md`): the opening
  paragraph's "the spec's iOS target is unmet" sentence replaced by the
  explicit boundary statement citing `PB-A`; the decisions-doc prefix list
  gains `PB-` (next `PB-B`); the plan-task bullet list under "Where things
  are" gains a short task 14 entry citing this record (§65).
- `docs/record/README.md`: a new row for `65-platform-boundary.md`.
- `docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`: a note that
  iOS (and tvOS/watchOS/visionOS) is out of scope by `PB-A` — the roadmap's
  own list was always Linux/Windows only, so this is a boundary note, not a
  correction of its list.
- `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`: task 14's box
  ticked, with a dated note citing `PB-A` and this record.

## §4 Verification

`git diff --stat 5bba2b4 -- Sources Tests` is empty — no production or test
file changed. `swift build --build-system native --build-tests` on the
unchanged tree: 0 `error:`, the one pre-existing SwiftPM deprecation
`warning:` under native (0 under the default build system), unmoved from
record §64. `cmp CLAUDE.md AGENTS.md` after `cp CLAUDE.md AGENTS.md`: byte
identical.
