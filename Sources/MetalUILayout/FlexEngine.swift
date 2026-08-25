import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: a single
/// line, fixed sizes, flex-start packing. Grow/shrink, alignment, wrapping and
/// absolute positioning arrive in later tasks, each with its own fixtures.
///
/// Every rect written here is **absolute to the root**, not relative to its
/// parent. `roundLayout` keeps no cross-rect state, so its no-drift guarantee
/// depends entirely on receiving absolute coordinates; storing parent-relative
/// ones would silently reintroduce the accumulated error it exists to prevent.
public func computeLayout(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double = 16
) {
    let rootSize = resolveNodeSize(tree, root, parent: .unspecified,
                                   available: available, rootFontSize: rootFontSize)
    tree.setLayout(root, LayoutRect(x: 0, y: 0, width: rootSize.width, height: rootSize.height))
    layoutChildren(tree, root, containerOrigin: (0, 0), containerSize: rootSize,
                   rootFontSize: rootFontSize)
}

/// Resolve a node's own border-box size from its style.
private func resolveNodeSize(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    parent: OptionalSizeD,
    available: AvailableSpaceSize,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              parentExtent: Double?, availableExtent: AvailableSpace) -> Double {
        let resolved = resolveDimension(dim, against: parentExtent, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: parentExtent, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: parentExtent, rootFontSize: rootFontSize)
        let base: Double
        if let resolved {
            base = resolved
        } else if case .definite(let d) = availableExtent {
            // TASK 7 SCOPE BOUNDARY — NOT CSS-CORRECT. DO NOT BUILD ON THIS.
            //
            // An auto-sized flex item does NOT take its container's extent. Its
            // main size comes from its *content*, via flex-basis and the §9.2
            // hypothetical main size; its cross size comes from content or from
            // stretch alignment. Falling back to the container's extent is a
            // placeholder that happens to be unobservable here only because
            // every Task 7 fixture gives each box an explicit width and height.
            //
            // The flex base size algorithm (§9.2) plus resolve-flexible-lengths
            // (§9.7) replace this branch wholesale in the grow/shrink task. If
            // it survives, auto-sized items silently inherit their container's
            // size forever and the bug is very hard to see.
            base = d
        } else {
            base = 0
        }
        return clamp(base, min: lower, max: upper)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width,
                    parentExtent: parent.width, availableExtent: available.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height,
                     parentExtent: parent.height, availableExtent: available.height))
}

/// Place a container's children along its main axis, packed from the start.
private func layoutChildren(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let s = tree.style(container)
    let kids = tree.children(container)
    guard !kids.isEmpty else { return }

    let isRow = s.flexDirection.isRow
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: isRow ? containerSize.width : containerSize.height,
                            rootFontSize: rootFontSize) ?? 0

    var cursor: Double = 0
    for kid in kids where tree.style(kid).display != .none {
        let kidSize = resolveNodeSize(
            tree, kid,
            parent: OptionalSizeD(width: containerSize.width, height: containerSize.height),
            available: AvailableSpaceSize(width: .definite(containerSize.width),
                                          height: .definite(containerSize.height)),
            rootFontSize: rootFontSize)

        let x = containerOrigin.0 + (isRow ? cursor : 0)
        let y = containerOrigin.1 + (isRow ? 0 : cursor)
        tree.setLayout(kid, LayoutRect(x: x, y: y, width: kidSize.width, height: kidSize.height))

        layoutChildren(tree, kid, containerOrigin: (x, y), containerSize: kidSize,
                       rootFontSize: rootFontSize)

        cursor += (isRow ? kidSize.width : kidSize.height) + gap
    }
}
