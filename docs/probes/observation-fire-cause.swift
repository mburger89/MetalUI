// Swift Observation probe: what does `withObservationTracking`'s `onChange` know about the write that fired it?
// (C14-j, `DM-E` in docs/superpowers/2026-10-21-retained-single-miss-decisions.md.)
//
// QUESTIONS.
// - A: does `onChange` fire (synchronously, on the writer's stack) for a write to an observed property?  (POSITIVE CONTROL)
// - B: do the closure's own arguments or the observed model name the property?  (SEPARATING ARM: the closure takes none; the
//      only handle is the model, whose registrar is not public API.)
// - C: do the writer's frames, captured inside `onChange`, contain the property's setter once demangled?
// - D: does a write to an UNOBSERVED property of the same model leave `onChange` silent (the control that C is not just
//      "any write")?
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc -Onone -swift-version 6 docs/probes/observation-fire-cause.swift -o /tmp/fire-cause && /tmp/fire-cause
//
// RECORDED and READING: the block at the end of this file.

import Foundation
import Observation

@Observable final class Model {
    var radius = 1.0
    var other = 2.0
}

nonisolated(unsafe) var fireCount = 0
nonisolated(unsafe) var causes: [String] = []

@_silgen_name("swift_demangle")
func _swiftDemangle(_ name: UnsafePointer<CChar>?, _ length: UInt, _ out: UnsafeMutablePointer<CChar>?,
                    _ outLength: UnsafeMutablePointer<UInt>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

func demangle(_ mangled: String) -> String? {
    mangled.withCString { p in
        guard let out = _swiftDemangle(p, UInt(strlen(p)), nil, nil, 0) else { return nil }
        defer { free(out) }
        return String(cString: out)
    }
}

@inline(never) func demangled(_ symbolLine: String) -> String? {
    for token in symbolLine.split(separator: " ") where token.hasPrefix("$s") || token.hasPrefix("_$s") {
        return demangle(String(token))
    }
    return nil
}

func capture() -> [String] {
    Thread.callStackSymbols.compactMap(demangled).filter { $0.contains(".setter") || $0.contains("withMutation") }
}

@inline(never) func writeRadius(_ m: Model) { m.radius = 5 }
@inline(never) func writeOther(_ m: Model) { m.other = 5 }

func armA() {
    let m = Model(); fireCount = 0; causes = []
    withObservationTracking { _ = m.radius } onChange: { fireCount += 1; causes = capture() }
    writeRadius(m)
    print("A (write to observed): fired \(fireCount)")
    print("C writer frames: \(causes)")
}
func armD() {
    let m = Model(); fireCount = 0; causes = []
    withObservationTracking { _ = m.radius } onChange: { fireCount += 1; causes = capture() }
    writeOther(m)
    print("D (write to unobserved sibling): fired \(fireCount)")
}
armA()
print("B: onChange is () -> Void and the model's registrar is internal: no property name is passed")
armD()

// RECORDED (macOS, swift 6.4, 2026-10-21).
//   -Onone:  A fired 1 | C writer frames: [ObservationRegistrar.withMutation(of:keyPath:_:), Model.withMutation(keyPath:_:),
//            "main.Model.radius.setter : Swift.Double"] | D fired 0
//   -O:      A fired 1 | C writer frames: [ObservationRegistrar.withMutation(of:keyPath:_:)] only (setter inlined) | D fired 0
// READING. A and D hold (positive control; the silent sibling write). B: the closure receives nothing and the registrar is not
// public, so no key path is available (`DM-E`). C: in a debug build the writer's setter is on the stack inside `onChange`, so the
// trace can name `Model.radius.setter`; in a release build it is inlined and only `withMutation` remains, so the cause is `?`
// there, stated as such. The cause is a diagnostic only: no decision reads it.
