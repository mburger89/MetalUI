// Swift Observation probe, release arm: with the setter inlined, what is left on the stack inside `onChange` to name the writer?
// (C14-l, `AM-G` in docs/superpowers/2026-10-22-retained-move-miss-decisions.md; the debug arm is `observation-fire-cause.swift`.)
//
// QUESTIONS.
// - A (POSITIVE CONTROL): at -Onone the stack inside `onChange` holds the property's setter, demangled `Model.radius.setter`.
// - B (SEPARATING ARM): at -O the setter is inlined into the writer: the stack holds no `.setter` frame.
// - C: at -O is the WRITER's own function (an `@inline(never)` caller, as an app's gesture closure or action is) still on the stack
//   above the observation machinery?  If so the rule "nearest frame above the machinery" names it.
// - D: with the writer itself inlined into `main` (nothing above the machinery but the entry), what does the rule see?
//
// HOW TO RUN (SA-O):
//
//   xcrun swiftc -Onone -swift-version 6 docs/probes/observation-fire-cause-release.swift -o /tmp/fcr-debug && /tmp/fcr-debug
//   xcrun swiftc -O     -swift-version 6 docs/probes/observation-fire-cause-release.swift -o /tmp/fcr-release && /tmp/fcr-release
//
// RECORDED and READING: the block at the end of this file.

import Foundation
import Observation

@Observable final class Model {
    var radius = 1.0
}

nonisolated(unsafe) var frames: [String] = []

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

/// Every frame of the stack, demangled where a Swift symbol is named, else the raw token after the address.
func capture() -> [String] {
    Thread.callStackSymbols.map { line in
        for token in line.split(separator: " ") where token.hasPrefix("$s") || token.hasPrefix("_$s") {
            if let name = demangle(String(token)) { return name }
        }
        return line.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).first.map(String.init) ?? line
    }
}

@inline(never) func theWriter(_ m: Model) { m.radius = 5 }

func arm(_ label: String, _ write: (Model) -> Void) {
    let m = Model(); frames = []
    withObservationTracking { _ = m.radius } onChange: { frames = capture() }
    write(m)
    print("\(label): \(frames.count) frames, setter frame: \(frames.contains { $0.contains(".setter") })")
    for f in frames.prefix(8) { print("    \(f)") }
}
arm("writer behind @inline(never)") { theWriter($0) }
arm("writer inlined into the call site") { $0.radius = 7 }

// RECORDED (macOS arm64, swift 6.4, 2026-10-22): see the two blocks printed by the commands above; copied into
// docs/record/146-retained-move-miss.md section 4 with the reading.
