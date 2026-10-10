// AppKit probe: does `NSApplication` hand a path on the command line to the
// delegate's `application(_:open:)` by itself — so that an app also feeding
// `CommandLine.arguments` to `App.open(_:)` (ruling AS-G item 6's recipe)
// would receive the document twice on macOS? Evidence for ruling AS-M in
// docs/superpowers/2026-10-08-app-shell-decisions.md.
//
// HOW TO RUN (compiled form, SA-O). The probe opens no window; it installs a
// delegate before `run()` (as AppKitPlatform.run() will, AS-C item 7), prints
// what the delegate heard, and exits 0.5 s after `applicationDidFinishLaunching`.
//
//   xcrun swiftc docs/probes/appkit-launch-arguments-open.swift -o /tmp/argv-open
//   touch /tmp/argv-probe.mcgraph
//   /tmp/argv-open                                                   # A0
//   /tmp/argv-open /tmp/argv-probe.mcgraph                           # A1
//   /tmp/argv-open /tmp/argv-probe.mcgraph -NSTreatUnknownArgumentsAsOpen NO   # A2
//   /tmp/argv-open /tmp/does-not-exist.mcgraph                       # A3
//   /tmp/argv-open --verbose                                         # A4
//   # A5: the same binary as Contents/MacOS/ArgvOpen of a minimal ArgvOpen.app
//   # (Info.plist: CFBundleExecutable, CFBundleIdentifier, CFBundlePackageType
//   # APPL, CFBundleDocumentTypes for `mcgraph`, role Editor), run directly:
//   ArgvOpen.app/Contents/MacOS/ArgvOpen /tmp/argv-probe.mcgraph
//   # A6 (positive control for application(_:open:)): LaunchServices opens it
//   open -W -n --stdout /tmp/a6.txt -a ArgvOpen.app /tmp/argv-probe.mcgraph
//
// INSTRUMENT. The delegate's `application(_:open:)` and
// `applicationDidFinishLaunching(_:)` each print one line, in order.
// POSITIVE CONTROLS: A0 prints `didFinishLaunching` (the delegate is installed
// and called); A6 shows `application(_:open:)` is reached when LaunchServices
// opens a document (so A1's silence is not a deaf instrument). SEPARATING
// ARMS: A1 vs A0 (a path argument, the only change); A2 vs A1 (AppKit's own documented switch, turning the behaviour off); A3 (a
// path that does not exist); A4 (a dash argument, as SwiftPM and test runners
// pass).
//
// RECORDED 2026-10-09 by the app-shell critic session, macOS 27.0.1, Apple
// Swift 6.4, screen unlocked (no CGSSessionScreenIsLocked line,
// displayAsleep main: 0). Each arm run twice, stdout byte-identical, exit 0.
//
// OUTPUT, verbatim (`=== <arm>` and `status=` lines written by the shell loop;
// A6's lines are the --stdout file):
//
//   === A0
//     didFinishLaunching
//     exit
//     status=0
//   === A1
//     didFinishLaunching
//     exit
//     status=0
//   === A2
//     didFinishLaunching
//     exit
//     status=0
//   === A3
//     didFinishLaunching
//     exit
//     status=0
//   === A4
//     didFinishLaunching
//     exit
//     status=0
//   === A5
//     didFinishLaunching
//     exit
//     status=0
//   === A6
//     application(_:open:) urls=["file:///private/tmp/argv-probe.mcgraph"]
//     didFinishLaunching
//     exit
//
// READING. AppKit does NOT turn a command-line path into an open, bundled or
// not, with or without a document type (A1, A3, A5 identical to A0): the
// recipe that feeds CommandLine.arguments to App.open delivers each document
// once on macOS too. A LaunchServices open (A6) reaches application(_:open:)
// BEFORE applicationDidFinishLaunching — during run()'s finishLaunching, after
// App's initialiser and any openWindow made before run().

import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        print("  application(_:open:) urls=\(urls.map(\.absoluteString))")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("  didFinishLaunching")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("  exit")
            fflush(stdout)
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
