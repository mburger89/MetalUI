// SwiftUI probe: path operations (round-3 item R3-8, rulings PG-A onward in
// docs/superpowers/2026-10-31-path-ops-decisions.md).
//
// HOW TO RUN (compiled; no window, no screen needed):
//
//   xcrun swiftc docs/probes/swiftui-path-ops.swift -o /tmp/pg-probe && /tmp/pg-probe
//
// INSTRUMENT: `Path.forEach` dumps a path's elements; `currentPoint` and
// `boundingRect` read its end and extent; `contains` samples the interior.
// POSITIVE CONTROLS (group C): a 3-4-5 line and a unit-square perimeter have
// known lengths, so a trim by a known fraction must land on a known point.
// SEPARATING ARMS: TR2 (per-element vs arc length) trims a path whose two
// segments differ 10x in length; TR3 (curve) a quarter circle whose
// parameter midpoint differs from its arc-length midpoint.
//
// RECORDED 2026-10-31 by the path-ops item (R3-8), macOS 27.2, Apple Swift 6.4
// (Xcode 27), compiled form, run twice, stdout byte-identical (81 lines), exit 0.
// `Path.boundingRect` in group SP is not tight at a miter tip (arm SP V reads
// the elements instead). Groups X and Y are the extra arms.
//
//   --- C: positive controls
//   C1 3-4-5 line trim(0,0.5): M(0,0) L(1.5,2) (expect L(1.5,2))
//   C2 square trim(0,0.25): M(0,0) L(10,0) (expect M(0,0) L(10,0))
//   --- TR: trimmedPath
//   TR2 L10 then L90, trim(0,0.5): M(0,0) L(10,0) L(10,40) (arc length: ends (10,40); per element: (10,45) or (5,..))
//   TR3 quarter circle r100 trim(0,0.5) end: (70.711,70.711) (arc length: (70.711,70.711))
//   TR3b quarter circle trim(0.25,0.75) bounds: x38.303 y38.303 w54.099 h54.099
//   TR4 two subpaths 10 and 90: 
//      trim(0,0.5): M(0,0) L(10,0) M(0,5) L(40,5) (whole-path: M(0,0) L(10,0) M(0,5) L(40,5); per-subpath: halves)
//      trim(0.05,0.15): M(5,0) L(10,0) M(0,5) L(5,5)
//   TR5 square trim(0.9,1): M(0,4) L(0,0)
//   TR5b square trim(0,1): M(0,0) L(10,0) L(10,10) L(0,10) Z
//   TR5c square trim(0.75,0.25) (from > to): 
//   TR5d square trim(0.5,0.5): ''
//   TR5e square trim(-0.5,0.25): M(0,0) L(10,0)
//   TR5f square trim(0,1.5): M(0,0) L(10,0) L(10,10) L(0,10) Z
//   TR5g square trim(0.25,0.5) (interior): M(10,0) L(10,10)
//   TR6 open path trim(0,1): M(0,0) L(10,0) L(10,10)
//   TR6b closed (explicit) trim(0.9,1): M(2.414,2.414) L(0,0) (closing edge length 14.142 counted?)
//   TR6c closed trim(0,1): M(0,0) L(10,0) L(10,10) Z
//   TR7 empty path trim: ''
//   --- TS: Shape.trim start points (the first element of path(in:) and of the trimmed path)
//   TS Rectangle: path M(0,0) L(100,0) L(100,60) L(0,60) Z | trim(0,0.25) M(0,0) L(80,0) end (80,0)
//   TS RoundedRectangle(20): path M(100,30) L(100,30) C(98.502,47.37) C(87.37,58.502) C(69.427,60) L(30.573,60) C(12.63,58.502) C(1.498,47.37) C | trim(0,0.25) M(100,30) L(100,30) C(98.502,47.37) C(87.37,58.502) C(69.427,60) L(50,60) end (50,60)
//   TS RoundedRectangle(20,circular): path M(100,30) L(100,40) C(80,60) L(20,60) C(0,40) L(0,20) C(20,0) L(80,0) C(100,20) Z | trim(0,0.25) M(100,30) L(100,40) C(80,60) L(50,60) end (50,60)
//   TS Circle: path M(80,30) C(50,60) C(20,30) C(50,0) C(80,30) Z | trim(0,0.25) M(80,30) C(50,60) end (50,60)
//   TS Ellipse: path M(100,30) C(50,60) C(0,30) C(50,0) C(100,30) Z | trim(0,0.25) M(100,30) C(50,60) end (50,60)
//   TS Capsule: path M(100,30) L(100,30) C(97.753,41.055) C(81.055,57.753) C(54.14,60) L(45.86,60) C(18.945,57.753) C(2.247,41.055) | trim(0,0.25) M(100,30) L(100,30) C(97.753,41.055) C(81.055,57.753) C(54.14,60) L(50,60) end (50,60)
//   TS2 Circle in 100x100 trim(0,0.5): M(100,50) C(50,100) C(0,50) end (0,50)
//   TS2b Circle trim(0,0.25) end: (50,100) bounds x50 y50 w50 h50
//   TS2c Circle trim(0,1) elements: M(100,50) C(50,100) C(0,50) C(50,0) C(100,50) Z
//   TS3 trim size: (20.0, 30.0, 60.0, 30.0)
//   --- SP: strokedPath
//   SP butt: bounds x0 y-2 w10 h4 elements M(0,2) L(10,2) L(10,-2) L(0,-2) L(0,2) Z
//   SP round: bounds x-2 y-2 w14 h4 elements M(0,2) L(10,2) C(12,0) C(10,-2) L(0,-2) C(-2,0) C(0,2) Z
//   SP square: bounds x-2 y-2 w14 h4 elements M(0,2) L(10,2) L(12,2) L(12,-2) L(10,-2) L(0,-2) L(-2,-2) L(-2,2) L(0,2) Z
//   SP ring: bounds x-5 y-5 w110 h110 centre(50,50) false (50,2) true (50,-2) true (50,8) false (50,12) false
//   SP dash [4,4] on 20 line w2: x0 y-1 w20 h2 (0,0) true gap(6,0) false
//   SP w0: 'M(0,0) L(10,0) L(10,0) L(0,0) L(0,0) Z'
//   SP V miter w4 (elements; `box` above is not tight at a miter tip): M(-1.414,1.414) L(8.586,11.414) L(10,12.828) L(11.414,11.414) L(21.414,1.414) L(18.586,-1.414) L(8.586,8.586) L(11.414,8.586) L(1.414,-1.414) L(-1.414,1.414) Z
//   SP V bevel w4 (elements; `box` above is not tight at a miter tip): M(-1.414,1.414) L(8.586,11.414) L(11.414,11.414) L(21.414,1.414) L(18.586,-1.414) L(8.586,8.586) L(11.414,8.586) L(1.414,-1.414) L(-1.414,1.414) Z
//   SP V round w4 (elements; `box` above is not tight at a miter tip): M(-1.414,1.414) L(8.586,11.414) C(11.414,11.414) L(21.414,1.414) L(18.586,-1.414) L(8.586,8.586) L(11.414,8.586) L(1.414,-1.414) L(-1.414,1.414) Z
//   --- AR: arcs and transforms
//   AR1 addRelativeArc 0 +90: end (50,100) bounds x50 y50 w50 h50
//   AR2 addRelativeArc 0 -90: end (50,0) bounds x50 y0 w50 h50
//   AR3 addArc 0..90 clockwise:false end (50,100) bounds x50 y50 w50 h50
//   AR4 addRelativeArc delta 450: end (50,100) bounds x0 y0 w100 h100 elements 55
//   AR5 addRelativeArc with transform: end (60,120) bounds x60 y70 w50 h50
//   AR6 addArc with scale(2,1): end (100,100) bounds x100 y50 w100 h50
//   AR7 applying(rotate 90 then translate): M(5,7) L(5,17) L(-15,17) L(-15,7) Z
//   AR8 offsetBy(3,4): M(3,4) L(13,4) L(13,24) L(3,24) Z
//   AR9 addRect(transform:): M(1,2) L(11,2) L(11,22) L(1,22) Z
//   --- UR: UnevenRoundedRectangle
//   UR1 path: M(100,20) L(100,29.427) C(98.502,47.37) C(87.37,58.502) C(69.427,60) L(15.287,60) C(6.315,59.251) C(0.749,53.685) C(0,45) L(0,45) C(2.247,18.945) C(18.945,2.247) C(45.86,0) L(100,0) C(100,0) C(100,0) C(100,0) Z
//   UR1b bounds x0 y0 w100 h60 contains(1,1) false (99,1) true (1,59) false (99,59) false
//   UR2 radii 100 on 100x60 (clamped?): M(100,30) L(100,30) C(97.753,41.055) C(81.055,57.753) C(54.14,60) L(45.86,60) C(18.945,57.753) C(2.247,41.055) C(0,30) L(0,30) C(2.247,18.945) C(18.945,2.247) C(45.86,0) L(54.14,0) C(81.055,2.247) C(97.753,18.945) C(100,30) Z
//   UR3 negative radius: M(100,30) L(100,44.713) C(99.251,53.685) C(93.685,59.251) C(84.713,60) L(0,60) C(0,60) C(0,60) C(0,60) L(0,0) C(0,0) C(0,0) C(0,0) L(84.713,0) C(93.685,0.749) C(99.251,6.315) C(100,15.287) Z
//   UR4 trim(0,0.25): M(100,20) L(100,29.427) C(98.502,47.37) C(87.37,58.502) C(69.427,60) L(57.806,60)
//   UR5 sizes: (0.0, 0.0, 100.0, 60.0)
//   --- X: extra arms
//   X1 UR TL=50 BL=50 on 100x60: M(100,30) L(100,60) C(100,60) C(100,60) C(100,60) L(45.86,60) C(18.945,57.753) C(2.247,41.055) C(0,30) L(0,30) C(2.247,18.945) C(18.945,2.247) C(45.86,0) L(100,0) C(100,0) C(100,0) C(100,0) Z bounds x0 y0 w100 h60 contains(2,30) true (2,5) false
//   X2 UR circular TL=45 on 100x60: M(100,30) L(100,60) C(100,60) L(0,60) C(0,60) L(0,45) C(45,0) L(100,0) C(100,0) Z
//   X3 UR circular 30/10/20/0: M(100,20) L(100,40) C(80,60) L(10,60) C(0,50) L(0,30) C(30,0) L(100,0) C(100,0) Z
//   X4 relative arc after move(0,0): M(0,0) L(100,50) C(50,100) bounds x0 y0 w100 h100
//   X5 relative arc delta 1000: end (58.682,0.76) bounds x0 y0 w100 h100
//   X6 relative arc delta -450: end (50,0)
//   X7 relative arc delta 0: M(93.301,75)
//   X8 rect w4 stroked: bounds x-2 y-2 w24 h14 (10,5) false (10,0) true (10,1.9) true (10,2.1) false (-1.9,-1.9) true
//   X9 line 100, trim(0.2,0.7) then strokedPath(w4,round) bounds: x18 y-2 w54 h4
//   X10 trim then trim: M(45,0) L(70,0)
//   X11 RR(10) 100x60 trim(0,0.5) end (0,30) (perimeter 100*2+60*2 - 8*10 + 2π*10 = 302.8318530717959)
//   X12 Capsule 100x60 trim(0,0.25) end (50,60)
//   X13 Rectangle trim(0.1,0.2) in 100x60: M(32,0) L(64,0)
//   --- Y: Uneven clamp rule
//   Y1 circular TL45 BL45: M(100,30) L(100,60) C(100,60) L(30,60) C(0,30) L(0,30) C(30,0) L(100,0) C(100,0) Z
//   Y2 circular TL50 BL50: M(100,30) L(100,60) C(100,60) L(30,60) C(0,30) L(0,30) C(30,0) L(100,0) C(100,0) Z
//   Y3 circular TL80 (h60): M(100,30) L(100,60) C(100,60) L(0,60) C(0,60) L(0,60) C(60,0) L(100,0) C(100,0) Z
//   Y4 circular TL70 TR70 (w100): M(100,55) L(100,60) C(100,60) L(0,60) C(0,60) L(0,50) C(50,0) L(50,0) C(100,50) Z
//   Y5 circular TL20 BL50: M(100,30) L(100,60) C(100,60) L(40,60) C(0,20) L(0,20) C(20,0) L(100,0) C(100,0) Z
//   Y6 continuous TL45: M(100,30) L(100,60) C(100,60) C(100,60) C(100,60) L(0,60) C(0,60) C(0,60) C(0,60) L(0,60) C(3.371,28.417) C(28.417,3.371) C(68.79,0) L(100,0) C(100,0) C(100,0) C(100,0) Z
//   Y7 circular all 40: M(100,30) L(100,30) C(70,60) L(30,60) C(0,30) L(0,30) C(30,0) L(70,0) C(100,30) Z
import SwiftUI

