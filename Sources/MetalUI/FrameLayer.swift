import MetalUICore
import MetalUILayout

// The legacy (CSS-engine) frame's one semantic home.
//
// `Sources/MetalUI/ModifiedElement.swift` is one of the eight files a parallel
// track also edits, and this milestone's frame work would otherwise land on its
// last lines — the exact hunk boundary that track appends at (frame-sizing
// critic finding 14). So `ModifiedElement.swift` keeps a one-line forwarding
// declaration and every change to the legacy frame's meaning happens here, in a
// file no other track touches.
//
// Step 0 of lane 1 is deliberately a **no-behaviour-change** move: `style()`
// below reproduces `ElementGroup.frame(width:height:)`'s previous body
// verbatim. Lane 2 (ruling FR-C) gives `FrameSpec` its min/max bounds and
// alignment and grows this table.

/// SwiftUI's frame as one value: what `.frame(...)` asked for, before the CSS
/// lowering that ``style()`` performs.
///
/// **INTERNAL on purpose** (ruling FR-C): it appears in no public signature —
/// the frame overloads return `ModifiedElement<LayerBase>` — so a `public`
/// spelling would be a name an outside module can neither construct nor read,
/// which is the declared-but-inert shape CLAUDE.md keeps a table of. There is
/// nothing to narrow later, so no plain-import typecheck guard is owed
/// (practices shape 16 applies to narrowing an EXISTING public name).
struct FrameSpec: Sendable, Hashable {
    var width: Pixels?
    var height: Pixels?

    init(width: Pixels? = nil, height: Pixels? = nil) {
        self.width = width
        self.height = height
    }

    /// The one place the CSS approximation of a SwiftUI frame lives.
    ///
    /// Today's rows, unchanged by step 0: the layer is a flex container centred
    /// on both axes, and a declared axis writes `size.<axis>`. Nothing else —
    /// `FrameModifier.init`'s style, verbatim, before that type was deleted.
    func style() -> Style {
        var style = Style()
        style.alignItems = .center
        style.justifyContent = .center
        if let width { style.size.width = .length(.pixels(width)) }
        if let height { style.size.height = .length(.pixels(height)) }
        return style
    }
}

extension ElementGroup {
    /// SwiftUI's own rejection of an argument-less frame, verbatim (ruling
    /// FR-J).
    ///
    /// Every parameter of `frame(width:height:)` has a default, so `.frame()`
    /// used to compile silently and build a real centring, size-nothing layer —
    /// a node, an identity level and a `$anim` slot for nothing (`SA-N` item 9).
    /// SwiftUI answers that with a separate zero-parameter overload marked
    /// deprecated, which the compiler prefers for a no-argument call; this is
    /// the same overload with the same message, returning the receiver so it
    /// contributes nothing.
    ///
    /// **A matching declaration on `ProposalElementGroup` is load-bearing, not
    /// redundant** (`NativeModifiedContent.swift`). With this one alone, a
    /// no-argument call on a proposal element resolves to that refined
    /// protocol's own all-defaulted `frame(width:height:alignment:)` — more
    /// specialized, so it wins — and infers `ModifiedContent<…>` with no
    /// diagnostic at all, which is `SA-N` item 9 surviving on the path that
    /// matters. Measured; pinned by the typecheck fixture
    /// `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`.
    ///
    /// `.frame(alignment:)` is deliberately left alone: SwiftUI accepts it too,
    /// and an alignment with nothing to align is a no-op in both.
    @available(*, deprecated, message: "Please pass one or more parameters.")
    public func frame() -> Self { self }
}
