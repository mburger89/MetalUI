// Swift Observation probe: nested `withObservationTracking` scopes (C14,
// incremental invalidation; IV-C in
// docs/superpowers/2026-10-13-incremental-invalidation-decisions.md).
//
// QUESTIONS.
// - N: with an INNER tracking call inside an OUTER one, a read in the inner
//   apply closure: does the inner `onChange` fire, does the outer's?
//   A read in the outer apply closure outside the inner call: outer only?
// - M: is the outer session still armed (and does it fire) for a property read
//   only inside the inner call, i.e. are the access lists merged upward?
// - T: the per-scope token trick (`RedrawSentinel`, generalised): a scope that
//   reads its own `@Observable` token in its session, and whose token is
//   written before it re-evaluates, has its previous session fired and consumed
//   -- N re-evaluations then ONE property write give ONE onChange of the live
//   session (plus N-1 flush callbacks), not N.
// - U: control for T without a token: N re-evaluations then one write gives N
//   onChange calls (the accumulation RedrawSentinel documents).
//
// POSITIVE CONTROL. N0: a single tracking call, write after read, fires once.
// SEPARATING ARMS. T vs U (the token is the only difference).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc -swift-version 6 docs/probes/swift-observation-nested-scopes.swift -o /tmp/iv-obs && /tmp/iv-obs
//
// RECORDED and READING: the block at the end of this file.

import Observation

@Observable final class Model {
    var a = 0
    var b = 0
}
@Observable final class Token { var tick = 0 }

nonisolated(unsafe) var fired: [String] = []

func n0() {
    let m = Model(); fired = []
    withObservationTracking { _ = m.a } onChange: { fired.append("only") }
    m.a += 1
    print("N0 single call, write a:", fired)
}

func nested(_ m: Model) {
    withObservationTracking {
        _ = m.b
        withObservationTracking { _ = m.a } onChange: { fired.append("inner") }
    } onChange: { fired.append("outer") }
}
func n1() {
    var m = Model(); fired = []; nested(m)
    m.a += 1
    print("N  write a (read only in the inner call):", fired.sorted())
    m = Model(); fired = []; nested(m)
    m.b += 1
    print("N  write b (read in the outer call only):", fired.sorted())
}

func n2() {
    let m = Model(); fired = []
    withObservationTracking {
        withObservationTracking { _ = m.a } onChange: { fired.append("inner") }
    } onChange: { fired.append("outer") }
    m.b += 1
    print("M  write b (read nowhere):", fired)
    m.a += 1
    print("M  write a (read only in inner):", fired)
}

func tArm(withToken: Bool, reevaluations n: Int) {
    let m = Model(), token = Token(); fired = []
    for i in 0..<n {
        if withToken && i > 0 { token.tick &+= 1 }   // flush the previous session
        withObservationTracking {
            if withToken { _ = token.tick }
            _ = m.a
        } onChange: { fired.append("s") }
    }
    let afterFlush = fired.count
    fired = []
    m.a += 1
    print("\(withToken ? "T" : "U") \(n) re-evaluations: flush callbacks \(afterFlush), then one write -> \(fired.count) onChange")
}

n0(); n1(); n2()
tArm(withToken: true, reevaluations: 50)
tArm(withToken: false, reevaluations: 50)

// RECORDED (swift 6.4 / macOS 27 arm64, 2026-10-13; N and M lines sorted, the
// callback ORDER between inner and outer was seen both ways across runs):
//
//   N0 single call, write a:                         ["only"]         (positive control)
//   N  write a (read only in the inner call):        ["inner", "outer"]
//   N  write b (read in the outer call only):        ["outer"]
//   M  write b (read nowhere):                       []
//   M  write a (read only in inner):                 ["inner", "outer"]
//   T 50 re-evaluations: flush callbacks 49, then one write -> 1 onChange
//   U 50 re-evaluations: flush callbacks 0,  then one write -> 50 onChange
//
// READING. (1) Access lists MERGE UPWARD: a read inside a nested tracking call
// is also registered with every enclosing call, so an outer session cannot tell
// "a read of mine changed" from "a read of a nested scope changed" (N, M), and
// the order of the two callbacks is unspecified. Per-Component sessions inside
// the window's one whole-frame session therefore cannot be told apart from it;
// IV-C rules the consequence. (2) The per-scope token generalises RedrawSentinel
// exactly: one live session per scope, N-1 flush callbacks, one onChange (T);
// without it the sessions accumulate linearly (U). Public API only: nothing here
// uses an SPI, so Linux and Windows behave as the toolchain's Observation does.
