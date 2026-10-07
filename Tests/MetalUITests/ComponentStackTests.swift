import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// MG-15 (rulings `PE-J`, `PE-K`, `PE-L`, `PE-P`;
// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`, spec §6.2):
// the stack a `Component` tree costs in a debug build, measured by the
// internal `StackMeter` (debug-only, main-thread-only samples in every
// `ElementBuilder` method, both `Component` layout entries and
// `Frame.requestNativeLeaf`).
//
// The SMK configurator's root — a shell `Component` switching between pane
// `Component`s — overflowed an 8 MB main-thread stack in a debug build while
// every pane alone built fine: `ComponentLayout<C>` stored `C.Content` and its
// `GroupLayout` inline, so each `EitherGroup` level of the shell's `switch`
// held pane-sized layout temporaries (`PE-J`'s table: ~100 KB per level). The
// box (`PE-J`) makes a shell cost about one pane; an inline `switch` over
// large subtrees inside ONE builder still grows with every branch (a compiler
// property, `PE-K`). `PE-L`'s window warning (spec tests 2.4, 2.5) waits on
// the re-take of its 512 KiB threshold: the production trees measure above it
// (record §78).
//
// Every figure here is a byte count of stack, never a time. The tests print
// their figures (`STACK-METER …` lines) for record §78.

/// The stack `make()`'s build, layout, prepaint and paint use, in bytes,
/// rendered once into a production `Frame` at `width`×`height` inside a
/// `StackMeter` measurement, and the deepest `Component`'s type.
@MainActor
func stackHighWater<E: ElementGroup>(width: Float = 920, height: Float = 560,
                                     _ make: @MainActor () -> E) -> (bytes: Int, deepest: String?) {
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1)
    let (_, bytes, deepest) = StackMeter.measuring {
        var root = DifferentialRoot(width: width, height: height, content: make)
        frame.render(&root)
    }
    return (bytes, deepest)
}

private func kib(_ bytes: Int) -> String { String(format: "%.1f KiB", Double(bytes) / 1024) }

/// A recursion `depth` frames deep that samples at its bottom — a known,
/// growing amount of stack for the meter's own tests.
@inline(never)
private func sampleAtDepth(_ depth: Int) -> Int {
    var padding = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    padding.0 = depth
    if depth == 0 {
        StackMeter.sample()
        return padding.0
    }
    return withUnsafeMutablePointer(to: &padding) { $0.pointee.0 } + sampleAtDepth(depth - 1)
}

/// A secondary thread's entry: `sampleAtDepth(64)`. A nonisolated global
/// function, not a closure in the `@MainActor` test, which would be inferred
/// main-actor isolated and trap on the executor check when the thread enters it.
private func sampleOnASecondaryThread(_: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    _ = sampleAtDepth(64)
    return nil
}

/// **2.1** (`PE-J`). A shell `Component` switching over twelve pane
/// `Component`s uses about the stack of one pane: the difference is at most
/// 16 KiB (the design session measured 4.5 KB; the boxless layout 508 KB).
///
/// Red before the box (`ComponentLayout` storing its payload inline): pane
/// 1 211 584 bytes, shell 2 1 414 432, shell 12 1 719 328 — the difference
/// 507 744, the design session's 508 KB (its own figures were leaf samples
/// only: pane 424 KB; this meter also samples in every builder method, so it
/// sees the `content` getters' frames). Boxed (`PE-J`): pane 1 010 368,
/// shell 2 1 011 904, shell 12 1 014 880 — the difference 4 512, the design
/// session's 4.5 KB. Mutation M2.1 (the payload inline again) reddens it.
@Test @MainActor func aShellOverTwelveComponentPanesUsesTheStackOfOnePane() throws {
    let pane = stackHighWater { StackPane0() }
    let shell2 = stackHighWater { StackShell2(choice: .p0) }
    let shell12 = stackHighWater { StackShell12(choice: .p0) }
    print("STACK-METER pane \(pane.bytes) (\(kib(pane.bytes))), shell 2 \(shell2.bytes) (\(kib(shell2.bytes))), shell 12 \(shell12.bytes) (\(kib(shell12.bytes)))")
    try #require(pane.bytes > 0, "the meter measured nothing")
    #expect(pane.deepest?.hasSuffix("StackPane0") == true, "the deepest Component: \(pane.deepest ?? "nil")")
    #expect(shell12.bytes - pane.bytes <= 16 * 1024,
            "a shell over 12 panes costs \(kib(shell12.bytes - pane.bytes)) more than one pane")
}

/// **2.2** — the separating arm: the meter sees a `content` getter's own
/// frame. Calling the inline-12 shell's `content` getter alone — a build, no
/// layout, so no layout-time sample can run — measures more than 200 KiB:
/// the frame a debug build reserves for every branch's temporaries (`PE-K`),
/// seen only by the samples in `ElementBuilder`'s methods, which run inside
/// that frame. And laid out, one `Component` whose `switch` holds twelve
/// inline subtrees uses more than 200 KiB more stack than the same over two
/// (design, leaf samples only: 583 KB; this meter: 1 300 704 → 4 300 576
/// bytes after `PE-J`) — `PE-K`'s remaining cost, which no box removes.
///
/// Mutation M2.2 (no sampling in `ElementBuilder`) reads the getter alone as
/// 0. *(The laid-out difference alone could not separate: with leaf samples
/// only it still reads 594 912 bytes (405 824 → 1 000 736), because the layout functions' frames
/// grow with the branches' value sizes too — measured under M2.2.)*
@Test @MainActor func theStackMeterSeesTheContentGettersFrame() throws {
    let (_, getter, _) = StackMeter.measuring { _ = InlineStackShell12(choice: .p0).content }
    let inline2 = stackHighWater { InlineStackShell2(choice: .p0) }
    let inline12 = stackHighWater { InlineStackShell12(choice: .p0) }
    print("STACK-METER inline 12 getter alone \(getter) (\(kib(getter))); inline 2 \(inline2.bytes) (\(kib(inline2.bytes))), inline 12 \(inline12.bytes) (\(kib(inline12.bytes)))")
    #expect(getter > 200 * 1024, "the getter's own frame: \(kib(getter))")
    #expect(inline12.bytes - inline2.bytes > 200 * 1024,
            "inline 12 − inline 2 = \(kib(inline12.bytes - inline2.bytes))")
}

