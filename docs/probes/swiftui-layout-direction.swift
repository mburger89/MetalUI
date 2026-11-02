// SwiftUI probe: right-to-left `layoutDirection` mirrors layout, for R3-10 item 4
// (ruling prefix LD-, docs/superpowers/2026-11-01-layout-direction-decisions.md).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-layout-direction.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on SwiftUI symbols.
//
// METHOD. Every arm runs twice, LTR and RTL (LTR is the separating arm: a figure that does not move
// between the two is not mirrored). The arm is wrapped as
//   arm.frame(width: 100, height: 40, alignment: .topLeading).environment(\.layoutDirection, dir)
//   .coordinateSpace(name: "root")
// hosted in an NSHostingView in a window. Layout arms: each leaf `L(id, width)` is a 10-high clear
// view whose background GeometryReader reports `frame(in: .named("root")).minX` through a preference;
// the figures printed are those minX values (physical, left edge 0, right edge 100). Ink arms
// (`ink…`): the view is drawn by `ImageRenderer` at scale 1 into 100x40 and the printed range is the
// opaque (alpha > 100) column range `minX...maxX`, or `none`.
//
// RECORDED 2026-11-01 (R3-10 item 4) on macOS 27.2, Apple Swift 6.4, run twice, byte-identical stdout; the whole stdout is the block at the foot of this file.
//
// THE READING (each line names the arm; the figures are in the block below).
// 1. HStack reverses: A1 a10,b20 spacing 0 -> LTR 0/10, RTL 90/70; A2 spacing 5 -> 0/15 and 90/65.
// 2. frame(maxWidth: .infinity, alignment:) mirrors its alignment: B1 .leading 0 -> 90, B2 .trailing
//    90 -> 0, B3 .center unchanged.
// 3. ZStack(alignment: .leading) C1, overlay/background(alignment: .leading) D1/D2: the aligned child
//    moves to the right, the base does not.
// 4. padding(.leading) is the right-hand pad: E1 child 10 -> 80, E2 .trailing child 0 -> 90.
// 5. offset(x:) written INSIDE the environment writer flips its sign (F1 10 -> 80: the child sits at 90
//    and moves -10); written OUTSIDE it, it does not (F2 LTR 10, RTL 100 = 90 + 10).
// 6. position(x:) is measured from the right edge (G1 15 -> 75).
// 7. VStack(alignment: .leading), Grid, a custom Layout packing from the left, all mirror (H1, J1, I1).
// 8. A nested left-to-right container inside a right-to-left one keeps its own order inside its
//    mirrored box: the PARENT's direction decides where the box goes (K1).
// 9. A horizontal ScrollView opens at the leading (right) edge (L1: the first child at 90 in a 300
//    wide content, so the content's minX is -200).
// 10. Text glyphs are not mirrored; multilineTextAlignment .leading aligns right under RTL, .trailing
//    left, .center unchanged (M1, M2, M3: the first, short line's ink within the box).
// 11. Image is not mirrored; flipsForRightToLeftLayoutDirection(true) mirrors it (N1, N2).
// 12. Path/Shape fills ARE mirrored (O1); Canvas is NOT (O2) - MetalUI defers the shape half
//     (divergence 1045).
// 13. scaleEffect(anchor: .leading) mirrors its anchor (P1); rotationEffect mirrors the anchor AND the
//    sense (P2: the rows swap sides).

import SwiftUI
import AppKit

struct Rects: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct L: View {
    let id: String
    let width: CGFloat
    init(_ id: String, _ width: CGFloat = 10) { self.id = id; self.width = width }
    var body: some View {
        Color.clear.frame(width: width, height: 10)
            .background(GeometryReader { g in
                Color.clear.preference(key: Rects.self, value: [id: g.frame(in: .named("root"))])
            })
    }
}

struct LeftPacked: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 100, height: proposal.height ?? 40)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
            x += size.width
        }
    }
}

@MainActor
func layoutArm<V: View>(_ name: String, _ dir: LayoutDirection, @ViewBuilder _ arm: () -> V) {
    var seen: [String: CGRect] = [:]
    let root = arm()
        .frame(width: 100, height: 40, alignment: .topLeading)
        .environment(\.layoutDirection, dir)
        .coordinateSpace(name: "root")
        .onPreferenceChange(Rects.self) { seen = $0 }
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    for _ in 0..<6 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
    let figures = seen.keys.sorted().map { "\($0)=\(Int(seen[$0]!.minX.rounded()))" }.joined(separator: " ")
    print("\(name) \(dir == .leftToRight ? "LTR" : "RTL") \(figures)")
    window.orderOut(nil)
}

