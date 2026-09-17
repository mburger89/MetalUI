// ALLOCATION MODEL (not a SwiftUI probe, not the real module) for ruling MC-K
// in docs/superpowers/2026-09-15-modifier-composition-decisions.md, written
// after design-review finding 4 (MC-N). It copies
// Tests/MetalUILayoutTests/FreezeLoopAllocationTests.swift's malloc_logger
// counter and counts heap allocations on the calling thread for 500 builds of
// 1-, 2- and 3-layer chains: MC-A's flat storage (outermost layer inline, the
// rest in an array; a Layout holding the outer node inline and the inner nodes
// in an array) against today's nested `Box<Box<…>>`. Each "build" constructs
// the chain and runs a model `requestLayout` that returns `[NodeID]` as the
// real protocol does. Every path is run three times before counting, so
// one-time generic-metadata instantiation is not counted.
//
// HOW TO RUN:  swiftc -swift-version 5 -Onone LayerAllocationModel.swift -o m && ./m
//              (and -O; and with `xcrun swiftc`)
//
// RECORDED 2026-09-15, macOS 26.6.2. Totals over 500 builds; divide by 500 for
// per-chain counts.
//
//   swiftc 6.3.3 (swift.org), -Onone: calibration 16 buffers -> 16
//     layers=1: nestedBox=1000 flat(construct+layout)=1000 flat(construct only)=0
//     layers=2: nestedBox=1500 flat(construct+layout)=3000 flat(construct only)=500
//     layers=3: nestedBox=2000 flat(construct+layout)=4500 flat(construct only)=1000
//   swiftc 6.3.3, -O: calibration 16 -> 16
//     layers=1: nestedBox=0 flat=500  construct only=0
//     layers=2: nestedBox=0 flat=1500 construct only=500
//     layers=3: nestedBox=0 flat=2000 construct only=1000
//   xcrun swiftc 6.4 (swiftlang), -Onone: calibration 16 -> 32 (the toolchain floor CLAUDE.md records)
//     layers=1: nestedBox=1500 flat=1500 construct only=500
//     layers=2: nestedBox=2000 flat=3500 construct only=1000
//     layers=3: nestedBox=2500 flat=5000 construct only=1500
//   xcrun swiftc 6.4, -O: identical to swiftc 6.3.3 -O except layers=3 nestedBox=500.
//
// PER CHAIN, swift.org -Onone: nested 2/3/4 (the `[NodeID]` each layout call
// returns), flat 2/6/9 -- so +0/+3/+5 over nested for 1/2/3 layers. At -O:
// nested 0/0/0, flat 1/3/4. Construction alone costs k-1 buffers for k layers.
//
// WHY k-1, measured rather than assumed: a variant with `consuming func _wrap`
// and `consuming func padding` (sed over this file) printed the SAME numbers at
// -Onone and -O. The buffers are the array's growth on append (an empty array
// owns no buffer; the first append allocates one), not copy-on-write of a
// shared buffer, so `consuming` cannot remove them. Only inline storage can.
//
// WHAT THIS DOES NOT SHOW: the real module's counts. `Style`, `Decoration` and
// `Handlers` differ from this model's; lane 2 re-measures in the test build.

import Darwin
// ---- instrument: FreezeLoopAllocationTests.swift's malloc_logger counter, verbatim shape
typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
let mallocLogTypeAllocate: UInt32 = 2
nonisolated(unsafe) var allocationsSeen = 0
nonisolated(unsafe) var countedThread: pthread_t?
nonisolated(unsafe) var chainedLogger: MallocLogger?
nonisolated(unsafe) let countingLogger: MallocLogger = { type, a1, a2, a3, result, skip in
    if type & mallocLogTypeAllocate != 0, let t = countedThread, pthread_equal(t, pthread_self()) != 0 { allocationsSeen += 1 }
    chainedLogger?(type, a1, a2, a3, result, skip)
}
func countAllocations(_ body: () -> Void) -> Int {
    let slot = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")!.assumingMemoryBound(to: MallocLogger?.self)
    _ = countingLogger; _ = mallocLogTypeAllocate
    chainedLogger = slot.pointee; allocationsSeen = 0; countedThread = pthread_self()
    slot.pointee = countingLogger; body(); slot.pointee = chainedLogger; countedThread = nil
    return allocationsSeen
}
@inline(never) func allocateBuffers(_ count: Int) -> Int {
    var total = 0
    for i in 0..<count { let b = ContiguousArray<Double>(repeating: Double(i), count: 16 + i); total &+= b.count }
    return total
}
// ---- model: a Style-sized layer (the real Style is large), handlers as optional closures
struct Style { var a: (Double, Double, Double, Double, Double, Double, Double, Double) = (0,0,0,0,0,0,0,0)
               var b: (Double, Double, Double, Double, Double, Double, Double, Double) = (0,0,0,0,0,0,0,0)
               var padding: Double = 0 }
