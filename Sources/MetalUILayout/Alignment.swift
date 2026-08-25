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
func lineContentSize(_ items: [FlexItem], gap: Double) -> Double {
    guard !items.isEmpty else { return 0 }
    let sizes = items.reduce(0) { $0 + $1.targetMainSize }
    return sizes + gap * Double(items.count - 1)
}

/// CSS Flexbox §9.5 — distribute a line's free space along the main axis.
///
/// **The space-* values never distribute negative free space.** An overflowing
/// line under `space-between` still starts at the main-start edge and packs
/// tight; distributing a negative amount would place later items at *smaller*
/// coordinates than earlier ones. `center` and `flex-end` are different: they
/// legitimately honour negative free space, and an overflowing centred line
/// overhangs both edges equally. That asymmetry is CSS, not an oversight.
///
/// One item collapses `space-between` onto `flex-start` and both `space-around`
/// and `space-evenly` onto `center`, per spec. Those degenerate cases are why a
/// single-item fixture can never distinguish the six values.
func distributeMainAxis(
    _ justify: JustifyContent,
    freeSpace: Double,
    itemCount: Int
) -> MainAxisOffsets {
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
