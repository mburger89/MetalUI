# Single-instance launch on SDL - design (S7)

Item S7 of the gpui-gap list (user request 2026-10-02; found answering MetalCreator's SDL-port gap 5; not a plan task). Branch
`feat/single-instance` from `ffbabb5c`; divergence labels 525-534 reserved, none taken; decisions
`docs/superpowers/2026-10-19-single-instance-decisions.md` (`SN-`). Record `docs/record/122-single-instance.md` (Record phase).
**Status: LANDED, record 122 (SN-P records the lane's amendments: the C file is `SDLInstance.c`, Windows elects with a semaphore).** Lanes: **one** (the files below are one coherent unit and share the C bridge).

## 1. Problem

On Linux and Windows a file manager runs `Exec=MyApp %F` once per open, so a second document starts a second process and the first never
hears of it (divergence 176's half that `AS-G` could not close; `docs/packaging.md` says "not built (owner none)"). macOS bundled apps
get this from LaunchServices (probe `A6`). SwiftUI has no cross-process API (so no SwiftUI spelling to follow; gpui likewise leaves it
to the host: Zed's own CLI uses a local socket, recollection, not verified here), hence MetalUI-only class `M`.

## 2. Inventory (read at `ffbabb5c`)

- `SDLPlatform.onOpenURLs` + parking + `handleApplicationDrop` (`SDLPlatform.swift` ~253-300): the delivery path to reuse.
- `SDLPlatform.run(maxIterations:)`: blocks in `mui_wait_event(…, 250)`, drains the main queue after each pump (`SV-H`).
- `SDLPlatformOptions.swift` and the trait-off stub (`SDLPlatform.swift` ~1440): where `Options.singleInstance` lands.
- `SDLBridge.c`/`SDLBridge.h`: the C home for the pure threaded transport (`CB-H`'s pattern).
- `App.open(_:)` (`AppShell.swift:215`): routes to the key window's handler, else the first with one, else `App.onOpenURL`.
- `docs/packaging.md` "Launch arguments" (l. 476-496), "Linux: MimeType= and %F", "Windows: a file association".

## 3. Public API (all in `MetalUISDL`, trait `SDL`)

```swift
public final class SingleInstance: Sendable, Hashable {
    public enum Outcome { case primary(SingleInstance), forwarded, unavailable(Failure) }
    public enum Failure: Error, Equatable { case emptyID, noListener, refused, insecureDirectory, pathTooLong, insecure, io(Int32) }
    public struct Configuration: Sendable { directory: String?, connectTimeout: Duration (2 s), readTimeout: Duration (2 s),
                                            raisesWindow: Bool (true), expectedPeerUID: UInt32? (nil) ; static let `default` }
    public static func claim(id: String, forwarding: [String], configuration: Configuration = .default) -> Outcome
}
extension SDLPlatform.Options { public var singleInstance: SingleInstance? }          // default nil
extension SDLPlatform { public static func launchingSingleInstance(id: String, forwarding: [String],
                                                                   options: Options = .default) throws -> SDLPlatform? }
```

Recipe (to `docs/packaging.md`, "Launch arguments", replacing its last sentence):

```swift
let documents = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }
guard let platform = try SDLPlatform.launchingSingleInstance(id: "com.example.MyApp", forwarding: Array(documents)) else { exit(0) }
let app = try App(platform: platform, textSystem: …)   // then openWindow, app.open(documents), app.run() as today
```

## 4. Files (the one lane)

| File | Change |
|---|---|
| `Backends/SDL/Sources/SDLBridge/SDLInstance.c` (new, SN-P), `SDLBridge.c` (wake mapping), `include/SDLBridge.h` | `mui_instance_*`: claim (flock / Win mutex), listener thread, wire decode/encode, queue, peer check, wake event, forward client |
| `Backends/SDL/Sources/MetalUISDL/SingleInstance.swift` (new) | the public type, path resolution of relative arguments, `Failure` mapping |
| `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `SDLPlatformOptions.swift` | `Options.singleInstance` (+ stub mirror), per-iteration drain, `handleApplicationOpen`, raise (`raiseWindow` closure), `launchingSingleInstance` |
| `Backends/SDL/Sources/SingleInstanceCheck/main.swift` (new), `Backends/SDL/Package.swift` | the subprocess executable (modes `primary`, `forward`) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLSingleInstanceTests.swift` (new) | tests below |
| `Tests/MetalUITests/…` guard file for the stub | guard 1.6b: the trait-off `SingleInstance`/`Options.singleInstance` spellings report the trait's remedy |
| `docs/packaging.md`, `docs/migration.md` (note: **none owed**, stated), `docs/verification/human-checks.md` (group `SI`), `docs/testing.md` (a short recipe) | docs |

Root `Sources/` is untouched (no new public declaration, no inventory row, no seam change, pixels 0 px by construction); the
Record phase edits `CLAUDE.md`/`AGENTS.md` (one rule), the record index, `docs/record/122`.

## 5. Tests (Backends/SDL, `SDLSingleInstanceTests`) - red-before and the mutation that must redden each

Red before = the API does not exist (compile failure) for every test; "meaningful red" is the mutation. Each test runs on a private temp
directory (SN-K). Mutations are applied one at a time, full unfiltered suite, committed first.

1. `aSecondClaimForwardsItsArgumentsAndThePrimaryReceivesThemInOrder` - three `claim`s with 2, 1, 3 strings; the primary's
   `onOpenURLs` batches equal them in order. M: drain the queue LIFO; M: append instead of enqueue-per-connection (merges batches).
2. `aForwardedPathBecomesAFileURLAndARelativeOneIsMadeAbsoluteByTheSender` - `"rel/a b.txt"`, an absolute path, `https://x/y`,
   `C:\\x` shape. M: skip the sender's absolutising; M: treat every string as a path.
3. `batchesWaitForAHandlerAndAreDeliveredOnceInOrder` - forward, then set `onOpenURLs`. M: drop when nil.
4. `aStaleSocketFileIsReplacedByANewPrimary` - plant a `.sock` file (and a bound-then-abandoned socket) with no lock. M: refuse when the
   file exists.
4b. `eightConcurrentClaimsElectExactlyOnePrimary` (SN-M). M: claim without `flock`.
5. `aKilledPrimaryReleasesTheRole` (subprocess, `primary` mode, `SIGKILL`, then `claim` returns `.primary`). M: lock fd without
   `flock` (bind-only election; the race test 4b is the separating one).
6. `aSecondProcessForwardsAndExitsZero` (subprocess `forward`, assert status 0 and delivery). M: the check exits 1 on `.forwarded`.
7. `aLockHeldWithNoListenerFallsBackToUnavailableWithinTheTimeout` - hold the lock with a raw `flock`; `connectTimeout` 0.3 s;
   expect `.unavailable(.noListener)` and elapsed < 2 s. M: retry forever (a bounded wait via the test's hang watchdog).
8. `aMalformedMessageIsRefusedAndTheListenerKeepsServing` (`@Test(arguments:)` over bad magic, truncated count, truncated string,
   length beyond the payload, `payloadLength` 1 MiB + 1, count 1025, string 32769, ill-formed UTF-8, embedded NUL, empty string, bytes left inside the payload): raw client; expect NAK or close, nothing delivered, then a valid message is delivered. M per limit: raise each limit by one;
   M: replace the UTF-8 / NUL check; M: allocate before checking.
9. `aStalledClientIsCutOffByTheReadTimeoutAndDoesNotBlockTheNextOne` - half a header, hold, `readTimeout` 0.3 s, then a good client.
   M: no deadline (watchdog).
10. `aPeerOfAnotherUserIsRejectedUnread` - `expectedPeerUID` = uid + 1. M: skip the peer check.
11. `theSocketAndItsDirectoryArePrivate` - 0700 directory, 0600 socket and lock; a 0777 directory and a symlinked directory answer
    `.insecureDirectory`. M: drop `umask`; M: skip `lstat`.
12. `anOverlongDirectoryIsNamedNotTruncated` - `.pathTooLong`. M: truncate.
13. `theSixtyFifthPendingMessageIsRefused` (no platform draining); the same test then drains and asserts the queue accepts again. M: unbounded queue.
14. `twoIdsAreTwoIndependentPrimaries` and `anEmptyIDIsRefused`. M: id ignored in the hash.
15. `aDeliveredMessageRaisesTheKeyWindowElseTheFirstAndNeverAHiddenOne` (the `raiseWindow` stub; an empty forward also raises;
    `raisesWindow: false` and `hidesWindows` do not). M: always raise;
    M: never raise.
16. `theWakeEventEndsABlockedWaitPromptly` - `run(maxIterations:)` with a forward from another thread; the delivery happens in
    `run(maxIterations: 1)` with the wake counted by a package read-back (SN-M; count, not time). M: no `SDL_PushEvent` (count 0).
17. `dropDeliveryAndForwardDeliveryDoNotInterleaveABatch` - a window-0 `DROP_FILE` pair, a forward between, then `DROP_COMPLETE`.
    M: share one accumulator.
18. `theClaimIsReleasedWhenThePlatformGoesAway` - after release a fresh claim is primary and the socket is gone. M: no `deinit` unlink
    (the stale path still recovers, so the assertion is the file's absence).
19. Root guard 1.6b `theTraitOffStubSpellsSingleInstance` (`typecheckFile`, trait-off module). M: drop `singleInstance` from the stub
    `Options` (red), once.

Linux image: all of 1-18 (no display needed). Windows: CI builds; tests 1-4, 6-10, 13-14, 16-18 run in CI's Windows job unchanged
except the `0600`/`0700` assertions of 11 and the signal of 5, which are `#if !os(Windows)` (their Windows twin is check SI3).
Root suite: 3970 unchanged plus guard 1.6b's test (3971 expected); `Backends/SDL` grows by about 28 cases.

## 6. Demo expectation

No demo change: the feature has no pixels. `MetalUISDLDemo` gains `--single-instance <id>` only if a human check needs it; otherwise group
`SI` uses `SingleInstanceCheck` plus the demo's existing `.onOpenURL` section (`METALUI_APP_SHELL_DEMO=1`). Pixels: 0 px, fourteen images.

## 7. Human checks (group `SI`, **not run: an agent cannot**)

SI1 Linux (X11 and Wayland): `.desktop` with `Exec=… %F`, double-click a second document in a file manager: the first window shows it, no
second window, the window raises or its taskbar entry flashes. SI2 `kill -9` the primary, relaunch: a fresh primary starts; launch
again: forwards. SI3 Windows 11 (x64 and ARM64; also two sessions of one user, SN-D): the same with Explorer and a file association; `Local\` mutex abandoned after End Task.
SI4 Wayland activation: record whether the raise needs the token (SN-H, SN-L). SI5 two users on one machine (fast user switching or `su`):
neither sees the other's primary. SI6 a primary left running 8 hours then forwarded to.

## 8. Deferred (SN-L) and honest scope

D-Bus activation, activation-token forwarding, cwd/env forwarding, a reply channel, an AppKit twin: named in SN-L with reasons. Windows is
compiled and reviewed, not run, by this item.
