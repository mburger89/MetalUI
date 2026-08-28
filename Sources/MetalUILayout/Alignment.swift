import MetalUICore

/// Where a line starts, and how much space sits between adjacent items.
///
/// Two numbers rather than a per-item offset array: every CSS distribution is
/// uniform, so a leading offset plus a constant stride describes all six. Grid
/// reuses this for its track alignment (spec §3.1 lists `Alignment.swift` as
/// shared), which is why it takes a free-space scalar rather than a flex line.
struct MainAxisOffsets {
    /// Distance from the container's main-start edge to the first item.
    let leading: Double
    /// Extra space inserted between adjacent items, on top of `gap`.
    let between: Double
}

/// A line's main-axis content size: the items, plus the gaps **between** them.
///
/// A trailing gap is the classic off-by-one here, and it was invisible until
/// this function existed — `positionItems` consumed `gap` inside a loop whose
/// cursor died with it, so nothing could observe the total. `justify-content`
/// subtracts this from the container to get free space, which is what finally
/// makes a trailing gap redden a test.
/// Takes plain main-axis extents rather than `[FlexItem]`: this file is shared
/// with Grid (spec §3.1), and a parameter naming a flex type would make that
/// claim false the moment Grid tried to call it.
///
/// **Margins are the caller's job, not this function's.** An item's margin
/// sits outside its border box, so `positionItems` passes this function each
/// item's *outer* main size (`marginMain.leading + targetMainSize +
/// marginMain.trailing`) rather than teaching this shared file about
/// `FlexItem.marginMain` — the same reason it stays `[Double]`.
func lineContentSize(_ mainSizes: [Double], gap: Double) -> Double {
    guard !mainSizes.isEmpty else { return 0 }
    return mainSizes.reduce(0, +) + gap * Double(mainSizes.count - 1)
}

/// CSS Flexbox §9.5 — distribute a line's free space along the main axis.
///
/// **The space-* values never distribute negative free space — because both
/// WebKit and Blink clamp it, not because the spec's letter says so.** CSS
/// Box Alignment actually defines `space-around` (and by extension
/// `space-evenly`/`space-between`) with negative free space as *identical to
/// `center`* — the spec's letter disagrees with this code. Measured directly
/// on a 2×80px line in a 100px container (freeSpace = -60) rather than taken
/// on faith:
///
/// ```
/// space-around   WebKit [0, 80]     Blink [0, 80]     spec letter [-30, 50]
/// space-evenly   WebKit [0, 80]     Blink [0, 80]
/// space-between  WebKit [0, 80]     Blink [0, 80]
/// center         WebKit [-30, 50]   Blink [-30, 50]   (spec, WebKit, Blink all agree)
/// ```
///
/// `center` and `flex-end` are different: all three of spec/WebKit/Blink
/// agree they legitimately honour negative free space, so an overflowing
/// centred line overhangs both edges equally — that part is uncontested.
///
/// Ruling AL-4. This follows the same rule as ruling FS-9
/// (`docs/superpowers/2026-08-25-flex-sizing-decisions.md`), applied in
/// mirror image: there, Blink and the spec agreed and WebKit alone dissented,
/// so FS-9 kept the spec. Here, WebKit and Blink agree and the spec's letter
/// is the lone dissenter, so this code follows the engines. The rule the two
/// rulings share: **two independent engines agreeing outrank the spec's
/// letter; one engine alone does not.**
///
/// One item collapses `space-between` onto `flex-start` and both `space-around`
/// and `space-evenly` onto `center`, per spec. Those degenerate cases are why a
/// single-item fixture can never distinguish the six values.
func distributeMainAxis(
    _ justify: JustifyContent,
    freeSpace: Double,
    itemCount: Int
) -> MainAxisOffsets {
    // Unreachable from the engine — `layOutChildren` returns early on an empty
    // line, so `leading` would be discarded anyway — and therefore deliberately
    // untested: a test for it could not fail. Kept because this file is shared
    // with Grid, whose empty-track cases are not written yet.
    guard itemCount > 0 else { return MainAxisOffsets(leading: 0, between: 0) }

    switch justify {
    case .flexStart:
        return MainAxisOffsets(leading: 0, between: 0)
    case .flexEnd:
        return MainAxisOffsets(leading: freeSpace, between: 0)
    case .center:
        return MainAxisOffsets(leading: freeSpace / 2, between: 0)
    case .spaceBetween:
        let space = max(0, freeSpace)
        guard itemCount > 1 else { return MainAxisOffsets(leading: 0, between: 0) }
        return MainAxisOffsets(leading: 0, between: space / Double(itemCount - 1))
    case .spaceAround:
        let space = max(0, freeSpace)
        let per = space / Double(itemCount)
        return MainAxisOffsets(leading: per / 2, between: per)
    case .spaceEvenly:
        let space = max(0, freeSpace)
        let per = space / Double(itemCount + 1)
        return MainAxisOffsets(leading: per, between: per)
    }
}