/// **2.3** (`PE-L` item 1, `PE-P`). A sample outside every measurement opens
/// nothing; a nested measurement returns its own figure and the enclosing one
/// is at least it; a sample from a secondary thread while a measurement is
/// open on the main thread changes nothing.
///
/// Mutations: M2.3 (a sample outside a scope opens one at its own address —
/// "the missing base" taken from the sample) → the first arm; M2.3b (no
/// main-thread check) → the secondary-thread arm (that thread's stack is not
/// the main thread's, so its address against the main entry is nonsense).
@Test @MainActor func theStackMeterMeasuresOnlyInsideAMeasurement() throws {
    try #require(StackMeter.isEnabled, "the suite runs a debug build")
    try #require(!StackMeter.isMeasuring, "no scope is open between tests")
    _ = sampleAtDepth(64)
    #expect(!StackMeter.isMeasuring, "a sample outside every measurement opened a scope")
    let (_, empty, _) = StackMeter.measuring {}
    #expect(empty == 0, "a measurement with no sample: \(empty)")

    let (inner, outer, _) = StackMeter.measuring { () -> Int in
        _ = sampleAtDepth(4)
        let (_, inner, _) = StackMeter.measuring { sampleAtDepth(64) }
        return inner
    }
    #expect(inner > 16 * 64, "64 frames of at least 16 words each: \(inner)")
    #expect(outer >= inner, "the enclosing scope folds in the nested one: outer \(outer), inner \(inner)")
    #expect(!StackMeter.isMeasuring, "every scope closed")

    // The secondary thread runs on a stack this test maps BELOW the main
    // thread's (checked, not assumed), so a sample from it would read deeper
    // than anything the main thread reached: without the main-thread check
    // the figure is nonsense megabytes. (On a thread Foundation places, macOS
    // arm64 maps the stack above the main thread's, where an uncounted and a
    // counted sample read alike — measured: M2.3b stayed green on that arm.)
    var marker: UInt8 = 0
    let mainAddress = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
    let stackSize = 1 << 20
    let hint = UnsafeMutableRawPointer(bitPattern: (mainAddress - (512 << 20)) & ~UInt(0xFFFF))
    let mapped = try #require(mmap(hint, stackSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0))
    try #require(mapped != MAP_FAILED, "mmap failed")
    defer { munmap(mapped, stackSize) }
    try #require(UInt(bitPattern: mapped) + UInt(stackSize) < mainAddress,
                 "the mapped stack is below the main thread's")
    var attributes = pthread_attr_t()
    pthread_attr_init(&attributes)
    defer { pthread_attr_destroy(&attributes) }
    try #require(pthread_attr_setstack(&attributes, mapped, stackSize) == 0)
    let (_, crossThread, _) = try StackMeter.measuring { () throws -> Void in
        var thread: pthread_t?
        try #require(pthread_create(&thread, &attributes, sampleOnASecondaryThread, nil) == 0)
        pthread_join(try #require(thread), nil)
    }
    #expect(crossThread == 0, "a secondary thread's samples are not counted: \(crossThread)")
}

// MARK: - Generated fixtures (spec §6.2: twelve pane types, shells over 2 and 12, inline shells)
//
// Generated once by a throwaway script and checked in (no build-time generation).
// A pane is a `Component` over a `Column` of twelve `Row { Text; Box; Text }`;
// a shell is a `Component` whose `content` switches over N distinct pane types;
// an inline shell is ONE `Component` whose `switch` holds N such `Column`s inline.

enum StackPaneChoice: CaseIterable {
    case p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11
}

struct StackPane0: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p0.0 a"); Box().cssWidth(Pixels(4)); Text("p0.0 b") }
            Row { Text("p0.1 a"); Box().cssWidth(Pixels(4)); Text("p0.1 b") }
            Row { Text("p0.2 a"); Box().cssWidth(Pixels(4)); Text("p0.2 b") }
            Row { Text("p0.3 a"); Box().cssWidth(Pixels(4)); Text("p0.3 b") }
            Row { Text("p0.4 a"); Box().cssWidth(Pixels(4)); Text("p0.4 b") }
            Row { Text("p0.5 a"); Box().cssWidth(Pixels(4)); Text("p0.5 b") }
            Row { Text("p0.6 a"); Box().cssWidth(Pixels(4)); Text("p0.6 b") }
            Row { Text("p0.7 a"); Box().cssWidth(Pixels(4)); Text("p0.7 b") }
            Row { Text("p0.8 a"); Box().cssWidth(Pixels(4)); Text("p0.8 b") }
            Row { Text("p0.9 a"); Box().cssWidth(Pixels(4)); Text("p0.9 b") }
            Row { Text("p0.10 a"); Box().cssWidth(Pixels(4)); Text("p0.10 b") }
            Row { Text("p0.11 a"); Box().cssWidth(Pixels(4)); Text("p0.11 b") }
        }
    }
}

