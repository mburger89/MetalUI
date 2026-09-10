import MetalUICore

/// The PAINT-side colour helper: `animated(_:_:for:pass:)`'s sibling, for the
/// one thing that helper structurally cannot do. M4 spec 3
/// (`docs/superpowers/specs/2026-09-03-animation-design.md`) §4's third rule.
///
/// ## Why colour is a different phase, not a shortcut
///
/// Spec §4 requires two `ColorToken`s to interpolate **through their
/// theme-resolved `Hsla`, re-resolved every frame**, and only `PaintPass` has a
/// theme — `PaintPass.theme`'s own doc says it is deliberately absent from
/// `LayoutPass` and `PrepaintPass`, because layout contributes `Style`, which
/// has no colour field at all. `AnimatedStyle.swift` runs in `LayoutPass`. So
/// spec §5's "one choke point" premise is wrong twice over: on site count
/// (four registering sites, not one — Task 4) and on phase count (two, not
/// one — this file).
///
/// ## ONE value is animated, not three fields, and that is the decomposition
///
/// `Box.paint` already selects among `focusBackground` / `hoverBackground` /
/// `background` by pointer and focus state before it draws anything — a
/// left-to-right `??` chain. **This helper animates the resolved RESULT of that
/// chain**, which is a deliberate departure from spec §4's own field list, for
/// two reasons:
///
/// - **hover and focus fades come out free.** CLAUDE.md records a human being
///   unable to read the current static token swap as an affordance at all ("a
///   judgement about two dark greys"); a fade is what makes it legible, and
///   nothing extra had to be built for it.
/// - **animating the three fields separately would interpolate values that are
///   not on screen.** Only one of the three is ever being drawn.
///
/// `hoverAndFocusFadeThroughTheSameEffectiveColourPath` (`AnimationTests.swift`)
/// is what pins the consequence rather than assuming it — it drives a real
/// `Box.paint` through `Frame.render` precisely because the `??` chain lives in
/// `Box.swift` and a test resolving the effective token itself would be blind
/// to a mutation there.
///
/// ## The interpolation space: RGB, and it was MEASURED
///
/// Ruling O left this open and it is closed here. `Hsla.h` is normalised
/// `0..<1`, so a naive per-component lerp from `h = 0.95` to `h = 0.05` travels
/// **backwards through 0.5** — a rainbow sweep through cyan and yellow between
/// two neighbouring reds — and "shortest arc" only moves the problem, still
/// sweeping unrelated hues for any pair more than a sixth of the wheel apart,
/// which is most pairs a theme holds.
///
/// **Two throwaway probes outside the repo, each with a positive control whose
/// answer was known in advance** (black → white must read an achromatic grey
/// strictly between the endpoints — the first run of the CoreAnimation probe
/// FAILED that control, reading `from` exactly, and was fixed rather than
/// believed):
///
/// | probe | blue → orange midpoint | RGB prediction | hue prediction |
/// |---|---|---|---|
/// | SwiftUI, via `Color.Resolved.animatableData` | `(0.4893, 0.5107, 0.7078)` | distance `0.2799` | distance `0.7229` |
/// | CoreAnimation, presentation layer, end-to-end | `(0.5005, 0.3238, 0.4995)` | distance `0.0007` | — |
///
/// **Both say RGB; neither says hue.** So there is no arc, no wrap-around, and
/// no shortest-arc rule to get wrong. The `s = 0.10` assertion in
/// `aBackgroundTokenChangedUnderATransactionReadsAMidFlightColour` is that
/// finding pinned: an RGB midpoint of two saturated colours desaturates toward
/// grey, where every hue-space answer stays saturated.
///
/// **The two probes DISAGREE on the encoding, and this file takes
/// CoreAnimation's.** CoreAnimation lerps in gamma-encoded sRGB exactly;
/// SwiftUI lerps in the cube root of linear light (measured at four fractions —
/// black → white reads sRGB `0.1315 / 0.3886 / 0.6813` at `t = 0.25 / 0.5 /
/// 0.75`, matching `srgbEncode(t³)` to four decimals and not matching `t`).
/// `Rgba` already **is** gamma-encoded sRGB, it is the space the compositor
/// blends in (design spec §7.8, CLAUDE.md's `bgra8Unorm`-never-`_sRGB`
/// constraint), and adopting SwiftUI's would introduce the only linearization
/// in the repo. **The cost of being wrong is stated rather than hidden:** a
/// fade's midpoint sits at sRGB `0.5` where SwiftUI's sits at `0.389` — same
/// endpoints, same hue, different pacing. Adopting SwiftUI's is a change to
/// `lerpComponents` below and nothing else.
///
/// ## What this file deliberately did NOT copy from `AnimatedStyle.swift`
///
/// That file's `inFlight` dictionary, its three fast-path gates and its whole
/// `caseTag` decompose/recompose layer exist because it animates **28 fields of
/// two structs**, of two enum types whose cases must not interpolate across
/// each other. This animates **one value**. So there is no dictionary (one
/// optional `ColorAnimation`), no per-field key strings, and no `caseTag`
/// space — `ColorToken` is the only discrete thing here and it is compared
/// natively. What IS copied, because it is about `StateTable` rather than about
/// fields: `peek` before writing, `withState` and never `write` (ruling H), and
/// ruling P's `mark`-when-there-is-nothing-to-write.
@MainActor
func animColorRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-color"))
}