struct Handlers { var onClick: (() -> Void)? = nil; var onKey: ((Int) -> Bool)? = nil }
struct NodeID { var i: Int }
struct Pass { var next = 0; mutating func node() -> NodeID { next += 1; return NodeID(i: next) } }

protocol Group { associatedtype L; associatedtype LayerBase: Group = Self
  mutating func layout(_ p: inout Pass) -> ([NodeID], L)
  func _wrap(_ l: Layer) -> Flat<LayerBase> }
protocol El: Group {}
struct Layer { var style = Style(); var handlers = Handlers() }
struct Leaf: El { var style = Style(); mutating func layout(_ p: inout Pass) -> ([NodeID], NodeID) { let n = p.node(); return ([n], n) } }
extension Group where LayerBase == Self { func _wrap(_ l: Layer) -> Flat<Self> { Flat(content: self, outermost: l, inner: []) } }

// nested: today's Box<Self>
struct Box<C: Group>: El { var style = Style(); var handlers = Handlers(); var content: C
  struct BL { var node: NodeID; var c: C.L }
  mutating func layout(_ p: inout Pass) -> ([NodeID], BL) { let (_, cl) = content.layout(&p); let n = p.node(); return ([n], BL(node: n, c: cl)) } }
extension Group { func boxPadding(_ v: Double) -> Box<Self> { var b = Box(content: self); b.style.padding = v; return b } }

// flat: MC-A, outermost inline, the rest in an array; Layout stores outermost node inline, the rest in an array
struct Flat<C: Group>: El { typealias LayerBase = C
  var content: C; var outermost: Layer; var inner: [Layer]
  struct FL { var outer: NodeID; var inner: [NodeID]; var c: C.L }
  func _wrap(_ l: Layer) -> Flat<C> { var c = self; c.inner.append(c.outermost); c.outermost = l; return c }
  mutating func layout(_ p: inout Pass) -> ([NodeID], FL) {
    let (_, cl) = content.layout(&p)
    var innerNodes: [NodeID] = []
    if !inner.isEmpty { innerNodes.reserveCapacity(inner.count); for _ in inner { innerNodes.append(p.node()) } }
    let o = p.node(); return ([o], FL(outer: o, inner: innerNodes, c: cl)) } }
extension Group { func padding(_ v: Double) -> Flat<LayerBase> { var l = Layer(); l.style.padding = v; return _wrap(l) } }

@inline(never) func buildNested(_ k: Int, _ p: inout Pass) {
    switch k {
    case 1: var e = Leaf().boxPadding(1); _ = e.layout(&p)
    case 2: var e = Leaf().boxPadding(1).boxPadding(2); _ = e.layout(&p)
    default: var e = Leaf().boxPadding(1).boxPadding(2).boxPadding(3); _ = e.layout(&p)
    }
}
@inline(never) func buildFlat(_ k: Int, _ p: inout Pass) {
    switch k {
    case 1: var e = Leaf().padding(1); _ = e.layout(&p)
    case 2: var e = Leaf().padding(1).padding(2); _ = e.layout(&p)
    default: var e = Leaf().padding(1).padding(2).padding(3); _ = e.layout(&p)
    }
}
@inline(never) func constructFlatOnly(_ k: Int) -> Int {
    switch k { case 1: return Leaf().padding(1).inner.count
    case 2: return Leaf().padding(1).padding(2).inner.count
    default: return Leaf().padding(1).padding(2).padding(3).inner.count }
}
let reps = 500
_ = allocateBuffers(16)
let cal = countAllocations { _ = allocateBuffers(16) }
print("calibration 16 buffers -> \(cal)")
for k in 1...3 { var w = Pass(); for _ in 0..<3 { buildNested(k, &w); buildFlat(k, &w); _ = constructFlatOnly(k) } }
for k in 1...3 {
    var p1 = Pass(), p2 = Pass()
    let n = countAllocations { for _ in 0..<reps { buildNested(k, &p1) } }
    let f = countAllocations { for _ in 0..<reps { buildFlat(k, &p2) } }
    var s = 0
    let c = countAllocations { for _ in 0..<reps { s &+= constructFlatOnly(k) } }
    print("layers=\(k) x\(reps): nestedBox=\(n) flat(construct+layout)=\(f) flat(construct only)=\(c)")
}