struct StackPane1: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p1.0 a"); Box().cssWidth(Pixels(4)); Text("p1.0 b") }
            Row { Text("p1.1 a"); Box().cssWidth(Pixels(4)); Text("p1.1 b") }
            Row { Text("p1.2 a"); Box().cssWidth(Pixels(4)); Text("p1.2 b") }
            Row { Text("p1.3 a"); Box().cssWidth(Pixels(4)); Text("p1.3 b") }
            Row { Text("p1.4 a"); Box().cssWidth(Pixels(4)); Text("p1.4 b") }
            Row { Text("p1.5 a"); Box().cssWidth(Pixels(4)); Text("p1.5 b") }
            Row { Text("p1.6 a"); Box().cssWidth(Pixels(4)); Text("p1.6 b") }
            Row { Text("p1.7 a"); Box().cssWidth(Pixels(4)); Text("p1.7 b") }
            Row { Text("p1.8 a"); Box().cssWidth(Pixels(4)); Text("p1.8 b") }
            Row { Text("p1.9 a"); Box().cssWidth(Pixels(4)); Text("p1.9 b") }
            Row { Text("p1.10 a"); Box().cssWidth(Pixels(4)); Text("p1.10 b") }
            Row { Text("p1.11 a"); Box().cssWidth(Pixels(4)); Text("p1.11 b") }
        }
    }
}

struct StackPane2: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p2.0 a"); Box().cssWidth(Pixels(4)); Text("p2.0 b") }
            Row { Text("p2.1 a"); Box().cssWidth(Pixels(4)); Text("p2.1 b") }
            Row { Text("p2.2 a"); Box().cssWidth(Pixels(4)); Text("p2.2 b") }
            Row { Text("p2.3 a"); Box().cssWidth(Pixels(4)); Text("p2.3 b") }
            Row { Text("p2.4 a"); Box().cssWidth(Pixels(4)); Text("p2.4 b") }
            Row { Text("p2.5 a"); Box().cssWidth(Pixels(4)); Text("p2.5 b") }
            Row { Text("p2.6 a"); Box().cssWidth(Pixels(4)); Text("p2.6 b") }
            Row { Text("p2.7 a"); Box().cssWidth(Pixels(4)); Text("p2.7 b") }
            Row { Text("p2.8 a"); Box().cssWidth(Pixels(4)); Text("p2.8 b") }
            Row { Text("p2.9 a"); Box().cssWidth(Pixels(4)); Text("p2.9 b") }
            Row { Text("p2.10 a"); Box().cssWidth(Pixels(4)); Text("p2.10 b") }
            Row { Text("p2.11 a"); Box().cssWidth(Pixels(4)); Text("p2.11 b") }
        }
    }
}

struct StackPane3: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p3.0 a"); Box().cssWidth(Pixels(4)); Text("p3.0 b") }
            Row { Text("p3.1 a"); Box().cssWidth(Pixels(4)); Text("p3.1 b") }
            Row { Text("p3.2 a"); Box().cssWidth(Pixels(4)); Text("p3.2 b") }
            Row { Text("p3.3 a"); Box().cssWidth(Pixels(4)); Text("p3.3 b") }
            Row { Text("p3.4 a"); Box().cssWidth(Pixels(4)); Text("p3.4 b") }
            Row { Text("p3.5 a"); Box().cssWidth(Pixels(4)); Text("p3.5 b") }
            Row { Text("p3.6 a"); Box().cssWidth(Pixels(4)); Text("p3.6 b") }
            Row { Text("p3.7 a"); Box().cssWidth(Pixels(4)); Text("p3.7 b") }
            Row { Text("p3.8 a"); Box().cssWidth(Pixels(4)); Text("p3.8 b") }
            Row { Text("p3.9 a"); Box().cssWidth(Pixels(4)); Text("p3.9 b") }
            Row { Text("p3.10 a"); Box().cssWidth(Pixels(4)); Text("p3.10 b") }
            Row { Text("p3.11 a"); Box().cssWidth(Pixels(4)); Text("p3.11 b") }
        }
    }
}

struct StackPane4: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p4.0 a"); Box().cssWidth(Pixels(4)); Text("p4.0 b") }
            Row { Text("p4.1 a"); Box().cssWidth(Pixels(4)); Text("p4.1 b") }
            Row { Text("p4.2 a"); Box().cssWidth(Pixels(4)); Text("p4.2 b") }
            Row { Text("p4.3 a"); Box().cssWidth(Pixels(4)); Text("p4.3 b") }
            Row { Text("p4.4 a"); Box().cssWidth(Pixels(4)); Text("p4.4 b") }
            Row { Text("p4.5 a"); Box().cssWidth(Pixels(4)); Text("p4.5 b") }
            Row { Text("p4.6 a"); Box().cssWidth(Pixels(4)); Text("p4.6 b") }
            Row { Text("p4.7 a"); Box().cssWidth(Pixels(4)); Text("p4.7 b") }
            Row { Text("p4.8 a"); Box().cssWidth(Pixels(4)); Text("p4.8 b") }
            Row { Text("p4.9 a"); Box().cssWidth(Pixels(4)); Text("p4.9 b") }
            Row { Text("p4.10 a"); Box().cssWidth(Pixels(4)); Text("p4.10 b") }
            Row { Text("p4.11 a"); Box().cssWidth(Pixels(4)); Text("p4.11 b") }
        }
    }
}

struct StackPane5: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p5.0 a"); Box().cssWidth(Pixels(4)); Text("p5.0 b") }
            Row { Text("p5.1 a"); Box().cssWidth(Pixels(4)); Text("p5.1 b") }
            Row { Text("p5.2 a"); Box().cssWidth(Pixels(4)); Text("p5.2 b") }
            Row { Text("p5.3 a"); Box().cssWidth(Pixels(4)); Text("p5.3 b") }
            Row { Text("p5.4 a"); Box().cssWidth(Pixels(4)); Text("p5.4 b") }
            Row { Text("p5.5 a"); Box().cssWidth(Pixels(4)); Text("p5.5 b") }
            Row { Text("p5.6 a"); Box().cssWidth(Pixels(4)); Text("p5.6 b") }
            Row { Text("p5.7 a"); Box().cssWidth(Pixels(4)); Text("p5.7 b") }
            Row { Text("p5.8 a"); Box().cssWidth(Pixels(4)); Text("p5.8 b") }
            Row { Text("p5.9 a"); Box().cssWidth(Pixels(4)); Text("p5.9 b") }
            Row { Text("p5.10 a"); Box().cssWidth(Pixels(4)); Text("p5.10 b") }
            Row { Text("p5.11 a"); Box().cssWidth(Pixels(4)); Text("p5.11 b") }
        }
    }
}