/// Resolve which alignment applies to one item.
///
/// `align-self: auto` is modelled as `nil` here, and defers to the container's
/// `align-items`. The container's own `nil` is CSS's initial `normal`, which on
/// a flex item behaves as **`stretch`** — not `flex-start`. Getting that default
/// wrong makes stretch unreachable for every unstyled container, which is most
/// of them.
func resolvedAlignment(_ item: Style, container: Style) -> AlignItems {
    if let s = item.alignSelf {
        switch s {
        case .flexStart: return .flexStart
        case .flexEnd:   return .flexEnd
        case .center:    return .center
        case .baseline:  return .baseline
        case .stretch:   return .stretch
        }
    }
    return container.alignItems ?? .stretch
}

/// CSS Flexbox §9.6 — an item's offset from its line's cross-start edge.
///
/// **`stretch` returns 0 here, and that is correct, not a stub.** Stretch
/// changes an item's cross *size*, and `collectItems` now does that (§9.4); by
/// the time placement runs, a stretched item already fills the line and a zero
/// offset is right. An item that is stretch-aligned but has a definite cross
/// size is not stretched at all, and CSS places it at cross-start — also zero.
/// Nothing here changed when stretch landed, and nothing here should.
///
/// **`baseline` is NOT implemented** and falls back to `flexStart`: a
/// baseline-aligned row lays out silently as a flex-start row.
///
/// **The blocker this comment used to name is gone, and the work is not done.**
/// It said baseline "requires font metrics that arrive with the text system in
/// M2". Those metrics exist — `MetalUIText`'s `FontMetrics` carries ascent,
/// descent and leading, pinned against `CTFontGetAscent`/`Descent`/`Leading` by
/// `metricsMatchCoreText` — so nothing is waiting on a milestone. What is
/// missing is engine work here, and naming it is the point of this paragraph
/// (taxonomy shape 10: name a mechanism, never a milestone):
///
/// 1. **The engine cannot see a baseline at all.** A `MeasureFunction` returns
///    a `SizeD`, so an item's first baseline never reaches `collectItems`; the
///    measure protocol has to carry it before `crossAxisOffset` can align on
///    it.
/// 2. **This function's signature is the wrong shape.** Baseline alignment is
///    not an offset computed per item from `(itemCross, lineCross)` — a line's
///    items have to agree on a common baseline first, which is a per-*line*
///    quantity this function is never given.
/// 3. **AL-6's `wrap-reverse` clause.** CSS Flexbox §8.3 swaps first- and
///    last-baseline alignment in a `wrap-reverse` container. `positionItems`'
///    flip inverts an offset, and baseline alignment is not an offset, so
///    nothing there expresses it today.
///
/// Recorded in CLAUDE.md's inert-API table — do not remove that row without
/// implementing this.
///
/// **`itemCross` is the item's OUTER cross size since item margins landed** —
/// `marginCross.leading + crossSize + marginCross.trailing` — because
/// alignment measures the margin box against the line, exactly as
/// `justify-content` measures outer main sizes against it. `positionItems` is
/// the caller that resolves this and then adds `marginCross.leading` to the
/// return value to land on the border box's own origin; this function itself
/// knows nothing about margins.
func crossAxisOffset(_ align: AlignItems, itemCross: Double, lineCross: Double) -> Double {
    switch align {
    case .flexStart, .stretch, .baseline: 0
    case .flexEnd:                        lineCross - itemCross
    case .center:                         (lineCross - itemCross) / 2
    }
}

