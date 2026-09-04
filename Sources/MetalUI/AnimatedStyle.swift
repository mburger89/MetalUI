import MetalUICore
import MetalUILayout

/// The shared, registration-time helper every styled-node call site substitutes
/// its animated `Style`/`Decoration` through before handing them to the layout
/// engine. M4 spec 3 (`docs/superpowers/specs/2026-09-03-animation-design.md`)
/// §5: there is no single choke point (`Box`, `Stack` and `ScrollView`'s two
/// nodes each call `LayoutPass.requestNode`/`requestLeaf` independently), so
/// this is the mechanism they all call instead — Task 4 wires the four sites,
/// this task builds and pins the mechanism itself.
///
/// **Read this file's storage model before touching it — it is one rule
/// applied uniformly, not a pile of special cases.** Every animatable field
/// reduces to a `Double` plus (for `Length`/`Dimension` fields only) a small
/// case tag whenever it is actually being compared or interpolated numerically;
/// `animateField(_:declared:declaredTag:previous:previousTag:inFlight:transaction:now:)`
/// is the one function every field call routes through once a genuine
/// difference is on the table, and every test below is really a test of that
/// one function through a different field shape.
///
/// ## What is NOT animated here, and why each is a real decision
///
/// - **`aspectRatio`.** Spec §4: it is CLAUDE.md's declared-but-inert `Style`
///   row — read by no production code — and animating a property that does
///   nothing is that table's exact trap, doubled. `newStyle.aspectRatio` is
///   simply never assigned below, so it carries `style.aspectRatio` through
///   unchanged, on every other untouched field's footing (`display`,
///   `position`, and the rest of spec §4's snapping list).
/// - **`Decoration.background` / `hoverBackground` / `focusBackground`.**
///   Spec §4 lists these as animatable, through their theme-*resolved* `Hsla`
///   — and the SUFFICIENT reason this helper does not is the type, not
///   reach: `Decoration.background` is `ColorToken?`, a discrete enum with no
///   addressable intermediate value the way a `Double` has 50 between 0 and
///   100, so there is nowhere to write a "halfway colour" back into it even
///   with a theme in hand. **`Frame.theme` is in fact reachable from here** —
///   it is `internal let`, and this file already reaches `pass.frame` for
///   `stateTable` and `timestamp` — so the earlier form of this paragraph,
///   which called it unreachable, was wrong and has been corrected at this
///   line rather than only in the fix-round report (practices doc mechanism
///   1). `PaintPass.theme`'s own doc — "Deliberately not on `LayoutPass` or
///   `PrepaintPass` … layout contributes `Style`, which has no colour field"
///   — is a **phase-contract boundary this helper honours**, not a wall it
///   is blocked by: colour belongs to paint by design, and reaching around
///   that design through `pass.frame.theme` would be the wrong fix even
///   though it would compile. These three fields therefore pass through
///   unchanged, on `aspectRatio`'s exact footing. **This is a real,
///   reportable narrowing of spec §4's animatable list, not an oversight**
///   — see this task's report for the alternative (a paint-time consumer of
///   this same `$anim` slot, which needs `Box.paint`'s own theme access and
///   was out of this task's scope). A later task has since ruled that colour
///   animates at PAINT instead, off the effective background `Box.paint`
///   already selects by pointer state — hover/focus fades come free there.
///
/// ## Storage (spec §6, RESHAPED by ruling U — Task 4's fix round)
///
/// **The shape that shipped first was one `AnimatedFieldState` per
/// animatable field EVER touched, all 28 of them, in one dictionary — and
/// that dictionary is what cost ~7.5 KB per element, not the ~2.5 KB the
/// 28 payloads themselves take.** Swift's `Dictionary` rounds a 28-entry
/// table up to capacity 64, and each bucket's overhead (hash, tombstone bit,
/// key storage) dwarfs a settled field's actual content. Measured at
/// n = 10,000 rows, cold frame, release: 48.4 → 122.7 MB; at n = 100,000:
/// 664.3 → 1,420.2 MB (+756 MB) — a ship-blocker on M3's own "100k rows"
/// criterion, because the spike is transient (it reaps within ten scroll
/// frames, ruling P's `mark` still works) but 1.42 GB of it is not.
///
/// **The fix is what this section now describes.** A reserved `$anim` child
/// slot under the element's own `GlobalElementID` holds one
/// `AnimatedElementState` — a `style`/`decoration` BASELINE, in their own
/// native `Style`/`Decoration` types, plus an `inFlight` dictionary holding
/// an `AnimatedFieldState` for ONLY the fields genuinely still interpolating
/// right now. A settled element (the overwhelming majority of every frame,
/// for any element not mid-transition) costs one `Style` (`MemoryLayout<Style>.stride`
/// = 228) plus one `Decoration` (12) plus an EMPTY dictionary, rather than a
/// 64-bucket table of 28 mostly-redundant entries. Measured in isolated
/// processes at n = 20,000: **7,503 → 509 bytes per entry** (a bare-`Int`
/// control entry costs 187), a 93% reduction; at n = 100,000 the animation
/// overhead this file adds falls from ~756 MB to ~51 MB.
///
/// **Baseline equality is now native, not tag-decomposed, for the common
/// case.** `Length`/`Dimension` are `Hashable` (hence `Equatable`) in their
/// own right, so "did this field change since the baseline" is `declared !=
/// baseline.<field>` — a native enum comparison — for a field that is not
/// currently in `inFlight`, with no call to `decomposeLength`/
/// `decomposeDimension` at all. Decomposing into a `(tag, Double)` pair
/// still happens, exactly as before, the moment a genuine difference (or an
/// already-running animation) needs numeric interpolation — that machinery
/// is unchanged; only the "is there anything to do here at all" gate in
/// front of it got cheaper.
///
/// This is the FOURTH reserved slot name, joining `$state\(n)`, `$focus` and
/// `$ax` — CLAUDE.md records those three as carrying an identical, unguarded
/// collision risk, and `$anim` inherits it exactly. `ScrollView`'s own two
/// named child ids (`$anim-content`, `$anim-viewport`) are a FIFTH and
/// SIXTH — see that type's own doc and CLAUDE.md's reserved slot list.
/// `theSixRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift`, renamed
/// from `theThreeRetentionSlotsAreMutuallyDistinct` by Task 3 per spec §7
/// item 10, and extended from four to six by Task 4's own fix round) is
/// what pins all of it — one test, extended in place twice rather than
/// replaced.
@MainActor
func animRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim"))
}

