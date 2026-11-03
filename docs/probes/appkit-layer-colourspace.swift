// End to end: does a `CAMetalLayer` tagged sRGB display the same pixels as
// SwiftUI's sRGB colour? (round 4 item R4-1 PR C, ruling `LS-A`, divergence 1)
//
// Four columns in one window, all the same bytes `#38BDF8` (56, 189, 248):
//   S   SwiftUI `Color(.sRGB, red:green:blue:)` in an `NSHostingView`
//   C   a plain `CALayer` whose `backgroundColor` is `CGColor(srgbRed:…)`
//   L1  a `CAMetalLayer`, `bgra8Unorm`, `colorspace = sRGB`, cleared to the bytes
//   L2  the same layer tagged Display P3 (the separating arm: MetalUI's old tag)
// The window is captured by id (`screencapture -x -o -l`, no shadow, no input,
// `capture.sh`'s method) and the centre pixel of each column is read from the
// PNG's raw samples (the display's own space, the same for all four).
//
// EXPECTED: S == C == L1, and L2 != L1. If S != L1 the ruling is wrong: stop.
//
// PRECONDITION (`capture.sh`): run `appkit-screen-lock-state.swift` first and
// proceed only when it prints no CGSSessionScreenIsLocked line, and `swift`
// has Screen Recording permission (`preflightScreenCaptureAccess: true`).
//
// Run: xcrun swiftc -O docs/probes/appkit-layer-colourspace.swift -o /tmp/alcs && /tmp/alcs
//
// Recorded output: NOT RUN to a verdict on 2026-11-03. The session was locked
// (`CGSSessionScreenIsLocked = 1`) and `preflightScreenCaptureAccess` read
// false: the probe compiled, opened its window, and printed "could not create
// image from window / no capture ..." (exit 2). Record 200 §1 and human check
// LS1 carry this gate. Fill in the readings here when an unlocked session runs it.
import AppKit
import Metal
import QuartzCore
import SwiftUI

let bytes: (UInt8, UInt8, UInt8) = (0x38, 0xBD, 0xF8)
let colW = 100, colH = 100
let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!

func metalView(_ space: CFString) -> NSView {
    let v = NSView(frame: NSRect(x: 0, y: 0, width: colW, height: colH))
    v.wantsLayer = true
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.colorspace = CGColorSpace(name: space)
    layer.framebufferOnly = true
    layer.isOpaque = true
    layer.drawableSize = CGSize(width: colW * 2, height: colH * 2)
    layer.contentsScale = 2
    v.layer = layer
    return v
}
func clear(_ view: NSView) {
    let layer = view.layer as! CAMetalLayer
    guard let drawable = layer.nextDrawable() else { return }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bytes.0) / 255,
        green: Double(bytes.1) / 255, blue: Double(bytes.2) / 255, alpha: 1)
    let cb = queue.makeCommandBuffer()!
    cb.makeRenderCommandEncoder(descriptor: pass)!.endEncoding()
    cb.present(drawable); cb.commit()
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: colW * 4, height: colH),
                      styleMask: [.titled], backing: .buffered, defer: false)
let root = NSView(frame: NSRect(x: 0, y: 0, width: colW * 4, height: colH))
let s = NSHostingView(rootView: Color(.sRGB, red: Double(bytes.0) / 255, green: Double(bytes.1) / 255,
                                      blue: Double(bytes.2) / 255, opacity: 1))
s.frame = NSRect(x: 0, y: 0, width: colW, height: colH)
let c = NSView(frame: NSRect(x: colW, y: 0, width: colW, height: colH))
c.wantsLayer = true
c.layer!.backgroundColor = CGColor(srgbRed: CGFloat(bytes.0) / 255, green: CGFloat(bytes.1) / 255,
                                   blue: CGFloat(bytes.2) / 255, alpha: 1)
let l1 = metalView(CGColorSpace.sRGB); l1.frame.origin.x = CGFloat(colW * 2)
let l2 = metalView(CGColorSpace.displayP3); l2.frame.origin.x = CGFloat(colW * 3)
for v in [s, c, l1, l2] { root.addSubview(v) }
window.contentView = root
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

func sleepf(_ t: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: t)) }
sleepf(0.5); clear(l1); clear(l2); sleepf(2.0)

let out = NSTemporaryDirectory() + "alcs.png"
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", String(window.windowNumber), out]
try! p.run(); p.waitUntilExit()
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: out) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil), let data = img.dataProvider?.data else {
    print("no capture (locked session or no Screen Recording permission)"); exit(2)
}
let ptr = CFDataGetBytePtr(data)!
let scale = Double(img.width) / Double(colW * 4)
var read: [String: [Int]] = [:]
for (i, name) in ["S", "C", "L1", "L2"].enumerated() {
    let x = Int((Double(i * colW + colW / 2)) * scale), y = img.height - Int(Double(colH / 2) * scale) - 1
    let o = y * img.bytesPerRow + x * (img.bitsPerPixel / 8)
    // CGImage from screencapture is BGRA or RGBA by bitmapInfo; print both orders' source space too.
    let px = [Int(ptr[o]), Int(ptr[o + 1]), Int(ptr[o + 2])]
    read[name] = px
    print("\(name): raw bytes \(px)  space \(img.colorSpace?.name as String? ?? "?")  bitmapInfo \(img.bitmapInfo.rawValue)")
}
print("S == C:  \(read["S"]! == read["C"]!)")
print("S == L1: \(read["S"]! == read["L1"]!)   (must be true)")
print("L2 != L1: \(read["L2"]! != read["L1"]!)  (must be true; the separating arm)")
exit(read["S"]! == read["L1"]! && read["L2"]! != read["L1"]! ? 0 : 1)
