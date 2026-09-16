import MetalUICore

/// **The one prepaint-side entry point for everything a `Decoration` and a
/// `Handlers` register or scope** — the sibling of
/// `paintDecoration(_:in:for:pass:content:)` in `AnimatedColor.swift`
/// (`OM-P`, spec §5.2).
///
/// Its four callers are `Box.prepaint`, `Stack.prepaint`, `Text.prepaint` and
/// `ModifiedElement.prepaintLayerBody`. Each of them called
/// `pass.registerHandlers(_:at:id:)` directly before this existed; the
/// difference is that a `Decoration` now carries a **scope** (`clipsContent`,
/// and lane 3's `Handlers.allowsHitTesting`) as well as the fields that only
/// ever produced one emission, and a scope has to wrap the children.
///
/// **Why a file of its own rather than four copies.** A site that forgot the
/// clip would register hitboxes that escape the box their element clips —
/// visible nowhere, reproducible only by clicking on content that is not drawn.
///
/// **Two guards, and the second was missing until the lane's review round**
/// (`OM-AI`). `everyDecorationPaintingSiteDrawsItsBorder` sees whether a site
/// CALLS the helper. Nothing saw the shape of the call: passing `Decoration()`
/// here — keeping the registration, dropping the scope — at `Stack.prepaint` or
/// at `ModifiedElement.prepaintLayerBody` left the whole suite green, because
/// `clippedAlsoClipsTheHitboxesInsideIt` was one `Box` fixture. It is now a
/// table with a `Box`, a `Stack` and a two-layer `ModifiedElement` arm, and each
/// of those three mutations reddens its own arm. `Text` has no children, so its
/// scope is a no-op and it has no arm; the paint-side sibling of the same
/// finding is `everyDecorationScopingSiteContainsItsOwnContent`, which covers
/// all four.
///
/// **`accessibleText` and `synthesizesAccessibility` are forwarded, and they
/// are not optional decoration** (`OM-X`). `Text.prepaint` calls the five-
/// argument internal overload of `registerHandlers` today
/// (`accessibleText: string.isEmpty ? nil : string, synthesizesAccessibility:
/// true`); a helper that forwarded only the three-argument form would delete
/// every text leaf's accessibility string, which is `AB-F`/`AB-Y`'s whole
/// subject. The defaults reproduce exactly what `Box`, `Stack` and
/// `ModifiedElement` pass.
///
/// **Lane 3 extends this, it does not replace it.** `Handlers.allowsHitTesting`
/// opens `pass.allowsHitTesting(false) { … }` around **everything below**,
/// including the receiver's own registration below — because `.onClick` and
/// `.allowsHitTesting` write the *same* outermost `ModifierLayer`'s `Handlers`,
/// so registering outside that scope would leave
/// `Box().onClick { }.allowsHitTesting(false)` an opaque pointer target, which
/// is probe arm N1 read backwards (`OM-T`). The `content` closure and the
/// return type are already shaped for that: a new scope goes at the top of this
/// function and wraps the rest.
/// **A method on `PrepaintPass`, not a free function taking `inout
/// PrepaintPass`**, for the reason `PaintPass.paintDecoration` records: the
/// `content()` closure writes `pass`, and an `inout` parameter holds an
/// exclusive access open across the whole call, so the closure's write is an
/// overlapping access the compiler rejects. A non-mutating method borrows
/// `self` instead — the same thing `pass.clipped(to:offsetBy:) { … pass … }` has
/// always relied on. `PrepaintPass`'s only stored property is `let frame:
/// Frame`.
extension PrepaintPass {
    func registerAndScope<R>(_ handlers: Handlers, _ decoration: Decoration,
                             at bounds: Bounds<Pixels>, for id: GlobalElementID,
                             accessibleText: String? = nil,
                             synthesizesAccessibility: Bool = true,
                             content: () -> R) -> R {
        // One call registers the hitbox, the focus entry, the produced-this-frame
        // signal, a declared `handlers.axNode` and the accessibility record — see
        // `Frame.registerHandlers`, which holds all of those gates so the four
        // conformers cannot disagree about any of them.
        registerHandlers(handlers, at: bounds, id: id, accessibleText: accessibleText,
                         synthesizesAccessibility: synthesizesAccessibility)
        guard decoration.clipsContent else { return content() }
        // The prepaint half of `.clipped()`, at a ZERO offset: this element does
        // not translate its children, it only bounds them. `ScrollView.prepaint`
        // is the same call with a scroll offset, and `Frame.insertHitbox`
        // intersects an incoming rect with the active clip, so a hitbox declared
        // inside a clipped box is recorded at the visible part of itself.
        var result: R!
        clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                cornerRadii: Corners(all: decoration.cornerRadius)) {
            result = content()
        }
        return result
    }
}
