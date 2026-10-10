// AppKit probe: does a bundle that declares a document type with NO
// `NSDocumentClass` (MetalCreator's `.mcgraph` Info.plist shape, the shape
// docs/packaging.md shows) make AppKit put up its "cannot open files in this
// format" alert when LaunchServices opens a document — or does an application
// delegate implementing `application(_:open:)` (AppKitApplicationDelegate,
// ruling AS-G item 5) take the open with no alert? Evidence for record §87 and
// docs/packaging.md "Documents and URLs an application opens"; human check AS9
// keeps the Finder double-click and Dock drop themselves.
//
// HOW TO RUN (compiled form, SA-O). One binary, two arms chosen by an
// environment variable passed through `open --env`; each arm is a minimal
// bundle `ASProbe.app` whose Info.plist is MetalCreator's shape (role Editor,
// LSHandlerRank Owner, LSItemContentTypes naming an exported type for the
// extension `asprobe`, no NSDocumentClass, no NSPrincipalClass):
//
//   D=$(mktemp -d); mkdir -p $D/ASProbe.app/Contents/MacOS
//   xcrun swiftc docs/probes/appkit-open-without-document-class.swift \
//       -o $D/ASProbe.app/Contents/MacOS/ASProbe
//   cat > $D/ASProbe.app/Contents/Info.plist <<'EOF'   (keys as listed above:
//     CFBundleExecutable ASProbe, CFBundleIdentifier com.example.asprobe,
//     CFBundlePackageType APPL, CFBundleDocumentTypes [{CFBundleTypeName
//     "ASProbe Document", CFBundleTypeRole Editor, LSHandlerRank Owner,
//     LSItemContentTypes [com.example.asprobe.document]}],
//     UTExportedTypeDeclarations [{UTTypeIdentifier com.example.asprobe.document,
//     UTTypeConformsTo [public.data], UTTypeTagSpecification
//     {public.filename-extension [asprobe]}}])
//   EOF
//   touch $D/one.asprobe $D/two.asprobe
//   # W0: the delegate implements application(_:open:) (MetalUI's shape)
//   open -W -n --stdout $D/w0.txt --env ARM=W0 -a $D/ASProbe.app $D/one.asprobe
//   # W1: separating arm — the delegate does NOT implement application(_:open:)
//   open -W -n --stdout $D/w1.txt --env ARM=W1 -a $D/ASProbe.app $D/one.asprobe
//   # W2: W0, then a second open while it runs (the app already running)
//   open -n --stdout $D/w2.txt --env ARM=W2 -a $D/ASProbe.app $D/one.asprobe; \
//       sleep 1; open -a $D/ASProbe.app $D/two.asprobe; sleep 3
//
// INSTRUMENT. 1.5 s after `applicationDidFinishLaunching` (W2: 3 s), a timer
// in the common run-loop modes (so it fires under a modal alert too) prints
// every window AppKit has — class, visibility, title — and `NSApp.modalWindow`,
// then exits 0. A background fallback exits 3 at 6 s. POSITIVE CONTROL: W1
// must show the alert window (a deaf instrument would print none in W1 too);
// W0 vs W1 differ only in the delegate method.
//
// RECORDED 2026-10-09 by the app-shell branch checker, macOS 27.0.1, Apple
// Swift 6.4, screen unlocked (no CGSSessionScreenIsLocked line,
// displayAsleep main: 0). Each arm run twice, `open` status 0, the two runs
// byte-identical; `plutil -lint` read OK on the Info.plist.
//
// OUTPUT, verbatim (the --stdout files):
//
//   === W0
//     arm=W0
//     application(_:open:) urls=["one.asprobe"]
//     didFinishLaunching
//     windows=0 modal=nil
//     exit
//   === W1
//     arm=W1
//     didFinishLaunching
//     window _NSAlertPanel visible=true title=""
//     windows=1 modal=_NSAlertPanel
//     exit
//   === W2
//     arm=W2
//     application(_:open:) urls=["one.asprobe"]
//     didFinishLaunching
//     application(_:open:) urls=["two.asprobe"]
//     windows=0 modal=nil
//     exit
//
// READING. With no NSDocumentClass, AppKit's "cannot open files" alert comes
// up (a modal _NSAlertPanel, W1) ONLY when the delegate does not implement
// application(_:open:); a delegate that implements it receives the document
// and no window or alert appears (W0), at launch and again with the app
// already running (W2). AppKitPlatform.run() installs such a delegate before
// NSApplication.run(), so a MetalUI app with MetalCreator's Info.plist shape
// gets .onOpenURL and no alert. Not covered: a Finder double-click and a Dock
// drop themselves (the same open-documents Apple Event `open -a` sends, but
// unmeasured here) — human check AS9.

import AppKit

let arm = ProcessInfo.processInfo.environment["ARM"] ?? "W0"

class BaseDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("  didFinishLaunching")
        fflush(stdout)
        let delay: TimeInterval = arm == "W2" ? 3.0 : 1.5
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows {
                    print("  window \(type(of: window)) visible=\(window.isVisible) title=\"\(window.title)\"")
                }
                print("  windows=\(NSApp.windows.count) modal=\(NSApp.modalWindow.map { "\(type(of: $0))" } ?? "nil")")
                print("  exit")
                fflush(stdout)
                exit(0)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) { exit(3) }
    }
}

final class OpeningDelegate: BaseDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        print("  application(_:open:) urls=\(urls.map(\.lastPathComponent))")
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate: BaseDelegate = arm == "W1" ? BaseDelegate() : OpeningDelegate()
app.delegate = delegate
print("  arm=\(arm)")
app.run()
