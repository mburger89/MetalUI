// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
// Its own file so Foundation's names stay out of SDLPlatform.swift's type
// lookup — the drain is the one thing this module needs Foundation for.
import Foundation

extension SDLPlatform {
    /// Runs the main run loop once without waiting (ruling `SV-H` item 1):
    /// the main dispatch queue — main-actor tasks and continuations — and any
    /// `RunLoop.main.perform` blocks get their turn each pass, which SDL's own
    /// event pump never gives them on Linux or Windows (gap 10, `LC-L`'s `B1`).
    /// Effective only outside a main-actor job (`B2` against `J1`), which is
    /// why ``run()`` must be called from synchronous top-level code. On macOS
    /// SDL's Cocoa pump may already drain the queue; the extra pass is then a
    /// no-op.
    func drainMainQueue() {
        _ = RunLoop.main.run(mode: .default, before: .distantPast)
    }
}
#endif
