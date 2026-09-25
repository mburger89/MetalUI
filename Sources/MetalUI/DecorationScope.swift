import MetalUICore

/// **The one prepaint-side entry point for everything a `Decoration` and a
/// `Handlers` register or scope** — the sibling of
/// `paintDecoration(_:in:for:pass:content:)` in `AnimatedColor.swift`
/// (`OM-P`, spec §5.2).
///
/// Its four callers are `Box.prepaint`, `Stack.prepaint`, `Text.prepaint` and
/// `ModifiedContent.prepaintLayerBody` (through `ModifierLayer._prepaint`, stage 11). Each of them called
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
/// at the legacy layer's prepaint (then `ModifiedElement.prepaintLayerBody`) left the whole suite green, because
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
/// **Lane 3 extended this, it did not replace it.** `Handlers.allowsHitTesting`
/// opens `pass.allowsHitTesting(false) { … }` around **everything below**,
/// including the receiver's own registration — because `.onClick` and
/// `.allowsHitTesting` write the *same* outermost `ModifierLayer`'s `Handlers`,
/// so registering outside that scope would leave
/// `Box().onClick { }.allowsHitTesting(false)` an opaque pointer target, which
/// is probe arm N1 read backwards (`OM-T`). **The scope is per layer**: a
/// `ModifiedElement` calls this once per layer, outermost first, so an inner
/// layer's `allowsHitTesting(false)` opens after the outer layer has already
/// registered — `.allowsHitTesting(false).padding(40).onClick { }` leaves the
/// outer click live where SwiftUI's is dead (`OM-AL`, a recorded divergence
/// that is `OM-I`'s across a layer). `Handlers.contentShapeInset` needed
/// nothing here at all: it is applied inside `Frame.registerHandlers`, to the
/// hitbox bounds alone (`OM-J`), so it cannot reach focus or accessibility by
/// construction rather than by four correct call sites.
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
        // **The pointer-disable scope wraps EVERYTHING below, the receiver's own
        // registration included** (ruling OM-T, plan task 5's lane 3).
        // `.onClick` and `.allowsHitTesting` write the same `Handlers` — on a
        // chain, the same outermost `ModifierLayer`'s — so registering outside
        // this scope would leave `Box().onClick { }.allowsHitTesting(false)` an
        // opaque pointer target, which is probe arm N1 read backwards and the
        // common spelling rather than a corner.
        //
        // The registration stays INSIDE rather than being skipped: the scope
        // must remove the pointer target and nothing else, and
        // `Frame.registerHandlers` gates only the hitbox insert on
        // `hitTestingDisabledDepth`. Focus registration, the `$focus` write,
        // `focusedElementProducedThisFrame`, a declared `AXNode` and the
        // accessibility record all sit above that gate and must keep firing —
        // which is also what SwiftUI does (probe
        // `swiftui-allows-hit-testing-side-effects`, arms A1 and K1).
        guard handlers.allowsHitTesting else {
            var result: R!
            allowsHitTesting(false) {
                result = registerAndScopeBody(handlers, decoration, at: bounds, for: id,
                                              accessibleText: accessibleText,
                                              synthesizesAccessibility: synthesizesAccessibility,
                                              content: content)
            }
            return result
        }
        return registerAndScopeBody(handlers, decoration, at: bounds, for: id,
                                    accessibleText: accessibleText,
                                    synthesizesAccessibility: synthesizesAccessibility,
                                    content: content)
    }

    /// The registration and the clip scope, with the pointer-disable scope (if
    /// any) already open around them.
    ///
    /// **Split out rather than written twice** inside the `guard` above: the
    /// two copies would be a site each, and `everyDecorationScopingSiteContains
    /// ItsOwnContent`'s finding — that a site can silently lose half a helper —
    /// applies inside a helper as much as across four of them.
    private func registerAndScopeBody<R>(_ handlers: Handlers, _ decoration: Decoration,
                                         at bounds: Bounds<Pixels>, for id: GlobalElementID,
                                         accessibleText: String?,
                                         synthesizesAccessibility: Bool,
                                         content: () -> R) -> R {
        // One call registers the hitbox, the focus entry, the produced-this-frame
        // signal, a declared `handlers.axNode` and the accessibility record — see
        // `Frame.registerHandlers`, which holds all of those gates so the four
        // conformers cannot disagree about any of them. It is also where
        // `handlers.contentShapeInset` is applied, to the hitbox bounds alone.
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
