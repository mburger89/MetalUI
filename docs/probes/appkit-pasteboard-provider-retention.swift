// Does an NSPasteboard retain an NSPasteboardItemDataProvider written through `writeObjects` (ruling CP-O)?
//
// Run: xcrun swiftc -O docs/probes/appkit-pasteboard-provider-retention.swift -o /tmp/p && /tmp/p
//
// Recorded 2026-10-22 (macOS 27 beta, private named pasteboard):
//   write true
//   provide called
//   provider deinit
//   after write; data: Optional(1 bytes)
//
// Reading: the only strong references to the provider (`p`) and the item were locals of `write`, which had returned,
// yet the provider answered the later read and was released only after it. The pasteboard (or the item it holds) keeps
// the provider alive until it is finished with it. Positive control: `provide called` proves the provider ran lazily.
// Separating arm: none can be built that lets the provider die early; `AppKitWindow.clipboardProviders` therefore stays
// as documented-contract insurance (NSPasteboard's documentation does not promise the retain), and mutation 2.10
// ("retain nobody") survives by measurement.
import AppKit
final class P: NSObject, NSPasteboardItemDataProvider {
    deinit { print("provider deinit") }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        print("provide called"); item.setData(Data([1]), forType: type)
    }
}
func write(_ pb: NSPasteboard) {
    let item = NSPasteboardItem()
    let p = P()
    item.setDataProvider(p, forTypes: [NSPasteboard.PasteboardType("com.x.y")])
    pb.clearContents()
    print("write", pb.writeObjects([item]))
}
let pb = NSPasteboard(name: NSPasteboard.Name("provider-retention-probe-\(getpid())"))
write(pb)
autoreleasepool {}
print("after write; data:", pb.data(forType: NSPasteboard.PasteboardType("com.x.y")) as Any)
pb.releaseGlobally()