/// `ScrollView`'s own two reserved child ids (the fifth and sixth slot
/// names this file's top doc names). `ScrollView.requestLayout` registers
/// two nodes from one element id, and `animRetentionSlot(for:)` derives
/// exactly one `$anim` slot per id it is given — passing the element's own
/// `id` to `animated(_:_:for:)` for both nodes would collide both nodes'
/// fields under the identical slot. A named child per node, on
/// `$state`/`$focus`/`$ax`'s footing, keeps them apart.
///
/// **Exposed as functions rather than inlined at `ScrollView.requestLayout`'s
/// two call sites, and that is load-bearing for `AXNodeTests.swift`'s
/// `theSixRetentionSlotsAreMutuallyDistinct`.** A test that reconstructs
/// `"$anim-content"`/`"$anim-viewport"` as its own string literals cannot
/// catch a rename at the real call site — measured, by making exactly that
/// mistake first: a test built from its own copy of the two strings stayed
/// green under a rename of the real call site's literal. Both
/// `ScrollView.swift` and the test call these same two functions, so a
/// rename in either can only ever be a rename in one place.
@MainActor
func scrollViewContentAnimID(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-content"))
}

@MainActor
func scrollViewViewportAnimID(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-viewport"))
}

/// One element's whole `$anim` slot (ruling U).
///
/// `style`/`decoration` are the BASELINE — the last frame's declared values,
/// in their own native types, kept regardless of whether anything is
/// animating. `inFlight` holds an `AnimatedFieldState` only for fields that
/// are genuinely still interpolating; a settled element's `inFlight` is
/// empty for its entire lifetime unless a caller starts a transition on it.
struct AnimatedElementState: Equatable {
    var style: Style
    var decoration: Decoration
    var inFlight: [String: AnimatedFieldState]
}

