import MetalUICore
import MetalUILayout

/// Which layout engine a frame's legacy elements register with (plan task 7,
/// `docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §3; rulings
/// LR-A, LR-B).
///
/// - `.legacy` — every legacy element registers CSS nodes and the frame runs
///   `FlexEngine`, exactly as before task 7. **The default, and the only
///   authority production uses until stage 6b.**
/// - `.proposal` — every legacy element lowers its (animated) `Style` onto kernel
///   nodes, keeping its ids, `prepaint` and `paint`. A site with no lowering yet
///   traps, naming itself and the field (`Frame.unlowerable(_:)`, ruling LR-C).
///
/// **It belongs to the frame, not to an element or an environment value** (LR-B):
/// a tree that switched authority below its root would be ruling SA-G's mixed
/// tree. `Window.layoutAuthority` passes it to every frame the window builds.
///
/// **Internal until stage 6b**, which decides whether any public spelling
/// survives; pinned by the plain-import guard
/// `aPlainImportCannotChooseTheLayoutAuthority`.
///
/// **`CaseIterable` for the tests** (plan task 7, stage 3, lane 3, ruling LR-BI):
/// the two scroll suites and `ScrollViewTests` are parameterised over
/// `allCases`, so "both authorities" is one list rather than a literal repeated
/// at 34 declarations. Internal, like the enum.
enum LayoutAuthority: Sendable, Equatable, CaseIterable {
    case legacy
    case proposal
}

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
    case customElement
    /// A `Deferred` presentation root (plan task 7, stage 5, rulings `LR-CH`,
    /// `LR-CL`): `containingBlock`, `nested` and `root`, raised against the
    /// presentation's containing block, and `amended`, raised by a `Component`
    /// amend over a presentation member (`LR-CK`). Every one exists to keep the
    /// differential honest about a legacy containing block that is not the
    /// window, and is deleted with the legacy authority (stage 9).
    case deferred
}

/// One field (or one whole site) with no proposal lowering, as recorded by a
/// frame built with `reportsUnlowerableFields`.
///
/// `field` is `"noLowering"` for a site that lowers nothing yet — in lane 1 every
/// site; lanes 2–4 replace `box`, `stack`, `text` and `modifierLayer` with
/// field-level names (`"flexGrow"`, `"alignItems.stretch"`, …).
/// `customElement` reports `"requestNode"` or `"requestLeaf"` — the deprecated
/// public registrars since stage 6a, owned by stage 9 (`LR-CW`).
///
/// **`component` reports nothing at all since stage 3's lane 4** (`LR-BO`): it
/// read `"amend"` or `"wrap"` until both ops were lowered, and neither lowering
/// can raise an entry at its own site — an amend's frame is recorded
/// `kind: .frameLayer`, which the unconsumed report skips, and both ops plan
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
        // stage 8's min/max recipe.
        if field.hasPrefix("position") || field.hasPrefix("inset") { return "10" }
        if field.hasSuffix(".absolute") { return "8" }
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
        // Stage 6a (`LR-CW`): a custom element on the deprecated public
        // registrars is **removed** from the proposal authority rather than
        // lowered — its replacement is `requestNativeLeaf` or a
        // `ProposalLayout` — and stage 9 deletes the pair (`LR-CK`'s precedent
        // for `position`/`inset`).
        case .customElement:
            return "9"
        // Stage 5 (`LR-CL`): every `deferred` entry protects a legacy containing
        // block that is not the window, and goes with the legacy authority.
        case .deferred:
            return "9"
        }
    }

    /// `"MetalUI: <site>.<field> has no proposal lowering (plan task 7, stage
    /// <n>); …"` — the message spec §5.2 fixes, which the exit tests read.
    var trapMessage: String {
        "MetalUI: \(description) has no proposal lowering (plan task 7, stage \(owningStage)); "
            + "a tree containing it cannot run under the proposal layout authority."
    }
}
