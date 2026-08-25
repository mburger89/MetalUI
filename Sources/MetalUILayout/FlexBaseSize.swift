import MetalUICore

/// CSS Flexbox §9.2 — a flex item's base size, before min/max clamping.
///
/// **This is deliberately not part of `resolveNodeSize`.** An item's main size
/// comes from this cascade; only its cross size comes from its own style. Merging
/// the two would recreate the "auto means the container's extent" fallback that
/// m1a ruling PF-3 removed, and that failure is silent.
///
/// The cascade, in spec order:
/// 1. a definite `flex-basis` wins outright, even over an explicit `width`;
/// 2. `flex-basis: auto` defers to the main size property, if that is definite;
/// 3. otherwise the item is content-sized — its measure function at max-content.
///
/// An item with no measure function and no definite size is 0. That is honest
/// rather than convenient: nothing measures content until the text system lands,
/// and a zero-width box is visibly wrong where a container-width box is
/// plausibly wrong.
func flexBaseSize(
    _ tree: LayoutTree,
    item: LayoutNodeID,
    isRow: Bool,
    containerMain: Double?,
    containerCross: Double?,
    rootFontSize: Double
) -> Double {
    let s = tree.style(item)

    // 1. Definite flex-basis.
    if let basis = resolveDimension(s.flexBasis, against: containerMain,
                                    rootFontSize: rootFontSize) {
        return basis
    }

    // 2. flex-basis: auto -> the main size property, if definite.
    let mainDim = isRow ? s.size.width : s.size.height
    if let main = resolveDimension(mainDim, against: containerMain,
                                   rootFontSize: rootFontSize) {
        return main
    }

    // 3. Content size, at max-content in the main axis.
    guard let measure = tree.measure(item) else { return 0 }
    let known = OptionalSizeD(
        width: isRow ? nil : resolveDimension(s.size.width, against: containerCross,
                                              rootFontSize: rootFontSize),
        height: isRow ? resolveDimension(s.size.height, against: containerCross,
                                         rootFontSize: rootFontSize) : nil)
    let available = AvailableSpaceSize(
        width: isRow ? .maxContent : (containerCross.map { .definite($0) } ?? .maxContent),
        height: isRow ? (containerCross.map { .definite($0) } ?? .maxContent) : .maxContent)
    let measured = measure(known, available)
    return isRow ? measured.width : measured.height
}