struct StackPane6: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p6.0 a"); Box().cssWidth(Pixels(4)); Text("p6.0 b") }
            Row { Text("p6.1 a"); Box().cssWidth(Pixels(4)); Text("p6.1 b") }
            Row { Text("p6.2 a"); Box().cssWidth(Pixels(4)); Text("p6.2 b") }
            Row { Text("p6.3 a"); Box().cssWidth(Pixels(4)); Text("p6.3 b") }
            Row { Text("p6.4 a"); Box().cssWidth(Pixels(4)); Text("p6.4 b") }
            Row { Text("p6.5 a"); Box().cssWidth(Pixels(4)); Text("p6.5 b") }
            Row { Text("p6.6 a"); Box().cssWidth(Pixels(4)); Text("p6.6 b") }
            Row { Text("p6.7 a"); Box().cssWidth(Pixels(4)); Text("p6.7 b") }
            Row { Text("p6.8 a"); Box().cssWidth(Pixels(4)); Text("p6.8 b") }
            Row { Text("p6.9 a"); Box().cssWidth(Pixels(4)); Text("p6.9 b") }
            Row { Text("p6.10 a"); Box().cssWidth(Pixels(4)); Text("p6.10 b") }
            Row { Text("p6.11 a"); Box().cssWidth(Pixels(4)); Text("p6.11 b") }
        }
    }
}

struct StackPane7: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p7.0 a"); Box().cssWidth(Pixels(4)); Text("p7.0 b") }
            Row { Text("p7.1 a"); Box().cssWidth(Pixels(4)); Text("p7.1 b") }
            Row { Text("p7.2 a"); Box().cssWidth(Pixels(4)); Text("p7.2 b") }
            Row { Text("p7.3 a"); Box().cssWidth(Pixels(4)); Text("p7.3 b") }
            Row { Text("p7.4 a"); Box().cssWidth(Pixels(4)); Text("p7.4 b") }
            Row { Text("p7.5 a"); Box().cssWidth(Pixels(4)); Text("p7.5 b") }
            Row { Text("p7.6 a"); Box().cssWidth(Pixels(4)); Text("p7.6 b") }
            Row { Text("p7.7 a"); Box().cssWidth(Pixels(4)); Text("p7.7 b") }
            Row { Text("p7.8 a"); Box().cssWidth(Pixels(4)); Text("p7.8 b") }
            Row { Text("p7.9 a"); Box().cssWidth(Pixels(4)); Text("p7.9 b") }
            Row { Text("p7.10 a"); Box().cssWidth(Pixels(4)); Text("p7.10 b") }
            Row { Text("p7.11 a"); Box().cssWidth(Pixels(4)); Text("p7.11 b") }
        }
    }
}

struct StackPane8: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p8.0 a"); Box().cssWidth(Pixels(4)); Text("p8.0 b") }
            Row { Text("p8.1 a"); Box().cssWidth(Pixels(4)); Text("p8.1 b") }
            Row { Text("p8.2 a"); Box().cssWidth(Pixels(4)); Text("p8.2 b") }
            Row { Text("p8.3 a"); Box().cssWidth(Pixels(4)); Text("p8.3 b") }
            Row { Text("p8.4 a"); Box().cssWidth(Pixels(4)); Text("p8.4 b") }
            Row { Text("p8.5 a"); Box().cssWidth(Pixels(4)); Text("p8.5 b") }
            Row { Text("p8.6 a"); Box().cssWidth(Pixels(4)); Text("p8.6 b") }
            Row { Text("p8.7 a"); Box().cssWidth(Pixels(4)); Text("p8.7 b") }
            Row { Text("p8.8 a"); Box().cssWidth(Pixels(4)); Text("p8.8 b") }
            Row { Text("p8.9 a"); Box().cssWidth(Pixels(4)); Text("p8.9 b") }
            Row { Text("p8.10 a"); Box().cssWidth(Pixels(4)); Text("p8.10 b") }
            Row { Text("p8.11 a"); Box().cssWidth(Pixels(4)); Text("p8.11 b") }
        }
    }
}

struct StackPane9: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p9.0 a"); Box().cssWidth(Pixels(4)); Text("p9.0 b") }
            Row { Text("p9.1 a"); Box().cssWidth(Pixels(4)); Text("p9.1 b") }
            Row { Text("p9.2 a"); Box().cssWidth(Pixels(4)); Text("p9.2 b") }
            Row { Text("p9.3 a"); Box().cssWidth(Pixels(4)); Text("p9.3 b") }
            Row { Text("p9.4 a"); Box().cssWidth(Pixels(4)); Text("p9.4 b") }
            Row { Text("p9.5 a"); Box().cssWidth(Pixels(4)); Text("p9.5 b") }
            Row { Text("p9.6 a"); Box().cssWidth(Pixels(4)); Text("p9.6 b") }
            Row { Text("p9.7 a"); Box().cssWidth(Pixels(4)); Text("p9.7 b") }
            Row { Text("p9.8 a"); Box().cssWidth(Pixels(4)); Text("p9.8 b") }
            Row { Text("p9.9 a"); Box().cssWidth(Pixels(4)); Text("p9.9 b") }
            Row { Text("p9.10 a"); Box().cssWidth(Pixels(4)); Text("p9.10 b") }
            Row { Text("p9.11 a"); Box().cssWidth(Pixels(4)); Text("p9.11 b") }
        }
    }
}