@MainActor
func inkArm<V: View>(_ name: String, _ dir: LayoutDirection, topRows: Int = 40, @ViewBuilder _ arm: () -> V) {
    let content = arm()
        .frame(width: 100, height: 40, alignment: .topLeading)
        .environment(\.layoutDirection, dir)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    var text = "none"
    if let cg = renderer.cgImage {
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lo = Int.max, hi = -1, rowLo = Int.max, rowHi = -1
        for y in 0..<min(h, topRows) {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 100 {
                lo = min(lo, x); hi = max(hi, x); rowLo = min(rowLo, y); rowHi = max(rowHi, y)
            }
        }
        if hi >= 0 { text = "cols \(lo)...\(hi) rows \(rowLo)...\(rowHi)" }
    }
    print("\(name) \(dir == .leftToRight ? "LTR" : "RTL") ink \(text)")
}

@MainActor
func run() {
    _ = NSApplication.shared
    for dir in [LayoutDirection.leftToRight, .rightToLeft] {
        layoutArm("A1 HStack spacing 0", dir) { HStack(spacing: 0) { L("a"); L("b", 20) } }
        layoutArm("A2 HStack spacing 5", dir) { HStack(spacing: 5) { L("a"); L("b", 20) } }
        layoutArm("B1 frame leading", dir) { L("a").frame(maxWidth: .infinity, alignment: .leading) }
        layoutArm("B2 frame trailing", dir) { L("a").frame(maxWidth: .infinity, alignment: .trailing) }
        layoutArm("B3 frame center", dir) { L("a").frame(maxWidth: .infinity, alignment: .center) }
        layoutArm("C1 ZStack leading", dir) { ZStack(alignment: .leading) { L("a", 30); L("b") } }
        layoutArm("D1 overlay leading", dir) {
            Color.clear.frame(width: 100, height: 40).overlay(alignment: .leading) { L("a") }
        }
        layoutArm("D2 background leading", dir) {
            Color.clear.frame(width: 100, height: 40).background(alignment: .leading) { L("a") }
        }
        layoutArm("E1 padding leading", dir) {
            L("a").padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
        }
        layoutArm("E2 padding trailing", dir) {
            L("a").padding(.trailing, 10).frame(maxWidth: .infinity, alignment: .leading)
        }
        layoutArm("F1 offset inside writer", dir) {
            L("a").offset(x: 10).frame(maxWidth: .infinity, alignment: .leading)
        }
        layoutArm("G1 position", dir) { L("a").position(x: 20, y: 10) }
        layoutArm("H1 VStack leading", dir) {
            VStack(alignment: .leading, spacing: 0) { L("a"); L("b", 30) }
        }
        layoutArm("I1 custom Layout left-packed", dir) { LeftPacked { L("a"); L("b", 20) } }
        layoutArm("J1 Grid", dir) { Grid(horizontalSpacing: 0) { GridRow { L("a"); L("b", 20) } } }
        layoutArm("K1 nested LTR in RTL", dir) {
            HStack(spacing: 0) {
                L("na")
                HStack(spacing: 0) { L("ia"); L("ib", 20) }.environment(\.layoutDirection, .leftToRight)
                L("nb")
            }
        }
        layoutArm("L1 horizontal ScrollView", dir) {
            ScrollView(.horizontal) { HStack(spacing: 0) { L("a"); Color.clear.frame(width: 290, height: 10) } }
        }
    }
    // F2: the offset written OUTSIDE the writer (the writer wraps the frame, the offset wraps the writer).
    for dir in [LayoutDirection.leftToRight, .rightToLeft] {
        var seen: [String: CGRect] = [:]
        let root = L("a").frame(maxWidth: .infinity, alignment: .leading)
            .frame(width: 100, height: 40, alignment: .topLeading)
            .environment(\.layoutDirection, dir)
            .offset(x: 10)
            .coordinateSpace(name: "root")
            .onPreferenceChange(Rects.self) { seen = $0 }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        for _ in 0..<6 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
        print("F2 offset outside writer \(dir == .leftToRight ? "LTR" : "RTL") a=\(Int((seen["a"]?.minX ?? -1).rounded()))")
        window.orderOut(nil)
    }

    let asymmetric = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { rect in
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 30).fill()
        return true
    }
    for dir in [LayoutDirection.leftToRight, .rightToLeft] {
        inkArm("M1 Text two lines .leading (first line)", dir, topRows: 14) {
            Text("Hi\nthere xxx").font(.system(size: 12)).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        inkArm("M2 Text two lines .trailing (first line)", dir, topRows: 14) {
            Text("Hi\nthere xxx").font(.system(size: 12)).multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        inkArm("N1 Image asymmetric", dir) {
            Image(nsImage: asymmetric).frame(maxWidth: .infinity, alignment: .leading)
        }
        inkArm("N2 Image flipsForRightToLeftLayoutDirection", dir) {
            Image(nsImage: asymmetric).flipsForRightToLeftLayoutDirection(true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        inkArm("O1 Path shape fill", dir) {
            Path { $0.addRect(CGRect(x: 0, y: 0, width: 30, height: 40)) }.fill(Color.black)
        }
        inkArm("O2 Canvas fill", dir) {
            Canvas { context, _ in context.fill(Path(CGRect(x: 0, y: 0, width: 30, height: 40)), with: .color(.black)) }
        }
        inkArm("P1 scaleEffect anchor leading", dir) {
            Rectangle().fill(Color.black).frame(width: 20, height: 10)
                .scaleEffect(2, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        inkArm("P2 rotationEffect 30 anchor leading", dir) {
            Rectangle().fill(Color.black).frame(width: 30, height: 4)
                .rotationEffect(.degrees(30), anchor: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        inkArm("M3 Text two lines .center (first line)", dir, topRows: 14) {
            Text("Hi\nthere xxx").font(.system(size: 12)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

MainActor.assumeIsolated { run() }

// WHOLE STDOUT (2026-11-01, macOS 27.2, Apple Swift 6.4, `/usr/bin/swift`, run twice, byte-identical, 54 lines):
//
// A1 HStack spacing 0 LTR a=0 b=10
// A2 HStack spacing 5 LTR a=0 b=15
// B1 frame leading LTR a=0
// B2 frame trailing LTR a=90
// B3 frame center LTR a=45
// C1 ZStack leading LTR a=0 b=0
// D1 overlay leading LTR a=0
// D2 background leading LTR a=0
// E1 padding leading LTR a=10
// E2 padding trailing LTR a=0
// F1 offset inside writer LTR a=10
// G1 position LTR a=15
// H1 VStack leading LTR a=0 b=0
// I1 custom Layout left-packed LTR a=0 b=10
// J1 Grid LTR a=0 b=10
// K1 nested LTR in RTL LTR ia=10 ib=20 na=0 nb=40
// L1 horizontal ScrollView LTR a=0
// A1 HStack spacing 0 RTL a=90 b=70
// A2 HStack spacing 5 RTL a=90 b=65
// B1 frame leading RTL a=90
// B2 frame trailing RTL a=0
// B3 frame center RTL a=45
// C1 ZStack leading RTL a=70 b=90
// D1 overlay leading RTL a=90
// D2 background leading RTL a=90
// E1 padding leading RTL a=80
// E2 padding trailing RTL a=90
// F1 offset inside writer RTL a=80
// G1 position RTL a=75
// H1 VStack leading RTL a=90 b=70
// I1 custom Layout left-packed RTL a=90 b=70
// J1 Grid RTL a=90 b=70
// K1 nested LTR in RTL RTL ia=60 ib=70 na=90 nb=50
// L1 horizontal ScrollView RTL a=90
// F2 offset outside writer LTR a=10
// F2 offset outside writer RTL a=100
// M1 Text two lines .leading (first line) LTR ink cols 1...10 rows 3...11
// M2 Text two lines .trailing (first line) LTR ink cols 41...50 rows 3...11
// N1 Image asymmetric LTR ink cols 0...9 rows 0...29
// N2 Image flipsForRightToLeftLayoutDirection LTR ink cols 0...9 rows 0...29
// O1 Path shape fill LTR ink cols 0...29 rows 0...39
// O2 Canvas fill LTR ink cols 0...29 rows 0...39
// P1 scaleEffect anchor leading LTR ink cols 0...39 rows 0...14
// P2 rotationEffect 30 anchor leading LTR ink cols 0...26 rows 18...36
// M3 Text two lines .center (first line) LTR ink cols 21...30 rows 3...11
// M1 Text two lines .leading (first line) RTL ink cols 89...98 rows 3...11
// M2 Text two lines .trailing (first line) RTL ink cols 49...58 rows 3...11
// N1 Image asymmetric RTL ink cols 70...79 rows 0...29
// N2 Image flipsForRightToLeftLayoutDirection RTL ink cols 90...99 rows 0...29
// O1 Path shape fill RTL ink cols 70...99 rows 0...39
// O2 Canvas fill RTL ink cols 0...29 rows 0...39
// P1 scaleEffect anchor leading RTL ink cols 60...99 rows 0...14
// P2 rotationEffect 30 anchor leading RTL ink cols 73...99 rows 18...36
// M3 Text two lines .center (first line) RTL ink cols 69...78 rows 3...11