/// CSS Flexbox §9.6.15 / §8.4 — distribute leftover **cross** space among a
/// container's flex lines.
///
/// Six of the seven values behave exactly as `justify-content`'s do, so this
/// **delegates** to `distributeMainAxis` rather than repeating the switch — a
/// second copy is how the two drift apart, and every clause that switch already
/// carries (ruling AL-4's negative-free-space clamp on the three `space-*`
/// values, the `itemCount == 1` degeneracies) would have to be re-derived
/// correctly here to no benefit.
///
/// **No mutation can prove that choice load-bearing, and none is claimed to.**
/// A *correct* parallel switch is observationally identical to this delegation,
/// so what the delegation buys is drift-resistance over time, not behaviour
/// today — no input distinguishes them. What mutation testing does pin is
/// narrower, and worth stating exactly rather than rounding up: corrupting a
/// value some fixture actually declares (`space-between` divided by `lineCount`)
/// reddens `wrapAlignContentBetweenMatchesWebKit`, so this path's distribution
/// is **browser-pinned for `space-between`**, and via
/// `flex_wrap_align_content_center` for `center`. `space-around` and
/// `space-evenly` are pinned by
/// `alignContentDistributesLeftoverCrossSpaceAmongLines` **alone**: halving
/// their edges wrongly reddens that unit test and no fixture, because no fixture
/// declares either value. An earlier draft of this paragraph said the browser
/// fixtures caught it. They do not — that was the task brief's prediction,
/// repeated here without being re-run.
///
/// `stretch` is the seventh, has no `justify-content` counterpart, and is CSS's
/// **initial value**: it grows every line rather than moving lines apart, so it
/// returns zero offsets here and reports its growth through `lineStretchAmount`
/// instead. Splitting it across two functions rather than returning a triple
/// keeps the delegation above a straight forward of `MainAxisOffsets`.
///
/// `lineCount` is what `itemCount` is to `distributeMainAxis` — the number of
/// things being distributed — so a single line collapses `spaceBetween` onto
/// `flexStart` and both `spaceAround` and `spaceEvenly` onto `center`, per spec,
/// for free.
func distributeLines(_ align: AlignContent, freeSpace: Double, lineCount: Int) -> MainAxisOffsets {
    switch align {
    case .stretch:      return MainAxisOffsets(leading: 0, between: 0)
    case .flexStart:    return distributeMainAxis(.flexStart, freeSpace: freeSpace, itemCount: lineCount)
    case .flexEnd:      return distributeMainAxis(.flexEnd, freeSpace: freeSpace, itemCount: lineCount)
    case .center:       return distributeMainAxis(.center, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceBetween: return distributeMainAxis(.spaceBetween, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceAround:  return distributeMainAxis(.spaceAround, freeSpace: freeSpace, itemCount: lineCount)
    case .spaceEvenly:  return distributeMainAxis(.spaceEvenly, freeSpace: freeSpace, itemCount: lineCount)
    }
}

/// How much **each** line grows under `align-content: stretch` (§9.6.15).
///
/// Zero for every other value, and zero when there is no leftover: §9.6.15 says
/// to *increase* each line's cross size, so negative free space — lines that
/// already overflow the container — never shrinks a line. Without that guard an
/// overflowing wrapped container would pull its lines back on top of each other.
///
/// The caller must apply this **before** resolving item stretch: a stretched
/// item fills its line, so growing the line afterwards leaves the item short by
/// exactly this amount with slack below it. `aStretchedLineChangesWhatItsStretchedItemsFill`
/// pins the ordering.
func lineStretchAmount(_ align: AlignContent, freeSpace: Double, lineCount: Int) -> Double {
    guard align == .stretch, lineCount > 0, freeSpace > 0 else { return 0 }
    return freeSpace / Double(lineCount)
}
