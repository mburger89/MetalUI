/// Transitions' captures and progress (plan task 13, ruling `AN-AE` as amended
/// by `AN-AH`; spec §6.5), held by the window's `AnimationStore`.
///
/// **A stub, by design** (spec §7): lane 1 declares the type and the three
/// hooks `Frame.render` calls — after layout, after the tree's paint, and at
/// the frame's end — and lane 3 fills them. Until then each is a no-op, and a
/// tree captures nothing.
@MainActor
final class TransitionStore {
    init() {}

    /// Called once per frame after the root layout is computed, before
    /// prepaint.
    func afterLayout(_ frame: Frame) {}

    /// Called once per frame after the tree has painted, before the glyph
    /// atlas's frame bracket closes, so whatever it emits can still reach the
    /// atlas.
    func paintGhosts(_ pass: inout PaintPass) {}

    /// Called once per frame at its end, before the `AnimationStore` drops
    /// untouched entries.
    func endFrame() {}
}
