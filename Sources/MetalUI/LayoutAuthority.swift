import MetalUICore
import MetalUILayout

// Stage 9 (`LR-FC`): the `LayoutAuthority` enum — `.legacy`, the CSS flex
// engine, and `.proposal`, the lowering onto the kernel — is deleted with the
// legacy engine. Every legacy element lowers; this file keeps the lowering's
// diagnostic vocabulary, `LoweringSite` and `UnlowerableField`, under its old
// name so that every citation of it stays true.

/// A legacy registration site, as it names itself in a diagnostic.
///
/// **Every site passes its own** (ruling LR-C, critic round 1): `Frame` never
/// infers the caller, because the two sites that motivated the per-site checks —
/// `List`, which registers through a `Box` it builds, and `StyledComponent`'s
/// amend, which registers nothing — are exactly the ones an inference would
/// misname.
enum LoweringSite: String, Sendable {
    case box
    case stack
    case text
    /// `TextField` (roadmap item 14): a leaf, lowered as `text` is.
    case textField
    case modifierLayer
    case scrollView
    case list
    case component
    /// A `Deferred` presentation root (plan task 7, stage 5, rulings `LR-CH`,
    /// `LR-CK`): one entry, `amended`, raised by a `Component` amend over a
    /// presentation member; owned by stage 11 (`LR-FF`). Stage 5's
    /// `containingBlock`, `nested` and `root` entries went with the legacy
    /// engine whose containing block they protected (stage 9, `LR-FF`).
    case deferred
}

/// One field (or one whole site) with no proposal lowering, as recorded by a
/// frame built with `reportsUnlowerableFields`.
///
/// `field` is `"noLowering"` for a site that lowers nothing yet — in lane 1 every
/// site; lanes 2–4 replace `box`, `stack`, `text` and `modifierLayer` with
/// field-level names (`"flexGrow"`, `"alignItems.stretch"`, …).
/// (`customElement`, which reported the deprecated public registrars from stage
/// 6a, went with them at stage 9, `LR-FF`.)
///
/// **`component` reports nothing at all since stage 3's lane 4** (`LR-BO`): it
/// read `"amend"` or `"wrap"` until both ops were lowered, and neither lowering
/// can raise an entry at its own site — an amend's frame is recorded
/// `kind: .frameLayer`, whose fields the unconsumed report skips (all but an
/// absolute `position`/`inset`, stage 8's `LR-FA`), and both ops plan
/// exactly one child, so neither can raise `flexGrow.weights`, the one entry
/// `parentSite:` names (`LR-BM`).
struct UnlowerableField: Hashable, Sendable, CustomStringConvertible {
    let site: LoweringSite
    let field: String

    var description: String { "\(site.rawValue).\(field)" }

    /// The plan-task-7 stage that owns this entry (spec §4.1), for the trap
    /// message. A site-level entry of a site stage 1 lowers is stage 1's; a
    /// field-level entry of one of those sites is stage 2's unless a lane says
    /// otherwise.
    var owningStage: String {
        // Stage 5 (`LR-CK`): the field decides before the site. `position` and
        // `inset` — an absolute box outside a `Deferred`, a `.relative` box, an
        // inset on a static box, and their `.unconsumed` forms — are **removed**
        // from the proposal authority rather than lowered, and belong to the stage
        // that deletes `Style.position`/`inset`; `minSize`/`maxSize` on an
        // absolute box's `auto` axis (`<field>.absolute`, `LR-CJ` item 3) to
        // stage 10 since stage 8 (`LR-EV` item 4, `LR-EZ` item 3): stage 8's
        // public spelling of a bounded absolute box is a `.frame` before
        // `.position`, which never reports (`LR-EV` item 2), so the report is
        // left only to a `Style`-written box and dies with `Style.minSize`/
        // `maxSize` (`LR-ER` item 4). Until stage 8 it read "8".
        if field.hasPrefix("position") || field.hasPrefix("inset") { return "10" }
        if field.hasSuffix(".absolute") { return "10" }
        switch site {
        // `textField` (roadmap item 14) is a leaf lowered as `text` is, so its
        // field-level entries are the same stage's.
        case .box, .stack, .text, .textField, .modifierLayer:
            return field == "noLowering" ? "1" : "2"
        // Stage 3 lowered both. `scrollView` survives for a scroller **child**'s
        // unlowerable item field, which `lowerLegacyNode` reports at this site
        // through `planLegacyItems`' `parentSite:` — `flexGrow.weights`, the only
        // field raised there (`LR-BM`) — and for a field a later stage puts on the
        // content node's unconsumed record (`<field>.unconsumed`, `LR-BB`).
        // `component` survives for THIS MESSAGE only: lane 4 left it with no
        // reachable entry (`LR-BO`), and the case is kept so that a later stage
        // naming a component field gets the right stage number rather than a
        // fresh `switch` arm nobody remembers to add.
        case .scrollView, .component:
            return "3"
        // Stage 4 lowered `List`, so the SITE-LEVEL entry is gone: `.list` now
        // survives exactly as `scrollView` does — for a ROW's unlowerable item
        // field, which `ListRows` reports at this site through
        // `planLegacyItems`' `parentSite:` (`flexGrow.weights`, the only field
        // raised there, `LR-BM`), and for a field a later stage puts on the
        // windowed node's unconsumed record (`<field>.unconsumed`). No row can
        // raise the weights entry today (`LR-BV`), which is `component`'s
        // post-`LR-BO` position.
        case .list:
            return "4"
        // Stage 9 (`LR-FF`): the one `deferred` entry left is `amended` — a
        // `Component.width`/`frame` amend over a presentation member, which
        // `LR-CK` reports rather than drop silently. What that amend means is
        // `Component.width`'s question, stage 11's (`LR-ER` item 2, `LR-EY`
        // item 3). The stage-5 `containingBlock`, `nested` and `root` entries
        // protected a legacy containing block and went with the legacy engine;
        // until stage 9 this arm read "9".
        case .deferred:
            return "11"
        }
    }

    /// `"MetalUI: <site>.<field> has no proposal lowering (plan task 7, stage
    /// <n>); …"` — the message spec §5.2 fixes, which the exit tests read.
    var trapMessage: String {
        "MetalUI: \(description) has no proposal lowering (plan task 7, stage \(owningStage)); "
            + "a tree containing it cannot run under the proposal layout authority."
    }
}