func fmt(_ v: CGFloat) -> String {
    let r = (Double(v) * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(r)
}
func pt(_ p: CGPoint?) -> String { p.map { "(\(fmt($0.x)),\(fmt($0.y)))" } ?? "nil" }
func dump(_ p: Path) -> String {
    var out: [String] = []
    p.forEach { e in
        switch e {
        case .move(let a): out.append("M\(pt(a))")
        case .line(let a): out.append("L\(pt(a))")
        case .quadCurve(let a, _): out.append("Q\(pt(a))")
        case .curve(let a, _, _): out.append("C\(pt(a))")
        case .closeSubpath: out.append("Z")
        }
    }
    return out.joined(separator: " ")
}
func box(_ p: Path) -> String {
    let b = p.boundingRect
    return "x\(fmt(b.minX)) y\(fmt(b.minY)) w\(fmt(b.width)) h\(fmt(b.height))"
}

print("--- C: positive controls")
var l345 = Path(); l345.move(to: .zero); l345.addLine(to: CGPoint(x: 3, y: 4))
print("C1 3-4-5 line trim(0,0.5): \(dump(l345.trimmedPath(from: 0, to: 0.5))) (expect L(1.5,2))")
let sq = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
print("C2 square trim(0,0.25): \(dump(sq.trimmedPath(from: 0, to: 0.25))) (expect M(0,0) L(10,0))")

print("--- TR: trimmedPath")
var two = Path(); two.move(to: .zero); two.addLine(to: CGPoint(x: 10, y: 0)); two.addLine(to: CGPoint(x: 10, y: 90))
print("TR2 L10 then L90, trim(0,0.5): \(dump(two.trimmedPath(from: 0, to: 0.5))) (arc length: ends (10,40); per element: (10,45) or (5,..))")
var quarter = Path(); quarter.addArc(center: .zero, radius: 100, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
let qt = quarter.trimmedPath(from: 0, to: 0.5)
print("TR3 quarter circle r100 trim(0,0.5) end: \(pt(qt.currentPoint)) (arc length: (70.711,70.711))")
print("TR3b quarter circle trim(0.25,0.75) bounds: \(box(quarter.trimmedPath(from: 0.25, to: 0.75)))")
print("TR4 two subpaths 10 and 90: ")
var sub = Path(); sub.move(to: .zero); sub.addLine(to: CGPoint(x: 10, y: 0)); sub.move(to: CGPoint(x: 0, y: 5)); sub.addLine(to: CGPoint(x: 90, y: 5))
print("   trim(0,0.5): \(dump(sub.trimmedPath(from: 0, to: 0.5))) (whole-path: M(0,0) L(10,0) M(0,5) L(40,5); per-subpath: halves)")
print("   trim(0.05,0.15): \(dump(sub.trimmedPath(from: 0.05, to: 0.15)))")
print("TR5 square trim(0.9,1): \(dump(sq.trimmedPath(from: 0.9, to: 1)))")
print("TR5b square trim(0,1): \(dump(sq.trimmedPath(from: 0, to: 1)))")
print("TR5c square trim(0.75,0.25) (from > to): \(dump(sq.trimmedPath(from: 0.75, to: 0.25)))")
print("TR5d square trim(0.5,0.5): '\(dump(sq.trimmedPath(from: 0.5, to: 0.5)))'")
print("TR5e square trim(-0.5,0.25): \(dump(sq.trimmedPath(from: -0.5, to: 0.25)))")
print("TR5f square trim(0,1.5): \(dump(sq.trimmedPath(from: 0, to: 1.5)))")
print("TR5g square trim(0.25,0.5) (interior): \(dump(sq.trimmedPath(from: 0.25, to: 0.5)))")
var open = Path(); open.move(to: .zero); open.addLine(to: CGPoint(x: 10, y: 0)); open.addLine(to: CGPoint(x: 10, y: 10))
print("TR6 open path trim(0,1): \(dump(open.trimmedPath(from: 0, to: 1)))")
var closedTri = open; closedTri.closeSubpath()
print("TR6b closed (explicit) trim(0.9,1): \(dump(closedTri.trimmedPath(from: 0.9, to: 1))) (closing edge length 14.142 counted?)")
print("TR6c closed trim(0,1): \(dump(closedTri.trimmedPath(from: 0, to: 1)))")
print("TR7 empty path trim: '\(dump(Path().trimmedPath(from: 0, to: 0.5)))'")

print("--- TS: Shape.trim start points (the first element of path(in:) and of the trimmed path)")
let r = CGRect(x: 0, y: 0, width: 100, height: 60)
func startOf(_ name: String, _ shape: some Shape) {
    let p = shape.path(in: r)
    let t = shape.trim(from: 0, to: 0.25).path(in: r)
    print("TS \(name): path \(dump(p).prefix(110)) | trim(0,0.25) \(dump(t).prefix(110)) end \(pt(t.currentPoint))")
}
startOf("Rectangle", Rectangle())
startOf("RoundedRectangle(20)", RoundedRectangle(cornerRadius: 20))
startOf("RoundedRectangle(20,circular)", RoundedRectangle(cornerRadius: 20, style: .circular))
startOf("Circle", Circle())
startOf("Ellipse", Ellipse())
startOf("Capsule", Capsule())
let sqr = CGRect(x: 0, y: 0, width: 100, height: 100)
print("TS2 Circle in 100x100 trim(0,0.5): \(dump(Circle().trim(from: 0, to: 0.5).path(in: sqr))) end \(pt(Circle().trim(from: 0, to: 0.5).path(in: sqr).currentPoint))")
print("TS2b Circle trim(0,0.25) end: \(pt(Circle().trim(from: 0, to: 0.25).path(in: sqr).currentPoint)) bounds \(box(Circle().trim(from: 0, to: 0.25).path(in: sqr)))")
print("TS2c Circle trim(0,1) elements: \(dump(Circle().trim(from: 0, to: 1).path(in: sqr)))")
print("TS3 trim size: \(Circle().trim(from: 0, to: 0.5).path(in: r).boundingRect)")

print("--- SP: strokedPath")
var hline = Path(); hline.move(to: .zero); hline.addLine(to: CGPoint(x: 10, y: 0))
for (name, style) in [("butt", StrokeStyle(lineWidth: 4)), ("round", StrokeStyle(lineWidth: 4, lineCap: .round)), ("square", StrokeStyle(lineWidth: 4, lineCap: .square))] {
    let sp = hline.strokedPath(style)
    print("SP \(name): bounds \(box(sp)) elements \(dump(sp).prefix(150))")
}
let ring = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100)).strokedPath(StrokeStyle(lineWidth: 10))
print("SP ring: bounds \(box(ring)) centre(50,50) \(ring.contains(CGPoint(x: 50, y: 50))) (50,2) \(ring.contains(CGPoint(x: 50, y: 2))) (50,-2) \(ring.contains(CGPoint(x: 50, y: -2))) (50,8) \(ring.contains(CGPoint(x: 50, y: 8))) (50,12) \(ring.contains(CGPoint(x: 50, y: 12)))")
print("SP dash [4,4] on 20 line w2: \(box(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 20, y: 0)) }.strokedPath(StrokeStyle(lineWidth: 2, dash: [4, 4])))) (0,0) \(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 20, y: 0)) }.strokedPath(StrokeStyle(lineWidth: 2, dash: [4, 4])).contains(CGPoint(x: 2, y: 0))) gap(6,0) \(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 20, y: 0)) }.strokedPath(StrokeStyle(lineWidth: 2, dash: [4, 4])).contains(CGPoint(x: 6, y: 0)))")
print("SP w0: '\(dump(hline.strokedPath(StrokeStyle(lineWidth: 0))))'")
var vee = Path(); vee.move(to: CGPoint(x: 0, y: 0)); vee.addLine(to: CGPoint(x: 10, y: 10)); vee.addLine(to: CGPoint(x: 20, y: 0))
for (name, join) in [("miter", CGLineJoin.miter), ("bevel", .bevel), ("round", .round)] {
    print("SP V \(name) w4 (elements; `box` above is not tight at a miter tip): \(dump(vee.strokedPath(StrokeStyle(lineWidth: 4, lineJoin: join, miterLimit: 10))))")
}

