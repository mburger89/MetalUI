# 122 — Single-instance launch on SDL

Branch `feat/single-instance` from `ffbabb5c` (master: PR #98, small pins). **Not a plan task**: item S7 of the gpui-gap list
(user request 2026-10-02), found while answering MetalCreator's SDL-port gap 5 (open-document events, divergence 176): on Linux and
Windows a file manager runs `Exec=MyApp %F` once per open, so a second document started a second process and the running app never
heard of it. Spec `docs/superpowers/specs/2026-10-19-single-instance-design.md`; rulings `SN-A`…`SN-P` in the new decisions doc
`docs/superpowers/2026-10-19-single-instance-decisions.md` (next unused `SN-Q`). No SwiftUI probe: SwiftUI has no cross-process API
(MetalUI-only, class `M`); macOS LaunchServices already forwards opens to a bundled app (probe `docs/probes/appkit-launch-arguments-open.swift`
arm `A6`).

**Numbering.** Written as §122 against master `ffbabb5c`; master published nothing newer at the Record phase (`git fetch`:
`origin/master` still `ffbabb5c`), so §122 stands. Divergence labels 525–534 were reserved for this branch; **none was taken** (no
SwiftUI behaviour differs: there is none to differ from). The human-checks group is **SI**.

**Status: LANDED — every agent-doable clause is built; the looks and Windows are owed** (group `SI`, §7). One lane, red first,
verified `ok: true`; the Record phase re-took the suite and the counts (§5).

## §0 Baseline

At `ffbabb5c`: **3970 tests in 3 suites**, 0 goldens, 247 typecheck guards, `Backends/SDL` baseline count not re-taken at the Record phase
(the branch's own reading is §4). Carried: `AS-G` (routing), `AS-M` (launch arguments are the app's recipe),
`AS-Q` (URLs before `App.init` dropped), `SV-H`, `CB-H` (a C callback off the main thread is pure), `WS-B`, `GA-L`.

## §1 What landed

- **`SingleInstance`** (`Backends/SDL/Sources/MetalUISDL/SingleInstance.swift`, trait `SDL`, class `M`): `claim(id:forwarding:configuration:)`
  returns `.primary(role)`, `.forwarded` or `.unavailable(Failure)`; `Configuration` (directory, connect and read timeouts 2 s,
  `raisesWindow`, `expectedPeerUID`). `SDLPlatform.Options.singleInstance` (default `nil`, mirrored in the trait-off stub) and
  `SDLPlatform.launchingSingleInstance(id:forwarding:options:) throws -> SDLPlatform?` (`nil` = forwarded, exit 0) (`SN-A`). No
  `Platform`/`PlatformWindow` requirement, no root-module declaration, so **no migration note, no inventory row, no census movement**
  (`SN-O`; `Backends/SDL` is outside the census, `GA-L`).
- **Transport** (`Backends/SDL/Sources/SDLBridge/SDLInstance.c`, `SDLBridge.h`, `SDLBridge.c`'s wake mapping): election and carrying are
  per user. Linux and macOS: `flock` on `msui-<hash>.lock` elects, a Unix socket `msui-<hash>.sock` carries, in `$XDG_RUNTIME_DIR`
  (else the user's temporary directory on macOS, else `/tmp/metalui-<uid>`), a real directory owned by the user with no group or other
  access; socket 0600, peer uid checked on both sides, a stale socket file under a free lock is replaced (`SN-C`). Windows: a **named
  semaphore** elects (amends `SN-D`'s mutex: a mutex is recursive on its owner thread, `SN-P` item 1) and a session-scoped named pipe
  carries, process SID checked (`SN-D`). The hash is SHA-256's first 16 hex digits of the id (pinned against Python's `hashlib`).
- **Wire** (`SN-E`): magic, count, length-prefixed UTF-8 strings, exact payload framing; limits 1024 strings, 32768 bytes a string, 1 MiB
  payload, no NUL, no ill-formed UTF-8, empty strings refused; a declared length over the limit allocates nothing; an ack follows
  the enqueue; a read deadline cuts a stalled client; a 64-message pending queue refuses the 65th.
- **Delivery** (`SN-G`, `SN-P` item 3): a C listener thread (pure, no Swift closure, no actor hop: `CB-H`) queues messages and pushes an
  SDL wake event; `pumpEvents()`/`waitForEvent` drain on the main actor into the existing `handleApplicationOpen` (the window-0
  drop's own parking and batching, so `AS-G` routing and `AS-Q`-style parking apply); one raise per drain
  that took any message (`SDL_RestoreWindow`, `SDL_RaiseWindow`, `SDL_FlashWindow` until focused; never a hidden window, `SN-H`).
- **Failure** (`SN-F`): a launch whose forward fails (`.unavailable`) runs as an independent instance rather than lose the document.
- **Docs**: `docs/packaging.md` "One instance on Linux and Windows" (recipe, API, transport, limits), `docs/testing.md` "A single-instance
  launch", human checks group SI (SI1–SI6), `docs/api-overview.md`, divergence 176 amended, `README.md`.
- **`SingleInstanceCheck`** (`Backends/SDL/Sources/SingleInstanceCheck`): the two-process executable (`primary`/`forward` modes).

## §2 Tests and guards

`Backends/SDL/Tests/MetalUISDLTests/SDLSingleInstanceTests.swift` (24 test declarations, the malformed-input one parameterised): ordered delivery (1), file-URL and relative-path
handling (2, 2b drive path), parking until a handler (3), stale socket replaced (4), eight concurrent claims elect one (4b, `SN-M`), a
SIGKILLed primary frees the role (5), a second process forwards and exits 0 (6), a held lock with no listener times out (7), malformed
messages refused and the listener keeps serving (8, parameterised), the limits' exact values (8b), an oversize length allocates nothing
(8c), a stalled client cut off (9), another user's peer rejected unread (10), socket and directory privacy (11), an overlong directory
named not truncated (12), the 65th message refused (13), ids independent (14), the id hash against `hashlib` (14b), raise policy
(15), the wake ends a blocked wait (16, a count not a time), a drop batch and a forward batch never interleave (17), the claim released
with the platform (18). **Guard 1.6b** (`Tests/MetalUITests/SDLTraitCompileGuards.swift`, `theTraitOffStubSpellsSingleInstance`): the
trait-off stub spells `SingleInstance`, `Options.singleInstance` and `launchingSingleInstance` and reports the trait's remedy.

**Red before green.** The tests were committed red (`00f5198a`): `error: cannot find type 'SingleInstance' in scope; error: extra
argument 'singleInstance' in call` on the `Backends/SDL` test build.

## §3 Mutations

Each applied alone on a committed tree, restored from a copy, full unfiltered suite, `git status --short` after. The Record phase
holds **the verifier's three re-takes by name**; the implementer's other mutations are listed from the test doc comments (each test names
the mutation it must redden) and their reddened-test lists rest on the implementer's report, not re-taken here.

| Mutation | Reddened (verifier's re-take) |
|---|---|
| M07 claim without `flock` (election removed) | 21 tests in all, among them `aSecondClaimForwardsItsArgumentsAndThePrimaryReceivesThemInOrder`, `eightConcurrentClaimsElectExactlyOnePrimary`, `aKilledPrimaryReleasesTheRole`, `aLockHeldWithNoListenerFallsBackToUnavailableWithinTheTimeout`, `aMalformedMessageIsRefusedAndTheListenerKeepsServing`, `aPeerOfAnotherUserIsRejectedUnread`, `theSixtyFifthPendingMessageIsRefused`, `theSocketAndItsDirectoryArePrivate`, `twoIdsAreTwoIndependentPrimaries`, `theClaimIsReleasedWhenThePlatformGoesAway`, `aSecondProcessForwardsAndExitsZero` |
| M14 skip the peer-uid check on the accepting side | `aPeerOfAnotherUserIsRejectedUnread` |
| M20 no `SDL_PushEvent` wake | `theWakeEventEndsABlockedWaitPromptly` |

Implementer's list, named by the doc comments and not re-taken: LIFO drain and per-connection append (1); no sender absolutising and
every string a path (2); drop when no handler (3); refuse when the socket file exists (4); no `flock` (4b, 5, the separating test is 4b);
exit 1 on `.forwarded` (6); retry for ever (7); raise each limit by one, lower each by one, replace the UTF-8/NUL check (8, 8b);
allocate the declared length first (8c); no read deadline (9); skip `lstat`, drop `umask` (11); truncate the path (12); an unbounded
queue (13); id ignored in the hash, a changed SHA-256 round constant (14, 14b); always raise, never raise (15); share one
accumulator (17); no unlink in `deinit` (18); guard 1.6b: drop `singleInstance` from the stub `Options`. Two findings from the
mutation round became commits: a refused raw write is an error, not SIGPIPE (the 1 MiB-limit mutant reddened by crashing, `bf261cea`),
and `SingleInstanceCheck` avoids the stdout global (`5d459b87`, guard 1.6b also refuses a stub missing a spelling).

## §4 Verification

- Root, native, unfiltered, after `swift package clean`: see §5. Default build `--build-tests`: 0 `warning:`.
- `Backends/SDL` on macOS: 30 + 215 passed. **Linux image** (`metalui-portable`, volume `metalui-sdl-build-single-instance`): 30 + 212 passed
  (every single-instance test runs there; none needs a display).
- Fourteen offscreen images: scene-identical, **0 px** against `ffbabb5c` (`Sources/` is untouched).
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; census unmoved (no root declaration).

## §5 Counts (Record phase, 2026-10-19)

**3971 tests in 4 suites**, 0 goldens, **248 typecheck guards** (247 + guard 1.6b; the guard count is the baseline plus the one new
guard, not re-grepped from the log), measured after `swift package clean`, `swift build --build-system native --build-tests` (0 `error:`, the only
`warning:` SwiftPM's deprecation notice) and `swift test --build-system native --no-parallel` unfiltered on a **locked screen**: the run reads exactly
the five `AppKitPresentationTests` sheet issues of `CI-AF` (`appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`,
`appKitCancelledDialogArrivesAsQueuedInput`, `appKitDismissPresentationEndsTheSheetAndAnswersNothing`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`)
and nothing else; `FR-J no-argument frame: succeeded=true`. 3970 + 1 (guard 1.6b's test). Census unmoved (no root declaration).

## §6 Hazards

- **Windows is compiled by nothing and run nowhere in this item**: the `_WIN32` branch of `SDLInstance.c` (semaphore, overlapped
  named pipe, SID scoping) was read, not built; the UTM VM was not tried. The Windows CI job on push and human check SI3 are the only
  cover; **watch that job before merge**. `advapi32` is linked by a `#pragma comment(lib, "advapi32.lib")` in `SDLInstance.c` (no manifest change; whether it resolves on the CI toolchain is itself unmeasured).
- A macOS test that creates an `SDLPlatform` arms `armMainRunLoopExitCheck()`; the test platform helper settles SDL's Cocoa report of the
  test process's own command line (an open event on the first pump) before it forwards.
- Known flake, unrelated: `theShaderLibraryLooksBesideTheExecutableThenTheSourceTree` failed once with a temp-directory permission error
  (`NSCocoaErrorDomain 513`, `SDLGPUShaderLibraryTests.swift:57`) in one verifier run; it passed in the baseline and in the Linux image.
- Wayland: `SDL_RaiseWindow` without an activation token may only flash the window (`SN-H`, check SI4).

## §7 Looks owed (group SI, not run: an agent cannot)

SI1 Linux X11 and Wayland with a `.desktop` `Exec=… %F`: the second document appears in the first window, no second window, the window raises
or flashes. SI2 `kill -9` the primary, relaunch, launch again. SI3 Windows 11 x64 and ARM64, Explorer, End Task, two sessions of one user.
SI4 Wayland activation. SI5 two users on one machine. SI6 a primary left eight hours (lock, suspend, resume).

## §8 Deferred (`SN-L`)

D-Bus `org.freedesktop.Application` activation, activation-token forwarding, working-directory and environment forwarding, a reply
channel, an AppKit twin: named in `SN-L` with reasons and owners. A Windows run of the transport: owner the CI job and check SI3.
