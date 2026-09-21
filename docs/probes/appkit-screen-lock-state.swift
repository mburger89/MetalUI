// The pre-capture check: is the screen LOCKED and the display ASLEEP, by the
// CoreGraphics session dictionary — plan task 4, lane 4, ruling FR-V in
// docs/superpowers/2026-09-15-frame-sizing-decisions.md (record §14).
//
// This is a probe of the MACHINE, not of SwiftUI: it records what the window
// server says about the login session and the main display, so that a lane
// owing real release-window captures (`MC-J`'s method: `screencapture -x -R…`,
// no input) knows before launching anything whether the capture can succeed.
// No SwiftUI claim is made, so no positive control is owed beyond the
// recorded readings below — and note that every reading so far is LOCKED;
// the first unlocked reading a later session takes is the control this probe
// still lacks.
//
// WHY IT EXISTS. The task brief's recipe said to check
//
//     ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked
//
// and capture if it prints `<false/>`. Lane 4 did: it printed `<false/>`, both
// demo windows opened (828×531 at (614, 259) by `CGWindowListCopyWindowInfo`),
// and every `screencapture -x -R614,259,828,531` printed `could not create
// image from rect`; a full-screen `screencapture -x` was a 4112×2658 PNG with
// 0 non-black pixels of 10 929 696. This dictionary, read in the same minute,
// said the screen was locked and the display asleep. `IOConsoleLocked`
// reports the CONSOLE SESSION (still this user's), not the screen lock, and
// it flipped to `<true/>` on a later reading of the same locked session —
// so it is not a lock signal in either direction (FR-V).
//
// HOW TO RUN. Compile with Apple's toolchain; the swiftly `swift` first on
// PATH is a swift.org build (ruling SA-O):
//
//     xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate
//     /tmp/lockstate 2>&1 | grep -v 'Connection\]'
//     ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked     # for comparison only
//
// The capture may be attempted only when `CGSSessionScreenIsLocked` is absent
// or 0 (reading 5: absent when unlocked) AND
// `displayAsleep main` is false. `preflightScreenCaptureAccess` is the
// permission, not the lock: it read `true` on every locked reading. The
// backstop, whatever any flag says, is the full-screen capture's non-black
// pixel count — 0 means nothing was captured.
//
// A NOTE ON THE API SHAPE, so nobody re-derives it: `CGSessionCopyCurrentDictionary()`
// returns `CFDictionary?` under Apple Swift 6.4, not an `Unmanaged`, so a
// `.takeRetainedValue()` spelling does not compile (`error: value of type
// 'CFDictionary' has no member 'takeRetainedValue'`); bridge it with
// `as? [String: Any]` as below.
//
// RECORDED OUTPUT — five readings: 1–4 locked (1–3 one lock, 4 a later one), 5
// UNLOCKED, the positive control; macOS
// 26.6.2 (25G83), Apple Swift 6.4 (swiftlang-6.4.0.33.1), one 2056×1329 @2x
// display:
//
// 1. 2026-09-15, lane 4's first run at `b513fa3` (~23:30 PDT), the session
//    `IOConsoleLocked` read `<false/>` on:
//
//      session CGSSessionScreenIsLocked = 1
//      session CGSSessionScreenLockedTime = 1789541394
//      displayAsleep main: 1
//      displayActive main: 0
//      preflightScreenCaptureAccess: true
//
// 2. 2026-09-16 04:02 PDT, lane 4's re-take at `7d5a3a7`, `IOConsoleLocked`
//    now `<true/>`:
//
//      session CGSSessionScreenIsLocked = 1
//      session CGSSessionScreenLockedTime = 1789543593
//      displayAsleep main: 1
//      displayActive main: 0
//      preflightScreenCaptureAccess: true
//
// 3. 2026-09-16 04:20:39 PDT, when this file was saved (record round at
//    `6c18389`), `IOConsoleLocked` `<true/>`, full output:
//
//      session CGSSessionScreenIsLocked = 1
//      session CGSSessionScreenLockedTime = 1789543593
//      session CGSSessionUniqueSessionUUID = 38632ECC-CF2D-4D7E-B8B2-CF39EEACBB02
//      session kCGSSessionAuditIDKey = 100016
//      session kCGSSessionGroupIDKey = 20
//      session kCGSSessionLoginwindowSafeLogin = 0
//      session kCGSSessionOnConsoleKey = 1
//      session kCGSSessionSecureInputPID = 627
//      session kCGSSessionSystemSafeBoot = 0
//      session kCGSSessionUserIDKey = 501
//      session kCGSSessionUserNameKey = maxburger
//      session kCGSessionLoginDoneKey = 1
//      session kCGSessionLongUserNameKey = Max Burger
//      session kSCSecuritySessionID = 100016
//      displayAsleep main: 1
//      displayActive main: 0
//      preflightScreenCaptureAccess: true
//      screens: ["(0.0, 0.0, 2056.0, 1329.0) scale=2.0"]
//
//    `kCGSSessionOnConsoleKey = 1` is the thing `IOConsoleLocked` is about:
//    the session IS on the console, and the screen is locked anyway.
//
// 4. 2026-09-16 09:07:08 PDT, the record round at `957b068`, `IOConsoleLocked`
//    `<true/>`; every key as in reading 3 except:
//
//      session CGSSessionScreenIsLocked = 1
//      session CGSSessionScreenLockedTime = 1789569027
//      displayAsleep main: 1
//      displayActive main: 0
//      preflightScreenCaptureAccess: true
//
//    The lock time moved (1789543593 → 1789569027), so the screen was
//    unlocked and re-locked between readings 3 and 4 with nobody capturing.
//    STILL NO POSITIVE CONTROL at this reading (closed by reading 5).
//
// 5. 2026-09-17 06:57:23 PDT, at `12abda1`, UNLOCKED — the positive control,
//    on macOS 27.0, same toolchain and display. `IOConsoleLocked` `<false/>`.
//    Every key as in reading 3 EXCEPT that `CGSSessionScreenIsLocked` and
//    `CGSSessionScreenLockedTime` are ABSENT (no line printed; they are not
//    0), and `kCGSSessionSecureInputPID` is absent too:
//
//      displayAsleep main: 0
//      displayActive main: 1
//      preflightScreenCaptureAccess: true
//
//    Together with it, a full-screen `screencapture -x` wrote a 4112×2658 PNG
//    with 10 929 102 non-black pixels of 10 929 696 (against 0 at reading 1),
//    and the release-window captures in record §03 succeeded. So the rule is
//    "the lock keys are absent (or 0) and the display is not asleep", and it
//    has now been observed in both directions.

import CoreGraphics
import AppKit

let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
for k in d.keys.sorted() { print("session \(k) = \(d[k]!)") }
print("displayAsleep main:", CGDisplayIsAsleep(CGMainDisplayID()))
print("displayActive main:", CGDisplayIsActive(CGMainDisplayID()))
print("preflightScreenCaptureAccess:", CGPreflightScreenCaptureAccess())
print("screens:", NSScreen.screens.map { "\($0.frame) scale=\($0.backingScaleFactor)" })
