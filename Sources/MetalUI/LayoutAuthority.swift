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
    /// `TextEditor` (ruling TI-H): a leaf, lowered as `text` is.
    case textEditor
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

    /// Who still owes this entry a lowering, for the trap message — or `nil`: a
    /// **permanent refusal by name** (stage 10, `LR-FO`).
    ///
    /// Until stage 10 this was `owningStage: String`, the plan-task-7 stage that
    /// owned the entry (spec §4.1): `"1"` for a site-level entry, `"2"` for a
    /// field of a leaf or container site, `"3"`/`"4"` for `scrollView`/
    /// `component`/`list`, `"10"` for `position`/`inset` and `<field>.absolute`
    /// (`LR-CK`, `LR-EZ` item 3), `"11"` for `deferred`. Once stage 10 finished,
    /// every stage but 11 had closed, so a message naming one read as work owed
    /// by a finished stage. Now:
    ///
    /// - site `deferred` → `"plan task 7, stage 11"`: its one entry, `amended`
    ///   (a `Component.width`/`frame` amend over a presentation member, `LR-CK`),
    ///   is `Component.width`'s question, stage 11's (`LR-FF`, `LR-ER` item 2,
    ///   `LR-EY` item 3);
    /// - a field with the prefix `alignItems.baseline` or `alignSelf.baseline` →
    ///   `"plan task 11"`: baselines (parent spec §8);
    /// - everything else → `nil`. Percentages (no containing block, `LR-AI`), a
    ///   non-greedy `maxSize`, a length `flexBasis`, a floored `space-*`, unequal
    ///   grow weights (SwiftUI shares a surplus equally, 7a probe G0/G1), a
    ///   negative grow or shrink, a root's auto-axis min/max and margin, every
    ///   `…unconsumed` item field (`LR-AQ`), `…absolute` (`LR-CJ` item 3), an
    ///   absolute box outside a `Deferred` and an inset on a static box (`LR-CK`;
    ///   the only absolute layout the kernel has is a presentation's, `LR-CH`),
    ///   and `modifierLayer.style` — the kernel has no answer for any of them, and
    ///   no later task is ruled to give one (`LR-FO` items 1–2).
    var owner: String? {
        if site == .deferred { return "plan task 7, stage 11" }
        if field.hasPrefix("alignItems.baseline") || field.hasPrefix("alignSelf.baseline") {
            return "plan task 11"
        }
        return nil
    }

    /// `"MetalUI: <site>.<field> has no proposal lowering (<owner>); …"` for an
    /// owned entry, `"MetalUI: <site>.<field> has no proposal lowering and is
    /// refused by name (plan task 7, LR-FO); …"` for a permanent one (`LR-FO`
    /// item 3). The prefix `"MetalUI: <site>.<field> has no proposal lowering"`,
    /// which every exit test's `stderr` assertion reads, is the message spec §5.2
    /// fixed and has not changed; until stage 10 the clause read `(plan task 7,
    /// stage <n>)`.
    var trapMessage: String {
        let clause = owner.map { " (\($0))" } ?? " and is refused by name (plan task 7, LR-FO)"
        return "MetalUI: \(description) has no proposal lowering\(clause); "
            + "a tree containing it cannot run under the proposal layout authority."
    }
}
