// SwiftUI probe: 3D render effects (R3-10 item 6; rulings PJ-*, record 193,
// docs/superpowers/2026-11-02-projection-effects-decisions.md).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-projection-effects.swift -o /tmp/pj-probe
//   /tmp/pj-probe 2>&1 | grep -v 'Connection\]'
//
// INSTRUMENT: `ImageRenderer` at scale 1 onto an opaque white 480x400 canvas, the subject at (140, 150);
// ink boxes are reported relative to the subject's origin. The ink of a red view is `any non-white pixel`.
// The row height at a column is the count of ink pixels in it.
// POSITIVE CONTROL (P1): an untransformed red 200x100 reads x0 y0 w200 h100. SEPARATING ARMS: perspective 0
// vs 1 (the far edge shrinks only with a perspective), a 100x200 view (d = max(W,H)/perspective, not min),
// angle 0 with anchorZ 50 (identity) against 0.001 degrees (the model's scale).
//
// RECORDED 2026-11-02, macOS 27.2 (Apple Swift 6.4.2), compiled, run twice, stdout byte-identical:
//
//   --- P: control
//   P1 untransformed 200x100: x0 y0 w200 h100 | h@left+2 100 h@right-2 100
//   --- R: rotation3DEffect (perspective model d = max(W,H)/perspective)
//   R1 45deg y p1: x-9 y-27 w161 h154 | h@left+2 154 h@right-2 76
//   R1 100x200 45deg y p1: x7 y-21 w73 h242 | h@left+2 242 h@right-2 174
//   R2 45deg y p2: x-140 y-121 w281 h342 | h@left+2 342 h@right-2 62
//   R2 45deg y p0: x29 y-1 w142 h102 | h@left+2 100 h@right-2 100
//   R2 -45deg y p1: x48 y-27 w161 h154 | h@left+2 76 h@right-2 154
//   R2 45deg y p-1: x48 y-27 w161 h154 | h@left+2 76 h@right-2 154
//   R3 45deg x p1: x-21 y20 w242 h73 | h@left+2 8 h@right-2 8
//   R4 z 30 vs rotationEffect: x-12 y-44 w224 h188 | h@left+2 6 h@right-2 6 | x-12 y-44 w224 h188 | h@left+2 6 h@right-2 6
//   R5 axis (0,2,0): x-9 y-27 w161 h154 | h@left+2 154 h@right-2 76
//   R5 zero axis: x0 y0 w200 h100 | h@left+2 100 h@right-2 100
//   R6 anchorZ 50 at 0deg: x0 y0 w200 h100 | h@left+2 100 h@right-2 100
//   R6 anchorZ 50 at 0.001deg: x20 y10 w160 h80 | h@left+2 80 h@right-2 80
//   R7 anchor leading 45deg: x0 y0 w83 h100 | h@left+2 100 h@right-2 60
//   R8 90deg: none
//   R8 60deg p2.5: none
//   R8 60deg p2.2: x-140 y-150 w266 h400 | h@left+2 400 h@right-2 56
//   R9 two 30deg: x-41 y-44 w192 h188 | h@left+2 188 h@right-2 70
//   R9 one 60deg: x12 y-38 w123 h176 | h@left+2 176 h@right-2 72
//   --- J: projectionEffect (row vectors, m11..m33)
//   J1 m13 0.002: x0 y0 w143 h100 | h@left+2 100 h@right-2 72
//   J2 m33 2: x0 y0 w100 h50 | h@left+2 50 h@right-2 50
//   J3 m31 30: x30 y0 w200 h100 | h@left+2 100 h@right-2 100
//   J4 m13 -0.01 (a corner behind the eye): none
//   --- T: transformEffect (CoreGraphics order, view-local)
//   T1 shear b .2 tx 10: x9 y-1 w202 h142 | h@left+2 101 h@right-2 101
//   T2 rotated 30 then tx 20: x-33 y10 w224 h187 | h@left+2 6 h@right-2 7
//   --- C: clipping
//   C1 clipped after: x0 y0 w152 h100 | h@left+2 100 h@right-2 76
//   --- L: layout
//   L1 sibling x: x-9 y-27 w259 h154 | h@left+2 154 h@right-2 100
//   --- B: back face
//   B1 180deg: x0 y0 w200 h100 | h@left+2 100 h@right-2 100
//
// Read: perspective model d = max(W,H)/perspective (R1: near edge x-9 and 154 tall, far edge 76 tall; 100x200 gives d=200
// again); R2 p2 halves d (the box grows past the 480x400 canvas, so only the edge heights read); p0 is orthographic;
// a negative perspective negates the angle; z-axis equals rotationEffect (R4); R6: angle 0 is identity with anchorZ 50 and
// 0.001 degrees is not; R8: a view with any corner behind the eye draws nothing; R9: nested effects compose as maps;
// J: row vectors with the w column (m13, m33, m31); L1: layout unaffected (the sibling stays at x200); B1: no back-face culling.
import SwiftUI
import AppKit