/// One element's whole `$anim-color` slot.
///
/// `token` is the BASELINE — the effective `ColorToken` this element's last
/// frame declared, kept whether or not anything is animating. **It is a token
/// and not a resolved colour, and that is the load-bearing choice in this
/// file**: it is what lets a *theme* change be told apart from a *declaration*
/// change. A theme swap moves `theme[token]` without moving `token`, so it
/// re-resolves the running animation's endpoints instead of being mistaken for
/// a new transition and snapping — which is spec §4 rule 3's "continuous result
/// rather than a jump", and spec §11's risk row naming cached resolved colours
/// as the optimisation that breaks it.
struct AnimatedColorState: Equatable {
    var token: ColorToken
    var inFlight: ColorAnimation?
}

/// One live colour transition.
///
/// **The two ends are asymmetric on purpose.** `toToken` is a token, so the
/// destination re-resolves against every frame's own theme. `from` is a token
/// *when it can be* — the ordinary case, a transition that began from a
/// declared baseline, where spec §4's "re-resolves **both** ends" is honoured
/// exactly — and a fixed `Rgba` when it cannot be: an interruption re-targets
/// from wherever the colour currently IS (spec §7), and a mid-interpolation
/// position is not any token. That exception is the whole of this file's
/// narrowing of spec §4 rule 3, and both halves are pinned by
/// `aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints`' two arms.
struct ColorAnimation: Equatable {
    var from: ColorEnd
    var toToken: ColorToken
    var startTime: Double
    var animation: Animation
    var velocity: RgbaVelocity
}

enum ColorEnd: Equatable {
    case token(ColorToken)
    case fixed(Rgba)

    @MainActor
    func resolve(in theme: Theme) -> Rgba {
        switch self {
        case let .token(token): return theme[token].toRgba()
        case let .fixed(color): return color
        }
    }
}

/// Per-component momentum, carried across frames so a spring interrupted
/// mid-flight re-targets with the velocity it actually has (spec §7). Four
/// `Double`s rather than a `Double`, because four components animate
/// independently and a shared scalar would couple them.
struct RgbaVelocity: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let zero = RgbaVelocity(r: 0, g: 0, b: 0, a: 0)
}

