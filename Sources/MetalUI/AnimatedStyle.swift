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
/// case tag; `animateField(_:declaredTag:declaredValue:transaction:now:)` is
/// the one function every field call routes through, and every test below is
/// really a test of that one function through a different field shape.
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
///   — but resolving a `ColorToken` needs a `Theme`, and `Theme` is
///   deliberately **not** on `LayoutPass` (`Passes.swift`'s own doc on
///   `PaintPass.theme`: "Deliberately not on `LayoutPass` or `PrepaintPass` …
///   layout contributes `Style`, which has no colour field"). This helper
///   runs at registration time — `LayoutPass` — which is the only phase this
///   task's interface gives it. Even given a theme, `ColorToken` is a
///   discrete enum with no addressable intermediate value the way a `Double`
///   has 50 between 0 and 100, so there is nowhere to write a "halfway
///   colour" back into a `Decoration.background: ColorToken?` field. These
///   three fields therefore pass through unchanged, on `aspectRatio`'s exact
///   footing. **This is a real, reportable narrowing of spec §4's animatable
///   list, not an oversight** — see this task's report for the alternative
///   (a paint-time consumer of this same `$anim` slot, which needs a `Theme`
///   and was out of this task's scope).
///
/// ## Storage (spec §6)
///
/// A reserved `$anim` child slot under the element's own `GlobalElementID`
/// holds an `AnimatedFieldMap` — one `AnimatedFieldState` per animatable
/// field that has ever differed from its own established baseline, keyed by
/// a dotted path name (`"inset.top"`, `"size.width"`, `"flexGrow"`, …). This
/// is the FOURTH reserved slot name, joining `$state\(n)`, `$focus` and
/// `$ax` — CLAUDE.md records those three as carrying an identical, unguarded
/// collision risk, and `$anim` inherits it exactly.
/// `theFourRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift`, renamed
/// from `theThreeRetentionSlotsAreMutuallyDistinct` by this task, per spec §7
/// item 10) is what pins it — the existing three-way test extended to four.
@MainActor
func animRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim"))
}

/// One animatable field's persisted animation state.
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

/// One element's whole `$anim` slot.
typealias AnimatedFieldMap = [String: AnimatedFieldState]

/// Substitutes animated values into `style`/`decoration` for `id`, advancing
/// or starting animations as needed, and returns the pair to register instead
/// of the caller's own declared values.
///
/// Spec §5's four steps, in order: (1)/(2) below read the previous frame's
/// `$anim` values via `peek` (never marking — Ruling I), (3) starts an
/// animation for each animatable field that differs while a transaction is
/// in flight, and each field call below is (4)'s substitution for that one
/// field. The one `withState` call at the end is the sole write, and it is
/// skipped entirely — Ruling I — when nothing this frame needs to be
/// persisted: no new difference on any field, and no field still mid-flight.
///
/// **`withState`, never `write` (Ruling H).** `StateTable.write` raises
/// `isDirty` and fires `onWrite → Window.setNeedsRedraw()`; this helper runs
/// on every frame at every registering site, so `write` here would re-dirty
/// the window every frame regardless of whether anything is actually
/// animating, and the display link would never pause — exactly the hazard
/// CLAUDE.md's `@State` bullet names. `theHelperNeverDirtiesTheStateTable`
/// (`AnimationTests.swift`) pins it across 20 frames of an unchanging style.
@MainActor
func animated(_ style: Style, _ decoration: Decoration, for id: GlobalElementID,
             pass: inout LayoutPass) -> (Style, Decoration) {
    let slotID = animRetentionSlot(for: id)
    let now = pass.frame.timestamp
    let transaction = Animation.pendingTransaction
    let existing = pass.frame.stateTable.peek(slotID, as: AnimatedFieldMap.self) ?? [:]

    var updated = existing
    var dirty = false

    func number(_ key: String, _ declared: Double) -> Double {
        let (value, _, slot) = animateField(existing[key], declaredTag: 0, declaredValue: declared,
                                            transaction: transaction, now: now)
        if let slot { updated[key] = slot; dirty = true }
        return value
    }

    func length(_ key: String, _ declared: Length) -> Length {
        let (tag, raw) = decomposeLength(declared)
        let (value, outTag, slot) = animateField(existing[key], declaredTag: tag, declaredValue: raw,
                                                  transaction: transaction, now: now)
        if let slot { updated[key] = slot; dirty = true }
        return recomposeLength(tag: outTag, value: value)
    }

    func dimension(_ key: String, _ declared: Dimension) -> Dimension {
        let (tag, raw) = decomposeDimension(declared)
        let (value, outTag, slot) = animateField(existing[key], declaredTag: tag, declaredValue: raw,
                                                  transaction: transaction, now: now)
        if let slot { updated[key] = slot; dirty = true }
        return recomposeDimension(tag: outTag, value: value)
    }

    var newStyle = style

    // Animatable — from `Style` (spec §4).
    newStyle.inset = Edges(top: dimension("inset.top", style.inset.top),
                           right: dimension("inset.right", style.inset.right),
                           bottom: dimension("inset.bottom", style.inset.bottom),
                           left: dimension("inset.left", style.inset.left))
    newStyle.size = Size(width: dimension("size.width", style.size.width),
                         height: dimension("size.height", style.size.height))
    newStyle.minSize = Size(width: dimension("minSize.width", style.minSize.width),
                            height: dimension("minSize.height", style.minSize.height))
    newStyle.maxSize = Size(width: dimension("maxSize.width", style.maxSize.width),
                            height: dimension("maxSize.height", style.maxSize.height))
    newStyle.margin = Edges(top: dimension("margin.top", style.margin.top),
                            right: dimension("margin.right", style.margin.right),
                            bottom: dimension("margin.bottom", style.margin.bottom),
                            left: dimension("margin.left", style.margin.left))
    newStyle.padding = Edges(top: length("padding.top", style.padding.top),
                             right: length("padding.right", style.padding.right),
                             bottom: length("padding.bottom", style.padding.bottom),
                             left: length("padding.left", style.padding.left))
    newStyle.border = Edges(top: length("border.top", style.border.top),
                            right: length("border.right", style.border.right),
                            bottom: length("border.bottom", style.border.bottom),
                            left: length("border.left", style.border.left))
    newStyle.gap = Axes(horizontal: length("gap.horizontal", style.gap.horizontal),
                        vertical: length("gap.vertical", style.gap.vertical))
    newStyle.flexGrow = Float(number("flexGrow", Double(style.flexGrow)))
    newStyle.flexShrink = Float(number("flexShrink", Double(style.flexShrink)))
    newStyle.flexBasis = dimension("flexBasis", style.flexBasis)

    // `aspectRatio` and every snapping field (`display`, `position`,
    // `overflow`, `flexDirection`, `flexWrap`, `justifyContent`, `alignItems`,
    // `alignContent`, `justifyItems`, `alignSelf`) are never assigned above,
    // so `newStyle` carries `style`'s own current value through untouched —
    // which IS "snap": always the caller's latest declared value, on every
    // frame, transaction or not.

    var newDecoration = decoration
    newDecoration.cornerRadius = Pixels(Float(number("cornerRadius", Double(decoration.cornerRadius.value))))
    // `background` / `hoverBackground` / `focusBackground`: see this file's
    // top-of-file doc. Not assigned above, so they pass through unchanged.

    if dirty {
        pass.frame.stateTable.withState(slotID, initial: updated) { $0 = updated }
    }

    return (newStyle, newDecoration)
}