/// One animatable field's persisted animation state, UNCHANGED in shape from
/// before ruling U — only its home moved, from a per-field entry that
/// existed for every field ever touched to a per-field entry that exists
/// only while genuinely mid-interpolation.
///
/// **`caseTag` unifies `Length` and `Dimension` into one small tag space so
/// "same case interpolates, different case snaps" (spec §4's three
/// type-system-unenforced rules) is ONE comparison rather than a special case
/// per type**: `0` = `.pixels`, `1` = `.rems`, `2` = `.percent`, `3` = `.auto`
/// (a `Length` field never produces `3` — there is no `Length.auto`). A plain
/// numeric field (`flexGrow`, `flexShrink`, `Decoration.cornerRadius`) always
/// carries tag `0` and can never mismatch, since nothing else ever writes a
/// different tag under its key.
struct AnimatedFieldState: Equatable {
    var caseTag: Int
    var from: Double
    var to: Double
    var startTime: Double
    var animation: Animation
    var velocity: Double
}

/// Substitutes animated values into `style`/`decoration` for `id`, advancing
/// or starting animations as needed, and returns the pair to register instead
/// of the caller's own declared values.
///
/// Spec §5's four steps, in order: (1)/(2) below read the previous frame's
/// baseline via `peek` (never marking on its own — see Ruling P below), (3)
/// starts an animation for each animatable field that differs while a
/// transaction is in flight, and each field call below is (4)'s substitution
/// for that one field. The one `withState` call at the end WRITES only when
/// something this frame needs to be persisted — Ruling I — no new difference
/// on any field, and no field still mid-flight.
///
/// **`withState`, never `write` (Ruling H).** `StateTable.write` raises
/// `isDirty` and fires `onWrite → Window.setNeedsRedraw()`; this helper runs
/// on every frame at every registering site, so `write` here would re-dirty
/// the window every frame regardless of whether anything is actually
/// animating, and the display link would never pause — exactly the hazard
/// CLAUDE.md's `@State` bullet names. `theHelperNeverDirtiesTheStateTable`
/// (`AnimationTests.swift`) pins it across 20 frames of an unchanging style.
///
/// **Ruling P (fix round 1): a settled entry that is NOT written must still
/// be MARKED, whenever one already exists.** Ruling I as originally shipped
/// conflated "nothing to write" with "nothing to do" — a continuously
/// produced but unchanging element called this helper every frame and never
/// touched `marked` on a settled frame, so its `$anim` entry went stale
/// after exactly `StateTable.staleAfterGenerations` (2) sweeps and became
/// eligible for the tombstone reap on the very next one, **even while being
/// produced every frame**. Above `sweepThreshold` this is a churn cycle —
/// reaped and immediately re-minted as a fresh "first sighting" — and worse,
/// a SILENT ONE: a value that changes on the exact frame after its baseline
/// was reaped finds `peek == nil`, is treated as a first sighting, and
/// stores the new value with **no animation at all**. `StateTable.mark(_:)`
/// exists for exactly this shape (`@State`'s own identical case, per its own
/// doc) — it marks without reading, creating, writing, or touching `isDirty`
/// (so it costs nothing either ruling H or I care about) — and is called
/// below whenever an entry already exists but this frame found nothing to
/// write. `aSettledAnimationSurvivesRepeatedSweepsAboveTheThresholdAndStillAnimatesWhenLaterChanged`
/// (`AnimationTests.swift`) pins the fix. Under ruling U's reshaped storage,
/// "nothing to write" is `newState == existing` — the baseline unchanged and
/// `inFlight` unchanged — checked once via `AnimatedElementState`'s own
/// `Equatable` rather than a per-field `dirty` flag.
@MainActor
func animated(_ style: Style, _ decoration: Decoration, for id: GlobalElementID,
             pass: inout LayoutPass) -> (Style, Decoration) {
    let slotID = animRetentionSlot(for: id)
    let now = pass.frame.timestamp
    let transaction = Animation.pendingTransaction

    guard let existing = pass.frame.stateTable.peek(slotID, as: AnimatedElementState.self) else {
        // First sighting of this ELEMENT — not, as before ruling U, of each
        // field independently: there is nothing to diff against yet, so
        // this establishes the resting baseline rather than animating from
        // an undefined prior state, the same choice SwiftUI makes for a
        // value that appears already-placed (ruling Q). `inFlight` starts
        // empty because there is no prior value for any field to differ
        // from yet. This IS "something to store" in Ruling I's sense — see
        // that ruling's own note, now paid once per element instead of once
        // per field.
        let baseline = AnimatedElementState(style: style, decoration: decoration, inFlight: [:])
        pass.frame.stateTable.withState(slotID, initial: baseline) { $0 = baseline }
        return (style, decoration)
    }

    var inFlight = existing.inFlight
    var newStyle = style

    // Fields not currently in flight and unchanged from the baseline never
    // reach `animateField` at all — a native `Length`/`Dimension`/`Float`
    // equality check is cheaper than decomposing into `(tag, Double)`, and
    // it is the path almost every field takes on almost every frame.
    func number(_ key: String, _ declared: Double, _ previous: Double) -> Double {
        if inFlight[key] == nil && declared == previous { return declared }
        return animateField(key, declared: declared, declaredTag: 0, previous: previous, previousTag: 0,
                            inFlight: &inFlight, transaction: transaction, now: now).value
    }

    func length(_ key: String, _ declared: Length, _ previous: Length) -> Length {
        if inFlight[key] == nil && declared == previous { return declared }
        let (declaredTag, declaredRaw) = decomposeLength(declared)
        let (previousTag, previousRaw) = decomposeLength(previous)
        let (value, tag) = animateField(key, declared: declaredRaw, declaredTag: declaredTag,
                                        previous: previousRaw, previousTag: previousTag,
                                        inFlight: &inFlight, transaction: transaction, now: now)
        return recomposeLength(tag: tag, value: value)
    }

    func dimension(_ key: String, _ declared: Dimension, _ previous: Dimension) -> Dimension {
        if inFlight[key] == nil && declared == previous { return declared }
        let (declaredTag, declaredRaw) = decomposeDimension(declared)
        let (previousTag, previousRaw) = decomposeDimension(previous)
        let (value, tag) = animateField(key, declared: declaredRaw, declaredTag: declaredTag,
                                        previous: previousRaw, previousTag: previousTag,
                                        inFlight: &inFlight, transaction: transaction, now: now)
        return recomposeDimension(tag: tag, value: value)
    }

    // Animatable — from `Style` (spec §4). `previous` is read from
    // `existing.style`, the baseline this element's last frame declared.
    let p = existing.style
    newStyle.inset = Edges(top: dimension("inset.top", style.inset.top, p.inset.top),
                           right: dimension("inset.right", style.inset.right, p.inset.right),
                           bottom: dimension("inset.bottom", style.inset.bottom, p.inset.bottom),
                           left: dimension("inset.left", style.inset.left, p.inset.left))
    newStyle.size = Size(width: dimension("size.width", style.size.width, p.size.width),
                         height: dimension("size.height", style.size.height, p.size.height))
    newStyle.minSize = Size(width: dimension("minSize.width", style.minSize.width, p.minSize.width),
                            height: dimension("minSize.height", style.minSize.height, p.minSize.height))
    newStyle.maxSize = Size(width: dimension("maxSize.width", style.maxSize.width, p.maxSize.width),
                            height: dimension("maxSize.height", style.maxSize.height, p.maxSize.height))
    newStyle.margin = Edges(top: dimension("margin.top", style.margin.top, p.margin.top),
                            right: dimension("margin.right", style.margin.right, p.margin.right),
                            bottom: dimension("margin.bottom", style.margin.bottom, p.margin.bottom),
                            left: dimension("margin.left", style.margin.left, p.margin.left))
    newStyle.padding = Edges(top: length("padding.top", style.padding.top, p.padding.top),
                             right: length("padding.right", style.padding.right, p.padding.right),
                             bottom: length("padding.bottom", style.padding.bottom, p.padding.bottom),
                             left: length("padding.left", style.padding.left, p.padding.left))
    newStyle.border = Edges(top: length("border.top", style.border.top, p.border.top),
                            right: length("border.right", style.border.right, p.border.right),
                            bottom: length("border.bottom", style.border.bottom, p.border.bottom),
                            left: length("border.left", style.border.left, p.border.left))
    newStyle.gap = Axes(horizontal: length("gap.horizontal", style.gap.horizontal, p.gap.horizontal),
                        vertical: length("gap.vertical", style.gap.vertical, p.gap.vertical))
    newStyle.flexGrow = Float(number("flexGrow", Double(style.flexGrow), Double(p.flexGrow)))
    newStyle.flexShrink = Float(number("flexShrink", Double(style.flexShrink), Double(p.flexShrink)))
    newStyle.flexBasis = dimension("flexBasis", style.flexBasis, p.flexBasis)

    // `aspectRatio` and every snapping field (`display`, `position`,
    // `overflow`, `flexDirection`, `flexWrap`, `justifyContent`, `alignItems`,
    // `alignContent`, `justifyItems`, `alignSelf`) are never assigned above,
    // so `newStyle` carries `style`'s own current value through untouched —
    // which IS "snap": always the caller's latest declared value, on every
    // frame, transaction or not.

    var newDecoration = decoration
    newDecoration.cornerRadius = Pixels(Float(number("cornerRadius", Double(decoration.cornerRadius.value),
                                                      Double(existing.decoration.cornerRadius.value))))
    // `background` / `hoverBackground` / `focusBackground`: see this file's
    // top-of-file doc. Not assigned above, so they pass through unchanged.

    // Ruling U: the baseline persisted is the CALLER'S declared style/
    // decoration (`style`/`decoration`, not `newStyle`/`newDecoration`),
    // exactly as before — `inFlight` is what carries the mid-animation
    // state, and the baseline is only ever "the last thing the caller
    // asked for", never the interpolated value in between.
    let newState = AnimatedElementState(style: style, decoration: decoration, inFlight: inFlight)
    if newState != existing {
        pass.frame.stateTable.withState(slotID, initial: newState) { $0 = newState }
    } else {
        // Ruling P: nothing to write, but an entry already exists for this
        // element — mark it live so it is not silently reaped while still
        // being produced every frame. `mark` touches neither `isDirty` nor
        // the entry's stored value, so this costs nothing rulings H or I
        // forbid.
        pass.frame.stateTable.mark(slotID)
    }

    return (newStyle, newDecoration)
}

