// SwiftUI probe: what a `Text` literal's interpolation does with a value that is
// not a string, a number or a `Text` — an arbitrary type, an `AttributedString`
// and an `Image` — and whether SwiftUI warns. Evidence for ruling RT-O items 4–5
// in docs/superpowers/2026-10-08-rich-text-decisions.md (the critic pass).
//
// HOW TO RUN, from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-text-interpolation.swift -o /tmp/interp-probe 2>&1 | grep -c "is deprecated: Localized"
//   /tmp/interp-probe
//
// INSTRUMENT: `ImageRenderer` at scale 2 on white; `px` counts RGB mismatches
// between two renders padded to one canvas. "≡ X" means 0 px against X.
// POSITIVE CONTROL: I0 (bold vs regular "v BOLD" differ; a render equals itself).
//
// RECORDED 2026-10-08 by the rich-text critic pass, macOS 27.0, compiled twice
// (verdicts identical; only I4's non-matching "description" count wobbled,
// 3250 / 3249). Compiling prints 2 warnings, one per arbitrary-type
// interpolation (I1, I2): "'appendInterpolation' is deprecated: Localized string
// interpolation produces an unlocalized, debug description for this type of
// value. Use a type supported by LocalizedStringKey.StringInterpolation or
// initialize a LocalizedStringResource instead …" (and 6 for this file's own
// `+` candidates). The `AttributedString`, `Image` and `Text` interpolations
// here compile without one; so do `swiftui-rich-text.swift`'s `String`, `Int`
// and `Double` ones (`M10`, `M11`, `M11b`: its 146 warnings are all `+`).
//
//     I0 bold vs regular: 607 px; self: 0
//     I1 Text("v \(Described())") ≡ description  [description:0 type name:1421]
//     I2 Text("v \(Plain())") ≡ String(describing:)  [String(describing:):0 empty:721]
//     I3 Text("v \(bold attributed)") ≡ runs kept  [runs kept:0 plain:607 debug description:780]
//     I4 Text("v \(Image(systemName: "star"))") ≡ image inline  [image inline:0 description:3250]
import SwiftUI
import AppKit

struct Described: CustomStringConvertible { var description: String { "DESC" } }
struct Plain {}

@MainActor func bitmap(_ view: some View) -> NSBitmapImageRep {
    let r = ImageRenderer(content: view.padding(2).frame(width: 200, height: 30, alignment: .topLeading).background(Color.white))
    r.scale = 2
    return NSBitmapImageRep(cgImage: r.cgImage!)
}
@MainActor func px(_ a: some View, _ b: some View) -> Int {
    let x = bitmap(a), y = bitmap(b)
    var n = 0
    for row in 0..<min(x.pixelsHigh, y.pixelsHigh) {
        for col in 0..<min(x.pixelsWide, y.pixelsWide) {
            let p = x.colorAt(x: col, y: row)!, q = y.colorAt(x: col, y: row)!
            if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent) + abs(p.blueComponent - q.blueComponent) > 0.01 { n += 1 }
        }
    }
    return n
}
@MainActor func identify(_ id: String, _ subject: some View, _ candidates: [(String, AnyView)]) {
    let scores = candidates.map { ($0.0, px(subject, $0.1)) }
    let best = scores.filter { $0.1 == 0 }.map(\.0)
    print("\(id) ≡ \(best.isEmpty ? "none" : best.joined(separator: ","))  [" + scores.map { "\($0.0):\($0.1)" }.joined(separator: " ") + "]")
}

@MainActor func main() {
    var bold = AttributedString("BOLD"); bold.inlinePresentationIntent = .stronglyEmphasized
    print("I0 bold vs regular: \(px(Text(verbatim: "v ") + Text("BOLD").bold(), Text(verbatim: "v BOLD"))) px; self: \(px(Text(verbatim: "v BOLD"), Text(verbatim: "v BOLD")))")
    identify("I1 Text(\"v \\(Described())\")", Text("v \(Described())"),
             [("description", AnyView(Text(verbatim: "v DESC"))), ("type name", AnyView(Text(verbatim: "v Described()")))])
    identify("I2 Text(\"v \\(Plain())\")", Text("v \(Plain())"),
             [("String(describing:)", AnyView(Text(verbatim: "v \(String(describing: Plain()))"))), ("empty", AnyView(Text(verbatim: "v ")))])
    identify("I3 Text(\"v \\(bold attributed)\")", Text("v \(bold)"),
             [("runs kept", AnyView(Text(verbatim: "v ") + Text("BOLD").bold())), ("plain", AnyView(Text(verbatim: "v BOLD"))),
              ("debug description", AnyView(Text(verbatim: "v \(String(describing: bold))")))])
    identify("I4 Text(\"v \\(Image(systemName: \"star\"))\")", Text("v \(Image(systemName: "star"))"),
             [("image inline", AnyView(Text(verbatim: "v ") + Text(Image(systemName: "star")))), ("description", AnyView(Text(verbatim: "v \(String(describing: Image(systemName: "star")))")))])
}
MainActor.assumeIsolated { main() }
