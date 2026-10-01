# Platform boundary — decisions (plan task 14)

Ruling for plan task 14: whether "complete SwiftUI alignment" extends to
building SwiftUI's Apple-platform scope (iOS/iPadOS and, by the same design
spec's own deferrals, tvOS/visionOS), or whether macOS-plus-SDL is instead
recorded as an explicit product boundary. Record:
[`../record/65-platform-boundary.md`](../record/65-platform-boundary.md).
No spec of its own — the ruling is the whole of this task's work.

Prefix **`PB-`**, lettered. **Next unused: `PB-B`.** (This line moves in the
commit that appends a ruling; read the last `## PB-` heading.)

---

## PB-A — the boundary is macOS, Linux and Windows; iOS/iPadOS/tvOS/watchOS/visionOS are out of scope

**Decision (user, 2026-09-30).** The plan's task 14 text is conditional: *"If
'complete SwiftUI alignment' includes SwiftUI's Apple-platform scope,
implement and verify iOS/iPadOS platform conformers, touch input, safe areas,
lifecycle and native accessibility. Otherwise record macOS-only as an
explicit product boundary rather than an implied parity claim."* The user
chose the second branch: **record the boundary; do not build iOS/iPadOS.**

The task text's own premise ("MetalUI is macOS-only today") is itself stale
by the time this ruling is written: the cross-platform roadmap
(`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`, rulings
`XP-A`…`XP-C`, record §39/§40) has since landed `Backends/SDL` running on
Linux and Windows through SDL3's GPU backends (D3D12, Vulkan, Metal) with the
portable text pipeline, at pixel parity with the AppKit/Metal path. So the
boundary this ruling records is not "macOS only" but:

- **Supported:** macOS (AppKit + Metal, the default — `App.swift`), and
  Linux and Windows through `Backends/SDL` (`App(platform:textSystem:)`,
  `SDLPlatform`/`SDLWindow`, `XP-A`/`XP-B`). All three are desktop windowing:
  a resizable window, a pointer, a physical keyboard.
- **Not supported, none planned:** iOS, iPadOS, tvOS, watchOS, visionOS. No
  UIKit (or `WindowGroup`-style scene) platform conformer, no touch input
  (`InputEvent.touch`, reserved but unimplemented since the original design,
  spec §8.2), no safe-area insets, no `UIApplication`/scene foreground-
  background lifecycle, no `UIAccessibility` bridge.

**Why.**

1. User decision, stated above — this is the controlling reason.
2. The 2026-09-12 SwiftUI-alignment plan's claim is about **behavioural**
   alignment (layout, composition and identity, state, environment,
   interaction, animation) measured against SwiftUI's own answers — not
   about running on every platform SwiftUI ships on. Nothing in `CLAUDE.md`'s
   "Architecture rules" or the plan's other thirteen tasks depends on a touch
   or scene-lifecycle input model; the platform axis this project has been
   expanding is desktop windowing (macOS → Linux/Windows), a different axis
   from device class (desktop → mobile/TV/headset).
3. The original design spec already deferred tvOS and visionOS for the same
   kind of reason this ruling gives iOS: tvOS "shares the UIKit backend built
   for iOS... but its interaction model is pointerless... which §8.1's
   hitbox-based hit testing assumes exists. Shipping it would mean designing
   a second input model that serves no stated goal" (spec §2). iOS itself
   was never deferred only because the original v1 scope named it a target
   outright — but the same hitbox/pointer assumption (§8.1) and the
   `InputEvent` enum's touch case being reserved, never implemented (§8.2),
   means iOS was never actually built toward either. There is no consumer
   (the validating consumer, spec's own framing, is a desktop Metal shader
   tool) asking for it.

**What would be needed to lift this boundary**, named so a future ruling can
start from an inventory rather than from scratch:

- A `PlatformWindow` conformer over `UIWindow`/`UIViewController` (or a
  `UIScene`), filling the four members this file already calls out as having
  **no default implementation** — `onAccessibilityRequest`,
  `publishAccessibilityTree(_:)` (`AB-R`), `controlActiveState` and
  `onControlActiveStateChange` (`EV-AB`) — whose natural iOS analogues
  (foreground/active vs. background/inactive scene state) are not the same
  shape as a desktop key window.
- A touch input model: `InputEvent.touch(TouchEvent)` is declared, never
  produced or dispatched; pointer-only concepts (`onHover`, cursor affordances,
  "first mouse") do not carry over, though the hitbox ranking (§8.1) likely
  does with a different front end.
- Safe-area insets threaded through `EnvironmentValues` (SwiftUI's own
  `safeAreaInsets`/`.ignoresSafeArea()`) — nothing in MetalUI's environment
  carries one today; there is no notch, home indicator or on-screen keyboard
  concept on any supported platform.
- A scene/application lifecycle (`UIApplication`/`UIScene` or
  `WindowGroup`-style) replacing `App`'s direct, always-foreground window
  creation, and the foreground/background transitions `Window` never models.
- A `UIAccessibility`/`UIAccessibilityElement` bridge — a third accessibility
  backend beside `NSAccessibility` (AppKit) and AccessKit (SDL on all three
  desktop platforms) — or AccessKit's own iOS surface, if AccessKit ships
  one.
- Every SwiftUI probe in `docs/probes/` re-run with a touch/gesture session:
  none was ever recorded against one, only pointer and keyboard input.

**Gaps on the supported platforms a reader might otherwise assume are
covered**, recorded here so this ruling does not read as a broader parity
claim than it is:

- None of macOS, Linux or Windows has touch input, a safe-area concept, or a
  foreground/background app lifecycle as a desktop windowing concept at all
  — this is not a partially-built feature on the supported platforms, it is
  absent from the platforms themselves, and nothing about recording the
  boundary changes that.
- `PlatformWindow`'s `onAccessibilityRequest`, `publishAccessibilityTree(_:)`,
  `controlActiveState` and `onControlActiveStateChange` have no default
  implementations (`AB-R`, `EV-AB` — `CLAUDE.md`'s own opening paragraph
  states this). `AppKitPlatform`/`AppKitWindow` and `SDLPlatform`/`SDLWindow`
  both implement all four today; a third conformer on an already-supported
  platform would still owe them, same as before this ruling.
- VoiceOver itself has only ever been validated by a human on macOS
  (`docs/verification/voiceover-script.md`, plan task 12, part 2) — AccessKit's
  AT-SPI (Linux) and UI Automation (Windows) surfaces are exercised by
  `Backends/SDL`'s own automated tests (`AccessKitTests`,
  `ReplayFixtureTests`) but have no human-run script of their own. That gap
  belongs to task 12's own closure, not to this ruling.
- The real-window capture debt this file tracks throughout (record §03,
  `docs/probes/window-capture/capture.sh`) has only ever been taken, when
  taken at all, against a macOS window; no equivalent capture has ever been
  run against a Linux or Windows window. Recording the platform boundary does
  not close or extend that debt.

**Cost if wrong.** If a later task needs iOS after all, this ruling is
reversed by a new ruling that starts from the "what would be needed" list
above, not by quietly building toward it piece by piece under a different
task's name. Nothing here deletes the design spec's reserved `InputEvent`
cases or the original tvOS/visionOS deferral text (spec §2) — both stay as
history, amended with a dated note pointing here.