/// Advance or (re)start one field's animation state (spec §5 step 3, §7).
///
/// Returns the value to use THIS frame, the case tag that value was
/// reconstructed with, and — only when something must be persisted — the
/// slot to write back. `nil` in the third position is Ruling I: a field with
/// no difference from its own last-known target and no still-running
/// animation writes nothing at all.
private func animateField(_ existing: AnimatedFieldState?, declaredTag: Int, declaredValue: Double,
                          transaction: Animation?, now: Double)
    -> (value: Double, tag: Int, slot: AnimatedFieldState?) {
    guard let existing else {
        // First sighting of this field on this element: there is nothing to
        // diff against, so this establishes the resting baseline rather than
        // animating from an undefined prior state — the same choice SwiftUI
        // makes for a value that appears already-placed. This IS "something
        // to store" in Ruling I's sense: without it, a LATER difference on
        // this exact field would have nothing to compare against either, and
        // no field could ever be observed to change.
        let settled = AnimatedFieldState(caseTag: declaredTag, from: declaredValue, to: declaredValue,
                                         startTime: now, animation: .linear(duration: 0), velocity: 0)
        return (declaredValue, declaredTag, settled)
    }

    let elapsed = now - existing.startTime
    let current = existing.animation.value(at: elapsed, from: existing.from, to: existing.to,
                                           initialVelocity: existing.velocity)

    let caseChanged = declaredTag != existing.caseTag
    let valueChanged = caseChanged || declaredValue != existing.to

    if valueChanged {
        // A case change snaps UNCONDITIONALLY, even mid-transaction — spec
        // §4's "three rules the type system does not enforce": `.auto`
        // carries no number, and a percentage's basis is not known here, so
        // neither has a meaningful midpoint against a different case.
        if !caseChanged, let transaction {
            // Interruption re-targets from wherever the field IS right now
            // (§7), not from `existing.from` — `current.value`/`.velocity`
            // are exactly that: the current position and momentum, which is
            // `(existing.to, 0)` when `existing` was already settled and a
            // true mid-flight position/velocity when it was not.
            let slot = AnimatedFieldState(caseTag: declaredTag, from: current.value, to: declaredValue,
                                          startTime: now, animation: transaction, velocity: current.velocity)
            return (current.value, declaredTag, slot)
        }
        let settled = AnimatedFieldState(caseTag: declaredTag, from: declaredValue, to: declaredValue,
                                         startTime: now, animation: .linear(duration: 0), velocity: 0)
        return (declaredValue, declaredTag, settled)
    }

    if current.isFinished {
        // Settled and unchanged from what was last recorded: Ruling I — no
        // difference and no live animation, so nothing is written.
        return (existing.to, existing.caseTag, nil)
    }

    // Still animating toward the same target the last frame declared: return
    // the interpolated position and re-store the IDENTICAL slot (nothing
    // about its content has changed) so it stays marked and survives the
    // tombstone reap while it is genuinely still live.
    return (current.value, existing.caseTag, existing)
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
    default: return .percent(Float(value)) // tag == 2
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
