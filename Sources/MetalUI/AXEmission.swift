import MetalUICore
import MetalUIPlatform

/// One `registerHandlers` call that has something to say to an accessibility
/// client, recorded **only while the frame collects** (`Frame.collectsAccessibility`,
/// ruling AB-B).
///
/// **A record, not an emission** (ruling AB-U). It writes neither `Frame.axNodes`
/// nor `StateTable`: a declared node still goes through `emitAXNode` exactly as
/// it does with no client, and a synthesized one (an `onClick` box, a focusable
/// box) never reaches either. Writing a `$ax` slot per synthesized node would
/// make `@State` retention depend on whether a screen reader is running, since
/// reaping engages only above `StateTable.sweepThreshold`.
///
/// `AccessibilityTreeBuilder` reads these, in record order, which is prepaint's
/// pre-order and so declaration order (AB-C).
struct AXEmission {
    let id: GlobalElementID
    /// `handlers.axNode` as written, `logicalIndex` included.
    let declared: AXNode
    /// The non-empty string of a text leaf, from `Text.prepaint` through
    /// `registerHandlers(…accessibleText:)`; read by the builder's text
    /// resolution (AB-F).
    let text: String?
    /// `handlers.onClick != nil`. Distinct from "pressable": a click target under
    /// `allowsHitTesting(false)` is still a button, and has no `.press` (AB-H).
    let isClickable: Bool
    /// `true` on this branch; the environment track's merge fills it (AB-Z).
    let isEnabled: Bool
    /// `false` for `OnTapModifier` (AB-Y). Its producer is that modifier; **it
    /// has no reader**: a conformer that does not synthesize records only when
    /// it declared something, which the gate in `Frame.registerHandlers` already
    /// decides, so the builder has nothing left to ask it.
    let synthesizes: Bool
    /// 0 outside every `Deferred`; otherwise that portal's per-frame ordinal
    /// (AB-V). A parent must share it.
    let portal: Int
    let geometry: AccessibilityGeometry
}