/// Advance or (re)start one field's animation state (spec §5 step 3, §7).
///
/// Reads and — whenever the field is newly differing from its baseline, or
/// already mid-flight — writes `inFlight[key]` in place. Returns the value
/// to use THIS frame and the case tag it was reconstructed with. Callers
/// only reach this once a native equality check has already found a
/// difference or an in-flight entry; the "nothing to do" fast path lives at
/// each of `number`/`length`/`dimension`'s own call sites instead of here.
private func animateField(_ key: String, declared: Double, declaredTag: Int,
                          previous: Double, previousTag: Int,
                          inFlight: inout [String: AnimatedFieldState],
                          transaction: Animation?, now: Double) -> (value: Double, tag: Int) {
    if let running = inFlight[key] {
        let elapsed = now - running.startTime
        let current = running.animation.value(at: elapsed, from: running.from, to: running.to,
                                              initialVelocity: running.velocity)

        let caseChanged = declaredTag != running.caseTag
        let valueChanged = caseChanged || declared != running.to

        if valueChanged {
            // A case change snaps UNCONDITIONALLY, even mid-transaction —
            // spec §4's "three rules the type system does not enforce":
            // `.auto` carries no number, and a percentage's basis is not
            // known here, so neither has a meaningful midpoint against a
            // different case.
            if !caseChanged, let transaction {
                // Interruption re-targets from wherever the field IS right
                // now (§7), not from `running.from` — `current.value`/
                // `.velocity` are exactly that: the current position and
                // momentum, which is `(running.to, 0)` when `running` was
                // already settled and a true mid-flight position/velocity
                // when it was not.
                inFlight[key] = AnimatedFieldState(caseTag: declaredTag, from: current.value, to: declared,
                                                   startTime: now, animation: transaction,
                                                   velocity: current.velocity)
                return (current.value, declaredTag)
            }
            inFlight[key] = nil
            return (declared, declaredTag)
        }

        if current.isFinished {
            // Settled and unchanged from what was last recorded: Ruling I —
            // no difference and no live animation, so this field leaves
            // `inFlight` entirely — ruling U's whole point, a settled field
            // costs nothing beyond its slice of the baseline.
            inFlight[key] = nil
            return (declared, declaredTag)
        }

        // Still animating toward the same target the last frame declared:
        // return the interpolated position and leave the entry as is —
        // nothing about its content has changed, so it stays marked and
        // survives the tombstone reap while it is genuinely still live.
        return (current.value, running.caseTag)
    }

    // Not currently in flight. The caller already knows `declared !=
    // previous` (that is why this function was reached at all), but the
    // CASE may or may not have changed, which decides snap versus animate.
    let caseChanged = declaredTag != previousTag

    if !caseChanged, let transaction {
        // The frame that STARTS a transition reads its own `from` — the
        // baseline value, not the target — at elapsed 0 of whatever curve
        // begins here.
        inFlight[key] = AnimatedFieldState(caseTag: declaredTag, from: previous, to: declared,
                                           startTime: now, animation: transaction, velocity: 0)
        return (previous, previousTag)
    }

    // No transaction in flight, or a case change (which never
    // interpolates): snap immediately.
    return (declared, declaredTag)
}