@MainActor
func ink<V: View>(_ v: V, w: Int = 200, h: Int = 100) -> String {
    let canvas = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().offset(x: 140, y: 150)
    }.frame(width: 480, height: 400)
    let r = ImageRenderer(content: canvas)
    r.scale = 1
    guard let cg = r.cgImage else { return "no image" }
    let rep = NSBitmapImageRep(cgImage: cg)
    var minX = 9999, minY = 9999, maxX = -1, maxY = -1
    var colHeights: [Int: Int] = [:]
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let white = c.redComponent > 0.97 && c.greenComponent > 0.97 && c.blueComponent > 0.97
            if !white {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                colHeights[x, default: 0] += 1
            }
        }
    }
    if maxX < 0 { return "none" }
    let left = colHeights[minX + 2] ?? 0, right = colHeights[maxX - 2] ?? 0
    return "x\(minX - 140) y\(minY - 150) w\(maxX - minX + 1) h\(maxY - minY + 1) | h@left+2 \(left) h@right-2 \(right)"
}

struct Box: View {
    var body: some View { Color.red.frame(width: 200, height: 100) }
}
struct Tall: View {
    var body: some View { Color.red.frame(width: 100, height: 200) }
}

@MainActor
func run() {
    print("--- P: control")
    print("P1 untransformed 200x100:", ink(Box()))
    print("--- R: rotation3DEffect (perspective model d = max(W,H)/perspective)")
    print("R1 45deg y p1:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0))))
    print("R1 100x200 45deg y p1:", ink(Tall().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0))))
    print("R2 45deg y p2:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0), perspective: 2)))
    print("R2 45deg y p0:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0), perspective: 0)))
    print("R2 -45deg y p1:", ink(Box().rotation3DEffect(.degrees(-45), axis: (x: 0, y: 1, z: 0))))
    print("R2 45deg y p-1:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0), perspective: -1)))
    print("R3 45deg x p1:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 1, y: 0, z: 0))))
    print("R4 z 30 vs rotationEffect:", ink(Box().rotation3DEffect(.degrees(30), axis: (x: 0, y: 0, z: 1))),
          "|", ink(Box().rotationEffect(.degrees(30))))
    print("R5 axis (0,2,0):", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 2, z: 0))))
    print("R5 zero axis:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 0, z: 0))))
    print("R6 anchorZ 50 at 0deg:", ink(Box().rotation3DEffect(.degrees(0), axis: (x: 0, y: 1, z: 0), anchorZ: 50)))
    print("R6 anchorZ 50 at 0.001deg:", ink(Box().rotation3DEffect(.degrees(0.001), axis: (x: 0, y: 1, z: 0), anchorZ: 50)))
    print("R7 anchor leading 45deg:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0), anchor: .leading)))
    print("R8 90deg:", ink(Box().rotation3DEffect(.degrees(90), axis: (x: 0, y: 1, z: 0))))
    print("R8 60deg p2.5:", ink(Box().rotation3DEffect(.degrees(60), axis: (x: 0, y: 1, z: 0), perspective: 2.5)))
    print("R8 60deg p2.2:", ink(Box().rotation3DEffect(.degrees(60), axis: (x: 0, y: 1, z: 0), perspective: 2.2)))
    print("R9 two 30deg:", ink(Box().rotation3DEffect(.degrees(30), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(30), axis: (x: 0, y: 1, z: 0))))
    print("R9 one 60deg:", ink(Box().rotation3DEffect(.degrees(60), axis: (x: 0, y: 1, z: 0))))
    print("--- J: projectionEffect (row vectors, m11..m33)")
    var m = ProjectionTransform()
    m.m13 = 0.002
    print("J1 m13 0.002:", ink(Box().projectionEffect(m)))
    var s = ProjectionTransform(); s.m33 = 2
    print("J2 m33 2:", ink(Box().projectionEffect(s)))
    var t = ProjectionTransform(); t.m31 = 30
    print("J3 m31 30:", ink(Box().projectionEffect(t)))
    var b = ProjectionTransform(); b.m13 = -0.01
    print("J4 m13 -0.01 (a corner behind the eye):", ink(Box().projectionEffect(b)))
    print("--- T: transformEffect (CoreGraphics order, view-local)")
    print("T1 shear b .2 tx 10:", ink(Box().transformEffect(CGAffineTransform(a: 1, b: 0.2, c: 0, d: 1, tx: 10, ty: 0))))
    print("T2 rotated 30 then tx 20:", ink(Box().transformEffect(CGAffineTransform(rotationAngle: .pi / 6).translatedBy(x: 20, y: 0))))
    print("--- C: clipping")
    print("C1 clipped after:", ink(Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0)).clipped()))
    print("--- L: layout")
    print("L1 sibling x:", ink(HStack(spacing: 0) {
        Box().rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0))
        Color.blue.frame(width: 50, height: 100)
    }))
    print("--- B: back face")
    print("B1 180deg:", ink(Box().rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))))
}

MainActor.assumeIsolated { run() }
