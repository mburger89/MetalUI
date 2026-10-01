import MetalUICore

// Plan task 12, part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §4;
// rulings `IX-V`, `IX-X`, `IX-Y`): the vocabulary the new accessibility
// modifiers take, and the two actions they register.

/// How an element that declares `accessibilityElement(children:)` treats the
/// accessibility content inside it — SwiftUI's `AccessibilityChildBehavior`
/// (ruling `IX-V`).
///
/// **A closed enum where SwiftUI's is a struct with static members**,
/// `PickerStyle`'s precedent (`DD-V`): nothing outside can add a behaviour, and
/// `.ignore`, `.combine` and `.contain` spell the same at a call site.
public enum AccessibilityChildBehavior: Sendable, Hashable {
    /// One node, its own declarations only; its children are dropped and
    /// contribute nothing (SwiftUI arms E1, E2, E12). SwiftUI's default.
    case ignore
    /// One node whose text is its children's, joined with `", "`; over an
    /// interactive child it takes the first one's role and press, and every
    /// interactive child becomes a custom action (E3, E6–E8, E10, E11, E14).
    case combine
    /// A group that keeps its children and does not hand them its label (E4,
    /// E5, E9).
    case contain
}

/// The descriptive traits an accessibility client reads off a node — SwiftUI's
/// `AccessibilityTraits`, the subset with a macOS reading (ruling `IX-X`).
///
/// **Each trait sets the role only** (SwiftUI arms T1–T11): `.isButton` makes
/// a button **without** a press (T2), `.isHeader` a heading labelled by its
/// text (T1), `.isLink` a link, `.isImage` an image, `.isStaticText` a static
/// text, `.isSelected` selected on any role (T4, T7), `.isModal` the only
/// subtree published (M1–M3). `.updatesFrequently` is carried and published
/// nowhere — SwiftUI's is invisible on macOS too (T10), a declared-but-inert
/// row by design. Removing `.isButton` from a clickable element changes its
/// role to a group and keeps its folded label and its press (T3, T3p).
///
/// **Not offered** (owner none; guard `anUnofferedTraitOrActionKindDoesNotCompile`):
/// `.isSearchField`, `.playsSound`, `.isKeyboardKey`, `.isSummaryElement`,
/// `.startsMediaSession`, `.allowsDirectInteraction`, `.causesPageTurn`,
/// `.isTabBar`, `.isToggle` — none has a macOS reading MetalUI could reproduce.
public struct AccessibilityTraits: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    /// A trait set from its raw bits; prefer the named statics.
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Publishes the element with the button role; sets the role only, adding
    /// no press (`IX-W`).
    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    /// Publishes the element as a heading whose text is its label, distributed
    /// to its subtree as a label is (`IX-W`).
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    /// Publishes the element as selected, on any role (`IX-W`).
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    /// Publishes the element with the link role; sets the role only (`IX-W`).
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)
    /// Publishes the element with the image role; sets the role only (`IX-W`).
    public static let isImage = AccessibilityTraits(rawValue: 1 << 4)
    /// Publishes the element as static text; sets the role only (`IX-W`).
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 5)
    /// Isolates the element: while the greatest declaring record is published,
    /// only its subtree is, and a request naming an element outside it is
    /// refused (`IX-X`; divergence 95).
    public static let isModal = AccessibilityTraits(rawValue: 1 << 6)
    /// Declared and inert: published on neither bridge, as SwiftUI's own trait
    /// is on macOS (record §05, `IX-W`).
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 7)
}

/// What `accessibilityAction(_:)` registers (ruling `IX-Y` item 1): an
/// accessibility press on the element runs it. **An `Action`**, so it rides the
/// registry the keyboard already uses, as `AccessibilityAdjustment` does
/// (AB-I): `Handlers` gains no member, and the one disabled gate — which
/// registers no action for a disabled element — is the whole of "disabled
/// refuses" (A7). Internal: only the modifier registers it, only
/// `Window.handleAccessibilityRequest` sends it.
struct AccessibilityDefaultAction: Action {}

/// What `accessibilityAction(named:_:)` registers (ruling `IX-Y` item 2): one
/// handler per element, dispatching by `name`, which chains every named action
/// the element declares. Internal, for `AccessibilityDefaultAction`'s reason.
struct AccessibilityNamedAction: Action {
    let name: String
}