// MARK: - Length / Dimension <-> (tag, Double)

private func decomposeLength(_ l: Length) -> (tag: Int, value: Double) {
    switch l {
    case let .pixels(p): return (0, Double(p.value))
    case let .rems(r): return (1, Double(r.value))
    case let .percent(f): return (2, Double(f))
    }
}

private func recomposeLength(tag: Int, value: Double) -> Length {
    switch tag {
    case 0: return .pixels(Pixels(Float(value)))
    case 1: return .rems(Rems(Float(value)))
    case 2: return .percent(Float(value))
    default:
        // Every `caseTag` this file ever writes comes from `decomposeLength`/
        // `decomposeDimension`, which only ever produce 0-3 — so reaching
        // here means a `$anim` entry's `caseTag` was corrupted (a string-key
        // collision — see the `$state`/`$focus`/`$ax`/`$anim` collision risk
        // this file's own top-of-file doc names — or a stray direct write
        // into the slot). Silently mapping an unrecognised tag to `.percent`
        // (this branch's shape before this fix round) would substitute a
        // wrong VALUE with no diagnostic; a loud trap is what makes that
        // hazard visible instead.
        preconditionFailure("recomposeLength: unrecognised case tag \(tag) for value \(value) — " +
                            "a corrupted $anim entry, not a value this file ever writes")
    }
}

private func decomposeDimension(_ d: Dimension) -> (tag: Int, value: Double) {
    switch d {
    case .auto: return (3, 0)
    case let .length(l): return decomposeLength(l)
    }
}

private func recomposeDimension(tag: Int, value: Double) -> Dimension {
    tag == 3 ? .auto : .length(recomposeLength(tag: tag, value: value))
}