print("--- AR: arcs and transforms")
var rel = Path(); rel.move(to: CGPoint(x: 100, y: 50))
rel.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(90))
print("AR1 addRelativeArc 0 +90: end \(pt(rel.currentPoint)) bounds \(box(rel))")
var rel2 = Path(); rel2.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(-90))
print("AR2 addRelativeArc 0 -90: end \(pt(rel2.currentPoint)) bounds \(box(rel2))")
var abs0 = Path(); abs0.addArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
print("AR3 addArc 0..90 clockwise:false end \(pt(abs0.currentPoint)) bounds \(box(abs0))")
var rel3 = Path(); rel3.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(450))
print("AR4 addRelativeArc delta 450: end \(pt(rel3.currentPoint)) bounds \(box(rel3)) elements \(dump(rel3).count)")
var rel4 = Path(); rel4.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(90), transform: CGAffineTransform(translationX: 10, y: 20))
print("AR5 addRelativeArc with transform: end \(pt(rel4.currentPoint)) bounds \(box(rel4))")
var arcT = Path(); arcT.addArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false, transform: CGAffineTransform(scaleX: 2, y: 1))
print("AR6 addArc with scale(2,1): end \(pt(arcT.currentPoint)) bounds \(box(arcT))")
let tr = CGAffineTransform(translationX: 5, y: 7).rotated(by: .pi / 2)
print("AR7 applying(rotate 90 then translate): \(dump(Path(CGRect(x: 0, y: 0, width: 10, height: 20)).applying(tr)))")
print("AR8 offsetBy(3,4): \(dump(Path(CGRect(x: 0, y: 0, width: 10, height: 20)).offsetBy(dx: 3, dy: 4)))")
var addRectT = Path(); addRectT.addRect(CGRect(x: 0, y: 0, width: 10, height: 20), transform: CGAffineTransform(translationX: 1, y: 2))
print("AR9 addRect(transform:): \(dump(addRectT))")