/// The animated effective background colour for `id`, or `nil` when there is
/// nothing to paint.
///
/// `token` is the already-selected effective token — `Box.paint`'s `??` chain
/// result — **not** `decoration.background`. See this file's top doc.
///
/// **A `nil` token returns immediately and touches the state table not at all**,
/// which is a memory decision rather than an oversight. Most boxes in a real
/// tree declare no background; minting a slot for each would put this file on
/// the wrong side of ruling U's whole argument. The consequence is that a
/// `token → nil → token` sequence loses its baseline once the slot is reaped,
/// and reads as a first sighting. That is the right answer anyway: exit
/// transitions are out of scope (spec §8) and a box that was painting nothing
/// has no colour to fade from.
@MainActor
func animatedColor(_ token: ColorToken?, for id: GlobalElementID,
                   pass: inout PaintPass) -> Hsla? {
    guard let token else { return nil }

    let theme = pass.theme
    let declared = theme[token]
    let slotID = animColorRetentionSlot(for: id)
    let now = pass.timestamp
    let transaction = Animation.pendingTransaction

    guard let existing = pass.frame.stateTable.peek(slotID, as: AnimatedColorState.self) else {
        // First sighting: establish the resting baseline rather than animating
        // from an undefined prior state — `animated(_:_:for:pass:)`'s ruling Q,
        // and the same choice SwiftUI makes for a value that appears
        // already-placed.
        let baseline = AnimatedColorState(token: token, inFlight: nil)
        pass.frame.stateTable.withState(slotID, initial: baseline) { $0 = baseline }
        return declared
    }

    var inFlight = existing.inFlight
    var value = declared

    if let running = inFlight {
        // BOTH ends re-resolve against THIS frame's theme, every frame. This is
        // the line step 6's mutation replaces, and the line that makes the
        // phase choice load-bearing rather than decorative.
        let from = running.from.resolve(in: theme)
        let to = theme[running.toToken].toRgba()
        let current = lerpComponents(running.animation, elapsed: now - running.startTime,
                                     from: from, to: to, velocity: running.velocity)

        if token != running.toToken {
            // The DECLARED token changed mid-flight. Note the comparison is on
            // the token, never on the resolved colour: a theme swap must not
            // reach here.
            if let transaction {
                // Interruption re-targets from where the colour IS and with the
                // momentum it has (spec §7), not from `running.from`.
                inFlight = ColorAnimation(from: .fixed(current.value), toToken: token,
                                          startTime: now, animation: transaction,
                                          velocity: current.velocity)
                value = current.value.toHsla()
            } else {
                inFlight = nil
                value = declared
            }
        } else if current.isFinished {
            inFlight = nil
            value = declared
        } else {
            value = current.value.toHsla()
        }
    } else if token != existing.token, let transaction {
        // A genuine declaration change with a transaction in flight. The frame
        // that STARTS a transition reads its own `from` — the baseline, not the
        // target — at elapsed 0.
        inFlight = ColorAnimation(from: .token(existing.token), toToken: token,
                                  startTime: now, animation: transaction,
                                  velocity: .zero)
        value = theme[existing.token]
    }
    // Otherwise: unchanged, or changed with no transaction in flight. Both
    // snap — `value` is already `declared`, and the asymmetry between this
    // branch and the one above is the whole of what `withAnimation` buys.

    let newState = AnimatedColorState(token: token, inFlight: inFlight)
    if newState != existing {
        pass.frame.stateTable.withState(slotID, initial: newState) { $0 = newState }
    } else {
        // Ruling P: nothing to write, but an entry exists — mark it live so it
        // is not reaped while its element is still being produced every frame.
        // `mark` touches neither `isDirty` nor the stored value, so it costs
        // nothing rulings H or I forbid.
        pass.frame.stateTable.mark(slotID)
    }

    if inFlight != nil {
        // **This is the signal Task 5 reads.** `Frame.requestAnotherFrame()`
        // sets `Frame.wantsAnotherFrame`, which `Window.drawFrameIfNeeded`
        // already consumes (`if frame.wantsAnotherFrame { setNeedsRedraw() }`)
        // AFTER the whole render, paint included — so a paint-phase
        // contribution reaches it. Task 5 owns `hasActiveAnimations`; this file
        // deliberately does not declare it.
        pass.requestAnotherFrame()
    }
    return value
}

/// The four components, each through the same `Animation` curve, independently.
///
/// **Clamped to `0...1`, and the reason is a spring, not tidiness.** A
/// `bounce > 0` spring overshoots its target — pinned, by
/// `aBouncySpringOvershootsItsTarget` — so a component genuinely leaves the unit
/// interval mid-flight. `Rgba.toHsla` divides by `1 - |2l - 1|`, which for an
/// out-of-range `l` produces a negative or explosive saturation rather than a
/// colour. Clamping the position (and not the velocity, which must stay real
/// for a re-target to pick up honest momentum) is what keeps an overshooting
/// colour spring on the screen instead of in the weeds.
private func lerpComponents(_ animation: Animation, elapsed: Double,
                            from: Rgba, to: Rgba, velocity: RgbaVelocity)
    -> (value: Rgba, velocity: RgbaVelocity, isFinished: Bool) {
    func component(_ f: Float, _ t: Float, _ v: Double) -> (Float, Double, Bool) {
        let out = animation.value(at: elapsed, from: Double(f), to: Double(t), initialVelocity: v)
        return (Float(min(max(out.value, 0), 1)), out.velocity, out.isFinished)
    }
    let r = component(from.r, to.r, velocity.r)
    let g = component(from.g, to.g, velocity.g)
    let b = component(from.b, to.b, velocity.b)
    let a = component(from.a, to.a, velocity.a)
    return (Rgba(r: r.0, g: g.0, b: b.0, a: a.0),
            RgbaVelocity(r: r.1, g: g.1, b: b.1, a: a.1),
            r.2 && g.2 && b.2 && a.2)
}
