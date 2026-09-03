import Observation

/// A liveness token whose only purpose is to be written once per frame, so that
/// every `withObservationTracking` session armed by a previous frame fires and
/// is thereby **removed**.
///
/// **Why this exists at all.** `withObservationTracking` installs an observer
/// per tracked property per call and removes it only when `onChange` fires. It
/// offers no cancellation: it returns nothing and exposes no handle, and
/// `ObservationRegistrar`'s install path is not public for arbitrary models. So
/// re-registering every frame — which design spec §4.4 prescribes, calling the
/// one-shot behaviour "ideal, since we re-register every frame" — accumulates
/// one observer per *drawn frame* on every property that has not changed.
///
/// **Measured** on a standalone probe (`swiftc -O -swift-version 6`), reading
/// one `@Observable` property across N frames and then writing it once: N = 1
/// gives 1 `onChange` call, N = 10 gives 10, N = 1000 gives 1000. Linear, no
/// plateau. MetalUI's common case is the pathological one — scrolling a list
/// draws frames continuously while the document model is static.
///
/// With this sentinel read inside every session and written at the top of every
/// frame, the same probe gives **1** at every N up to 10,000, with N−1 flush
/// callbacks: exactly one session outstanding at any moment.
///
/// `internal`, and deliberately not `public`: it is a mechanism, not API. See
/// `Window.drawFrameIfNeeded` for the three orderings that make it work.
@Observable
final class RedrawSentinel {
    /// Incremented with `&+=` rather than `+=`. This is a liveness token and
    /// never a quantity, and a window running for weeks must not trap on
    /// overflow.
    var tick: Int = 0
}