print("--- UR: UnevenRoundedRectangle")
let ur = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 30, bottomLeading: 10, bottomTrailing: 20, topTrailing: 0))
let up = ur.path(in: r)
print("UR1 path: \(dump(up))")
print("UR1b bounds \(box(up)) contains(1,1) \(up.contains(CGPoint(x: 1, y: 1))) (99,1) \(up.contains(CGPoint(x: 99, y: 1))) (1,59) \(up.contains(CGPoint(x: 1, y: 59))) (99,59) \(up.contains(CGPoint(x: 99, y: 59)))")
let urBig = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 100, bottomLeading: 100, bottomTrailing: 100, topTrailing: 100)).path(in: r)
print("UR2 radii 100 on 100x60 (clamped?): \(dump(urBig))")
let urNeg = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: -5, bottomLeading: 0, bottomTrailing: 10, topTrailing: 10)).path(in: r)
print("UR3 negative radius: \(dump(urNeg))")
print("UR4 trim(0,0.25): \(dump(ur.trim(from: 0, to: 0.25).path(in: r)))")
print("UR5 sizes: \(ur.path(in: r).boundingRect)")

print("--- X: extra arms")
let urClamp = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 50, bottomLeading: 50, bottomTrailing: 0, topTrailing: 0)).path(in: r)
print("X1 UR TL=50 BL=50 on 100x60: \(dump(urClamp)) bounds \(box(urClamp)) contains(2,30) \(urClamp.contains(CGPoint(x: 2, y: 30))) (2,5) \(urClamp.contains(CGPoint(x: 2, y: 5)))")
let urClamp2 = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 45, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0), style: .circular).path(in: r)
print("X2 UR circular TL=45 on 100x60: \(dump(urClamp2))")
let urCirc = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 30, bottomLeading: 10, bottomTrailing: 20, topTrailing: 0), style: .circular).path(in: r)
print("X3 UR circular 30/10/20/0: \(dump(urCirc))")
var cur = Path(); cur.move(to: .zero); cur.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(90))
print("X4 relative arc after move(0,0): \(dump(cur)) bounds \(box(cur))")
var big = Path(); big.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(1000))
print("X5 relative arc delta 1000: end \(pt(big.currentPoint)) bounds \(box(big))")
var neg = Path(); neg.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(0), delta: .degrees(-450))
print("X6 relative arc delta -450: end \(pt(neg.currentPoint))")
var zero = Path(); zero.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .degrees(30), delta: .degrees(0))
print("X7 relative arc delta 0: \(dump(zero))")
let closedRect = Path(CGRect(x: 0, y: 0, width: 20, height: 10)).strokedPath(StrokeStyle(lineWidth: 4))
print("X8 rect w4 stroked: bounds \(box(closedRect)) (10,5) \(closedRect.contains(CGPoint(x: 10, y: 5))) (10,0) \(closedRect.contains(CGPoint(x: 10, y: 0))) (10,1.9) \(closedRect.contains(CGPoint(x: 10, y: 1.9))) (10,2.1) \(closedRect.contains(CGPoint(x: 10, y: 2.1))) (-1.9,-1.9) \(closedRect.contains(CGPoint(x: -1.9, y: -1.9)))")
var trimPath = Path(); trimPath.move(to: .zero); trimPath.addLine(to: CGPoint(x: 100, y: 0))
print("X9 line 100, trim(0.2,0.7) then strokedPath(w4,round) bounds: \(box(trimPath.trimmedPath(from: 0.2, to: 0.7).strokedPath(StrokeStyle(lineWidth: 4, lineCap: .round))))")
print("X10 trim then trim: \(dump(trimPath.trimmedPath(from: 0.2, to: 0.7).trimmedPath(from: 0.5, to: 1)))")
let rrTrim = RoundedRectangle(cornerRadius: 10, style: .circular).trim(from: 0, to: 0.5)
print("X11 RR(10) 100x60 trim(0,0.5) end \(pt(rrTrim.path(in: r).currentPoint)) (perimeter 100*2+60*2 - 8*10 + 2π*10 = \(2*100 + 2*60 - 80 + 2 * Double.pi * 10))")
print("X12 Capsule 100x60 trim(0,0.25) end \(pt(Capsule().trim(from: 0, to: 0.25).path(in: r).currentPoint))")
print("X13 Rectangle trim(0.1,0.2) in 100x60: \(dump(Rectangle().trim(from: 0.1, to: 0.2).path(in: r)))")

print("--- Y: Uneven clamp rule")
func uneven(_ tl: CGFloat, _ bl: CGFloat, _ br: CGFloat, _ tr: CGFloat, _ s: RoundedCornerStyle) -> String {
    dump(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: tl, bottomLeading: bl, bottomTrailing: br, topTrailing: tr), style: s).path(in: r))
}
print("Y1 circular TL45 BL45: \(uneven(45, 45, 0, 0, .circular))")
print("Y2 circular TL50 BL50: \(uneven(50, 50, 0, 0, .circular))")
print("Y3 circular TL80 (h60): \(uneven(80, 0, 0, 0, .circular))")
print("Y4 circular TL70 TR70 (w100): \(uneven(70, 0, 0, 70, .circular))")
print("Y5 circular TL20 BL50: \(uneven(20, 50, 0, 0, .circular))")
print("Y6 continuous TL45: \(uneven(45, 0, 0, 0, .continuous))")
print("Y7 circular all 40: \(uneven(40, 40, 40, 40, .circular))")