struct StackPane10: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p10.0 a"); Box().cssWidth(Pixels(4)); Text("p10.0 b") }
            Row { Text("p10.1 a"); Box().cssWidth(Pixels(4)); Text("p10.1 b") }
            Row { Text("p10.2 a"); Box().cssWidth(Pixels(4)); Text("p10.2 b") }
            Row { Text("p10.3 a"); Box().cssWidth(Pixels(4)); Text("p10.3 b") }
            Row { Text("p10.4 a"); Box().cssWidth(Pixels(4)); Text("p10.4 b") }
            Row { Text("p10.5 a"); Box().cssWidth(Pixels(4)); Text("p10.5 b") }
            Row { Text("p10.6 a"); Box().cssWidth(Pixels(4)); Text("p10.6 b") }
            Row { Text("p10.7 a"); Box().cssWidth(Pixels(4)); Text("p10.7 b") }
            Row { Text("p10.8 a"); Box().cssWidth(Pixels(4)); Text("p10.8 b") }
            Row { Text("p10.9 a"); Box().cssWidth(Pixels(4)); Text("p10.9 b") }
            Row { Text("p10.10 a"); Box().cssWidth(Pixels(4)); Text("p10.10 b") }
            Row { Text("p10.11 a"); Box().cssWidth(Pixels(4)); Text("p10.11 b") }
        }
    }
}

struct StackPane11: Component {
    var content: some ElementGroup {
        Column {
            Row { Text("p11.0 a"); Box().cssWidth(Pixels(4)); Text("p11.0 b") }
            Row { Text("p11.1 a"); Box().cssWidth(Pixels(4)); Text("p11.1 b") }
            Row { Text("p11.2 a"); Box().cssWidth(Pixels(4)); Text("p11.2 b") }
            Row { Text("p11.3 a"); Box().cssWidth(Pixels(4)); Text("p11.3 b") }
            Row { Text("p11.4 a"); Box().cssWidth(Pixels(4)); Text("p11.4 b") }
            Row { Text("p11.5 a"); Box().cssWidth(Pixels(4)); Text("p11.5 b") }
            Row { Text("p11.6 a"); Box().cssWidth(Pixels(4)); Text("p11.6 b") }
            Row { Text("p11.7 a"); Box().cssWidth(Pixels(4)); Text("p11.7 b") }
            Row { Text("p11.8 a"); Box().cssWidth(Pixels(4)); Text("p11.8 b") }
            Row { Text("p11.9 a"); Box().cssWidth(Pixels(4)); Text("p11.9 b") }
            Row { Text("p11.10 a"); Box().cssWidth(Pixels(4)); Text("p11.10 b") }
            Row { Text("p11.11 a"); Box().cssWidth(Pixels(4)); Text("p11.11 b") }
        }
    }
}

struct StackShell2: Component {
    var choice: StackPaneChoice
    var content: some ElementGroup {
        switch choice {
        case .p0:
            StackPane0()
        default:
            StackPane1()
        }
    }
}

struct StackShell12: Component {
    var choice: StackPaneChoice
    var content: some ElementGroup {
        switch choice {
        case .p0:
            StackPane0()
        case .p1:
            StackPane1()
        case .p2:
            StackPane2()
        case .p3:
            StackPane3()
        case .p4:
            StackPane4()
        case .p5:
            StackPane5()
        case .p6:
            StackPane6()
        case .p7:
            StackPane7()
        case .p8:
            StackPane8()
        case .p9:
            StackPane9()
        case .p10:
            StackPane10()
        default:
            StackPane11()
        }
    }
}

struct InlineStackShell2: Component {
    var choice: StackPaneChoice
    var content: some ElementGroup {
        switch choice {
        case .p0:
            Column {
                Row { Text("i0.0 a"); Box().cssWidth(Pixels(4)); Text("i0.0 b") }
                Row { Text("i0.1 a"); Box().cssWidth(Pixels(4)); Text("i0.1 b") }
                Row { Text("i0.2 a"); Box().cssWidth(Pixels(4)); Text("i0.2 b") }
                Row { Text("i0.3 a"); Box().cssWidth(Pixels(4)); Text("i0.3 b") }
                Row { Text("i0.4 a"); Box().cssWidth(Pixels(4)); Text("i0.4 b") }
                Row { Text("i0.5 a"); Box().cssWidth(Pixels(4)); Text("i0.5 b") }
                Row { Text("i0.6 a"); Box().cssWidth(Pixels(4)); Text("i0.6 b") }
                Row { Text("i0.7 a"); Box().cssWidth(Pixels(4)); Text("i0.7 b") }
                Row { Text("i0.8 a"); Box().cssWidth(Pixels(4)); Text("i0.8 b") }
                Row { Text("i0.9 a"); Box().cssWidth(Pixels(4)); Text("i0.9 b") }
                Row { Text("i0.10 a"); Box().cssWidth(Pixels(4)); Text("i0.10 b") }
                Row { Text("i0.11 a"); Box().cssWidth(Pixels(4)); Text("i0.11 b") }
            }
        default:
            Column {
                Row { Text("i1.0 a"); Box().cssWidth(Pixels(4)); Text("i1.0 b") }
                Row { Text("i1.1 a"); Box().cssWidth(Pixels(4)); Text("i1.1 b") }
                Row { Text("i1.2 a"); Box().cssWidth(Pixels(4)); Text("i1.2 b") }
                Row { Text("i1.3 a"); Box().cssWidth(Pixels(4)); Text("i1.3 b") }
                Row { Text("i1.4 a"); Box().cssWidth(Pixels(4)); Text("i1.4 b") }
                Row { Text("i1.5 a"); Box().cssWidth(Pixels(4)); Text("i1.5 b") }
                Row { Text("i1.6 a"); Box().cssWidth(Pixels(4)); Text("i1.6 b") }
                Row { Text("i1.7 a"); Box().cssWidth(Pixels(4)); Text("i1.7 b") }
                Row { Text("i1.8 a"); Box().cssWidth(Pixels(4)); Text("i1.8 b") }
                Row { Text("i1.9 a"); Box().cssWidth(Pixels(4)); Text("i1.9 b") }
                Row { Text("i1.10 a"); Box().cssWidth(Pixels(4)); Text("i1.10 b") }
                Row { Text("i1.11 a"); Box().cssWidth(Pixels(4)); Text("i1.11 b") }
            }
        }
    }
}

