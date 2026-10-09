import MetalUICore
import MetalUIPlatform

// Key and focus scoping, lane A (rulings `KF-D`, `KF-E`, `KF-F`, `KF-G`,
// `KF-U`; spec `docs/superpowers/specs/2026-10-08-key-focus-design.md` §4.2,
// §4.3). MetalUI-only: SwiftUI routes no key by hover (probe arms K1u, K1v),
// so `hoverKeyRegion` is ruled on MetalCreator's use cases (M5-b, M5-g, M6).

extension StyledElement {
    /// Makes this element a **key region**: while nothing holds keyboard focus,
    /// keys go to the key region under the pointer — its `onKeyPress` handlers
    /// and its ancestors', outermost first, and its key context and its
    /// ancestors' to the window's `Keymap` (rulings `KF-D`, `KF-E`).
    /// MetalUI-only (SwiftUI's keys always need focus).
    ///
    /// **Focus wins**: a focused element anywhere keeps the keys, wherever the
    /// pointer rests. **A primary press inside the region clears focus**
    /// (unless it lands on a text field or a `focusable(_:interactions:)`
    /// `.edit` element inside it, which take focus themselves), so the region
    /// under the pointer then takes the keys (`KF-E` item 5); a press outside
    /// every region changes no focus (`KF-G`).
    ///
    /// **Hovered by `onHover(perform:)`'s rule** — the innermost key region on
    /// the topmost layer under the pointer that nothing opaque or drawn above
    /// it covers, through the one ranking — **computed only when a key or a
    /// press needs it**, never per pointer move. The region is **non-opaque**:
    /// it blocks no click, hover, wheel, drop or gesture. `.disabled(true)`,
    /// `.hidden()` and `.allowsHitTesting(false)` withdraw it. The raw
    /// `onKey(_:)` bubble and the controls' keys keep needing focus (`KF-U`).
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry; `false`
    /// turns a region off.
    public func hoverKeyRegion(_ isEnabled: Bool = true) -> Self {
        handling { $0.keyboard = KeyboardAttachment.keyRegion(isEnabled, over: $0.keyboard) }
    }
}

extension Window {
    /// The chain the Keymap's contexts, action dispatch and `onKeyPress` walk,
    /// **innermost first** (rulings `KF-D` item 1, `KF-U`): the focus chain
    /// while an element holds focus, otherwise the chain of the hovered key
    /// region (`hoveredKeyRegion()`), empty when neither. `dispatchKey` — the
    /// raw `onKey` bubble, where the controls' keys live — keeps `focusChain`.
    var keyChain: [GlobalElementID] {
        if focusedElement != nil { return focusChain }
        return MetalUI.focusChain(from: hoveredKeyRegion())
    }

    /// The cover's eligibility for the key-region and press-focus lookups: an
    /// opaque target, a hover region or a key region — `onHover`'s rule with
    /// key regions added (`KF-E` item 3); `withPressRegions` adds the
    /// click-focusable press regions (`KF-F` item 3, spec §4.3).
    private func coversKeys(_ box: Hitbox, withPressRegions: Bool) -> Bool {
        box.opaque || box.handlers.hover != nil || box.handlers.isKeyRegion
            || (withPressRegions && box.handlers.focusesOnPress)
    }

    /// The innermost hovered key region at the last pointer position, or `nil`
    /// (rulings `KF-E` items 3–4): `nil` when the last frame registered no key
    /// region (no lookup at all), the pointer left the window, or an in-window
    /// menu or drawn alert suppresses hover. **The one ranking**: the cover is
    /// `topmostHitbox(in:at:where:)`; a region is a member when it is on the
    /// cover's layer, contains the point and the cover is or descends from it.
    /// Counted in `keyRegionLookups`.
    func hoveredKeyRegion() -> GlobalElementID? {
        guard lastKeyRegionCount > 0, let point = lastMousePosition, !hoverIsSuppressed else { return nil }
        keyRegionLookups += 1
        guard let coverIndex = topmostHitbox(in: lastHitboxes, at: point,
                                             where: { coversKeys($0, withPressRegions: false) }) else {
            return nil
        }
        let cover = lastHitboxes[coverIndex]
        var found: GlobalElementID?
        for box in lastHitboxes where box.handlers.isKeyRegion {
            guard box.layer == cover.layer, box.contains(point), cover.id.isOrDescends(from: box.id) else { continue }
            if found.map({ box.id.isOrDescends(from: $0) }) ?? true { found = box.id }
        }
        return found
    }

    /// Focus on a primary press (rulings `KF-F` item 3, `KF-E` item 5): a
    /// stage that claims nothing, after the hover update and the modal, menu
    /// and popover stages and before the text-field stage. With `F` the
    /// innermost click-focusable element and `R` the innermost key region
    /// under the press, on the cover's layer, from which the cover descends:
    ///
    /// 1. the press lands on a text field (the text stage's own lookup) →
    ///    nothing here: the text stage focuses it;
    /// 2. `F` exists and (`R` is `nil` or `F` is or descends from `R`) →
    ///    focus `F`;
    /// 3. else `R` exists → clear focus;
    /// 4. else nothing — a press elsewhere resigns nothing (`KF-G`, RS1–RS5).
    ///
    /// A window whose last frame registered neither region does no lookup.
    func focusOnPress(_ event: InputEvent) {
        guard case .mouseDown(let mouse) = event, lastKeyRegionCount > 0 || lastFocusOnPressCount > 0 else {
            return
        }
        let point = mouse.position
        if let opaque = topmostOpaqueHitbox(in: lastHitboxes, at: point),
           lastHitboxes[opaque].handlers.textInput != nil {
            return
        }
        keyRegionLookups += 1
        guard let coverIndex = topmostHitbox(in: lastHitboxes, at: point,
                                             where: { coversKeys($0, withPressRegions: true) }) else { return }
        let cover = lastHitboxes[coverIndex]
        var focusable: GlobalElementID?
        var region: GlobalElementID?
        for box in lastHitboxes where box.handlers.keyboard != nil {
            guard box.layer == cover.layer, box.contains(point), cover.id.isOrDescends(from: box.id) else { continue }
            if box.handlers.focusesOnPress, focusable.map({ box.id.isOrDescends(from: $0) }) ?? true {
                focusable = box.id
            }
            if box.handlers.isKeyRegion, region.map({ box.id.isOrDescends(from: $0) }) ?? true {
                region = box.id
            }
        }
        if let focusable, region.map({ focusable.isOrDescends(from: $0) }) ?? true {
            focus(focusable)
        } else if region != nil {
            focus(nil)
        }
    }
}