struct InlineStackShell12: Component {
    var choice: StackPaneChoice
    var content: some ElementGroup {
        switch choice {
        case .p0:
            Column {
                Row { Text("i0.0 a"); Box().cssWidth(Pixels(4)); Text("i0.0 b") }
                Row { Text("i0.1 a"); Box().cssWidth(Pixels(4)); Text("i0.1 b") }
                Row { Text("i0.2 a"); Box().cssWidth(Pixels(4)); Text("i0.2 b") }
                Row { Text("i0.3 a"); Box().cssWidth(Pixels(4)); Text("i0.3 b") }
                Row { Text("i0.4 a"); Box().cssWidth(Pixels(4)); Text("i0.4 b") }
                Row { Text("i0.5 a"); Box().cssWidth(Pixels(4)); Text("i0.5 b") }
                Row { Text("i0.6 a"); Box().cssWidth(Pixels(4)); Text("i0.6 b") }
                Row { Text("i0.7 a"); Box().cssWidth(Pixels(4)); Text("i0.7 b") }
                Row { Text("i0.8 a"); Box().cssWidth(Pixels(4)); Text("i0.8 b") }
                Row { Text("i0.9 a"); Box().cssWidth(Pixels(4)); Text("i0.9 b") }
                Row { Text("i0.10 a"); Box().cssWidth(Pixels(4)); Text("i0.10 b") }
                Row { Text("i0.11 a"); Box().cssWidth(Pixels(4)); Text("i0.11 b") }
            }
        case .p1:
            Column {
                Row { Text("i1.0 a"); Box().cssWidth(Pixels(4)); Text("i1.0 b") }
                Row { Text("i1.1 a"); Box().cssWidth(Pixels(4)); Text("i1.1 b") }
                Row { Text("i1.2 a"); Box().cssWidth(Pixels(4)); Text("i1.2 b") }
                Row { Text("i1.3 a"); Box().cssWidth(Pixels(4)); Text("i1.3 b") }
                Row { Text("i1.4 a"); Box().cssWidth(Pixels(4)); Text("i1.4 b") }
                Row { Text("i1.5 a"); Box().cssWidth(Pixels(4)); Text("i1.5 b") }
                Row { Text("i1.6 a"); Box().cssWidth(Pixels(4)); Text("i1.6 b") }
                Row { Text("i1.7 a"); Box().cssWidth(Pixels(4)); Text("i1.7 b") }
                Row { Text("i1.8 a"); Box().cssWidth(Pixels(4)); Text("i1.8 b") }
                Row { Text("i1.9 a"); Box().cssWidth(Pixels(4)); Text("i1.9 b") }
                Row { Text("i1.10 a"); Box().cssWidth(Pixels(4)); Text("i1.10 b") }
                Row { Text("i1.11 a"); Box().cssWidth(Pixels(4)); Text("i1.11 b") }
            }
        case .p2:
            Column {
                Row { Text("i2.0 a"); Box().cssWidth(Pixels(4)); Text("i2.0 b") }
                Row { Text("i2.1 a"); Box().cssWidth(Pixels(4)); Text("i2.1 b") }
                Row { Text("i2.2 a"); Box().cssWidth(Pixels(4)); Text("i2.2 b") }
                Row { Text("i2.3 a"); Box().cssWidth(Pixels(4)); Text("i2.3 b") }
                Row { Text("i2.4 a"); Box().cssWidth(Pixels(4)); Text("i2.4 b") }
                Row { Text("i2.5 a"); Box().cssWidth(Pixels(4)); Text("i2.5 b") }
                Row { Text("i2.6 a"); Box().cssWidth(Pixels(4)); Text("i2.6 b") }
                Row { Text("i2.7 a"); Box().cssWidth(Pixels(4)); Text("i2.7 b") }
                Row { Text("i2.8 a"); Box().cssWidth(Pixels(4)); Text("i2.8 b") }
                Row { Text("i2.9 a"); Box().cssWidth(Pixels(4)); Text("i2.9 b") }
                Row { Text("i2.10 a"); Box().cssWidth(Pixels(4)); Text("i2.10 b") }
                Row { Text("i2.11 a"); Box().cssWidth(Pixels(4)); Text("i2.11 b") }
            }
        case .p3:
            Column {
                Row { Text("i3.0 a"); Box().cssWidth(Pixels(4)); Text("i3.0 b") }
                Row { Text("i3.1 a"); Box().cssWidth(Pixels(4)); Text("i3.1 b") }
                Row { Text("i3.2 a"); Box().cssWidth(Pixels(4)); Text("i3.2 b") }
                Row { Text("i3.3 a"); Box().cssWidth(Pixels(4)); Text("i3.3 b") }
                Row { Text("i3.4 a"); Box().cssWidth(Pixels(4)); Text("i3.4 b") }
                Row { Text("i3.5 a"); Box().cssWidth(Pixels(4)); Text("i3.5 b") }
                Row { Text("i3.6 a"); Box().cssWidth(Pixels(4)); Text("i3.6 b") }
                Row { Text("i3.7 a"); Box().cssWidth(Pixels(4)); Text("i3.7 b") }
                Row { Text("i3.8 a"); Box().cssWidth(Pixels(4)); Text("i3.8 b") }
                Row { Text("i3.9 a"); Box().cssWidth(Pixels(4)); Text("i3.9 b") }
                Row { Text("i3.10 a"); Box().cssWidth(Pixels(4)); Text("i3.10 b") }
                Row { Text("i3.11 a"); Box().cssWidth(Pixels(4)); Text("i3.11 b") }
            }
        case .p4:
            Column {
                Row { Text("i4.0 a"); Box().cssWidth(Pixels(4)); Text("i4.0 b") }
                Row { Text("i4.1 a"); Box().cssWidth(Pixels(4)); Text("i4.1 b") }
                Row { Text("i4.2 a"); Box().cssWidth(Pixels(4)); Text("i4.2 b") }
                Row { Text("i4.3 a"); Box().cssWidth(Pixels(4)); Text("i4.3 b") }
                Row { Text("i4.4 a"); Box().cssWidth(Pixels(4)); Text("i4.4 b") }
                Row { Text("i4.5 a"); Box().cssWidth(Pixels(4)); Text("i4.5 b") }
                Row { Text("i4.6 a"); Box().cssWidth(Pixels(4)); Text("i4.6 b") }
                Row { Text("i4.7 a"); Box().cssWidth(Pixels(4)); Text("i4.7 b") }
                Row { Text("i4.8 a"); Box().cssWidth(Pixels(4)); Text("i4.8 b") }
                Row { Text("i4.9 a"); Box().cssWidth(Pixels(4)); Text("i4.9 b") }
                Row { Text("i4.10 a"); Box().cssWidth(Pixels(4)); Text("i4.10 b") }
                Row { Text("i4.11 a"); Box().cssWidth(Pixels(4)); Text("i4.11 b") }
            }
        case .p5:
            Column {
                Row { Text("i5.0 a"); Box().cssWidth(Pixels(4)); Text("i5.0 b") }
                Row { Text("i5.1 a"); Box().cssWidth(Pixels(4)); Text("i5.1 b") }
                Row { Text("i5.2 a"); Box().cssWidth(Pixels(4)); Text("i5.2 b") }
                Row { Text("i5.3 a"); Box().cssWidth(Pixels(4)); Text("i5.3 b") }
                Row { Text("i5.4 a"); Box().cssWidth(Pixels(4)); Text("i5.4 b") }
                Row { Text("i5.5 a"); Box().cssWidth(Pixels(4)); Text("i5.5 b") }
                Row { Text("i5.6 a"); Box().cssWidth(Pixels(4)); Text("i5.6 b") }
                Row { Text("i5.7 a"); Box().cssWidth(Pixels(4)); Text("i5.7 b") }
                Row { Text("i5.8 a"); Box().cssWidth(Pixels(4)); Text("i5.8 b") }
                Row { Text("i5.9 a"); Box().cssWidth(Pixels(4)); Text("i5.9 b") }
                Row { Text("i5.10 a"); Box().cssWidth(Pixels(4)); Text("i5.10 b") }
                Row { Text("i5.11 a"); Box().cssWidth(Pixels(4)); Text("i5.11 b") }
            }
        case .p6:
            Column {
                Row { Text("i6.0 a"); Box().cssWidth(Pixels(4)); Text("i6.0 b") }
                Row { Text("i6.1 a"); Box().cssWidth(Pixels(4)); Text("i6.1 b") }
                Row { Text("i6.2 a"); Box().cssWidth(Pixels(4)); Text("i6.2 b") }
                Row { Text("i6.3 a"); Box().cssWidth(Pixels(4)); Text("i6.3 b") }
                Row { Text("i6.4 a"); Box().cssWidth(Pixels(4)); Text("i6.4 b") }
                Row { Text("i6.5 a"); Box().cssWidth(Pixels(4)); Text("i6.5 b") }
                Row { Text("i6.6 a"); Box().cssWidth(Pixels(4)); Text("i6.6 b") }
                Row { Text("i6.7 a"); Box().cssWidth(Pixels(4)); Text("i6.7 b") }
                Row { Text("i6.8 a"); Box().cssWidth(Pixels(4)); Text("i6.8 b") }
                Row { Text("i6.9 a"); Box().cssWidth(Pixels(4)); Text("i6.9 b") }
                Row { Text("i6.10 a"); Box().cssWidth(Pixels(4)); Text("i6.10 b") }
                Row { Text("i6.11 a"); Box().cssWidth(Pixels(4)); Text("i6.11 b") }
            }
        case .p7:
            Column {
                Row { Text("i7.0 a"); Box().cssWidth(Pixels(4)); Text("i7.0 b") }
                Row { Text("i7.1 a"); Box().cssWidth(Pixels(4)); Text("i7.1 b") }
                Row { Text("i7.2 a"); Box().cssWidth(Pixels(4)); Text("i7.2 b") }
                Row { Text("i7.3 a"); Box().cssWidth(Pixels(4)); Text("i7.3 b") }
                Row { Text("i7.4 a"); Box().cssWidth(Pixels(4)); Text("i7.4 b") }
                Row { Text("i7.5 a"); Box().cssWidth(Pixels(4)); Text("i7.5 b") }
                Row { Text("i7.6 a"); Box().cssWidth(Pixels(4)); Text("i7.6 b") }
                Row { Text("i7.7 a"); Box().cssWidth(Pixels(4)); Text("i7.7 b") }
                Row { Text("i7.8 a"); Box().cssWidth(Pixels(4)); Text("i7.8 b") }
                Row { Text("i7.9 a"); Box().cssWidth(Pixels(4)); Text("i7.9 b") }
                Row { Text("i7.10 a"); Box().cssWidth(Pixels(4)); Text("i7.10 b") }
                Row { Text("i7.11 a"); Box().cssWidth(Pixels(4)); Text("i7.11 b") }
            }
        case .p8:
            Column {
                Row { Text("i8.0 a"); Box().cssWidth(Pixels(4)); Text("i8.0 b") }
                Row { Text("i8.1 a"); Box().cssWidth(Pixels(4)); Text("i8.1 b") }
                Row { Text("i8.2 a"); Box().cssWidth(Pixels(4)); Text("i8.2 b") }
                Row { Text("i8.3 a"); Box().cssWidth(Pixels(4)); Text("i8.3 b") }
                Row { Text("i8.4 a"); Box().cssWidth(Pixels(4)); Text("i8.4 b") }
                Row { Text("i8.5 a"); Box().cssWidth(Pixels(4)); Text("i8.5 b") }
                Row { Text("i8.6 a"); Box().cssWidth(Pixels(4)); Text("i8.6 b") }
                Row { Text("i8.7 a"); Box().cssWidth(Pixels(4)); Text("i8.7 b") }
                Row { Text("i8.8 a"); Box().cssWidth(Pixels(4)); Text("i8.8 b") }
                Row { Text("i8.9 a"); Box().cssWidth(Pixels(4)); Text("i8.9 b") }
                Row { Text("i8.10 a"); Box().cssWidth(Pixels(4)); Text("i8.10 b") }
                Row { Text("i8.11 a"); Box().cssWidth(Pixels(4)); Text("i8.11 b") }
            }
        case .p9:
            Column {
                Row { Text("i9.0 a"); Box().cssWidth(Pixels(4)); Text("i9.0 b") }
                Row { Text("i9.1 a"); Box().cssWidth(Pixels(4)); Text("i9.1 b") }
                Row { Text("i9.2 a"); Box().cssWidth(Pixels(4)); Text("i9.2 b") }
                Row { Text("i9.3 a"); Box().cssWidth(Pixels(4)); Text("i9.3 b") }
                Row { Text("i9.4 a"); Box().cssWidth(Pixels(4)); Text("i9.4 b") }
                Row { Text("i9.5 a"); Box().cssWidth(Pixels(4)); Text("i9.5 b") }
                Row { Text("i9.6 a"); Box().cssWidth(Pixels(4)); Text("i9.6 b") }
                Row { Text("i9.7 a"); Box().cssWidth(Pixels(4)); Text("i9.7 b") }
                Row { Text("i9.8 a"); Box().cssWidth(Pixels(4)); Text("i9.8 b") }
                Row { Text("i9.9 a"); Box().cssWidth(Pixels(4)); Text("i9.9 b") }
                Row { Text("i9.10 a"); Box().cssWidth(Pixels(4)); Text("i9.10 b") }
                Row { Text("i9.11 a"); Box().cssWidth(Pixels(4)); Text("i9.11 b") }
            }
        case .p10:
            Column {
                Row { Text("i10.0 a"); Box().cssWidth(Pixels(4)); Text("i10.0 b") }
                Row { Text("i10.1 a"); Box().cssWidth(Pixels(4)); Text("i10.1 b") }
                Row { Text("i10.2 a"); Box().cssWidth(Pixels(4)); Text("i10.2 b") }
                Row { Text("i10.3 a"); Box().cssWidth(Pixels(4)); Text("i10.3 b") }
                Row { Text("i10.4 a"); Box().cssWidth(Pixels(4)); Text("i10.4 b") }
                Row { Text("i10.5 a"); Box().cssWidth(Pixels(4)); Text("i10.5 b") }
                Row { Text("i10.6 a"); Box().cssWidth(Pixels(4)); Text("i10.6 b") }
                Row { Text("i10.7 a"); Box().cssWidth(Pixels(4)); Text("i10.7 b") }
                Row { Text("i10.8 a"); Box().cssWidth(Pixels(4)); Text("i10.8 b") }
                Row { Text("i10.9 a"); Box().cssWidth(Pixels(4)); Text("i10.9 b") }
                Row { Text("i10.10 a"); Box().cssWidth(Pixels(4)); Text("i10.10 b") }
                Row { Text("i10.11 a"); Box().cssWidth(Pixels(4)); Text("i10.11 b") }
            }
        default:
            Column {
                Row { Text("i11.0 a"); Box().cssWidth(Pixels(4)); Text("i11.0 b") }
                Row { Text("i11.1 a"); Box().cssWidth(Pixels(4)); Text("i11.1 b") }
                Row { Text("i11.2 a"); Box().cssWidth(Pixels(4)); Text("i11.2 b") }
                Row { Text("i11.3 a"); Box().cssWidth(Pixels(4)); Text("i11.3 b") }
                Row { Text("i11.4 a"); Box().cssWidth(Pixels(4)); Text("i11.4 b") }
                Row { Text("i11.5 a"); Box().cssWidth(Pixels(4)); Text("i11.5 b") }
                Row { Text("i11.6 a"); Box().cssWidth(Pixels(4)); Text("i11.6 b") }
                Row { Text("i11.7 a"); Box().cssWidth(Pixels(4)); Text("i11.7 b") }
                Row { Text("i11.8 a"); Box().cssWidth(Pixels(4)); Text("i11.8 b") }
                Row { Text("i11.9 a"); Box().cssWidth(Pixels(4)); Text("i11.9 b") }
                Row { Text("i11.10 a"); Box().cssWidth(Pixels(4)); Text("i11.10 b") }
                Row { Text("i11.11 a"); Box().cssWidth(Pixels(4)); Text("i11.11 b") }
            }
        }
    }
}

