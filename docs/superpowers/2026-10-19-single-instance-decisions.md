# Single-instance launch on SDL — decisions

Rulings for item S7 (found answering MetalCreator's SDL-port gap 5; divergence 176 carries the open-document half). Spec:
[`specs/2026-10-19-single-instance-design.md`](specs/2026-10-19-single-instance-design.md). Record: `../record/122-single-instance.md`
(written at the Record phase). Branch `feat/single-instance` from `ffbabb5c`. Reserved divergence labels 525-534: **none taken**
(MetalUI-only, class `M`; SwiftUI has no cross-process API, and macOS LaunchServices already does this for a bundled app,
probe `docs/probes/appkit-launch-arguments-open.swift` arm `A6`).

Prefix **`SN-`**, lettered. **Next unused: `SN-M`.** (Moves in the commit that appends a ruling.)

**Carried.** `AS-G` (routing: key window's handler, else first window with one, else `App.onOpenURL`; never a new window), `AS-M`
(launch arguments are the app's recipe), `AS-Q` (URLs before `App.init` are dropped), `SV-H` (the SDL loop drains the main queue),
`CB-H` (a C callback off the main thread is pure: no Swift closure, no actor hop), `WS-B` (hidden windows), `PX-I`/`GA-L`
(`Backends/SDL` outside the census), `HT-X` 1 (a new platform requirement owes the headless platform an answer: **none is added**).

## SN-A - API: a claim made before the platform, passed in `SDLPlatform.Options`; no seam change

**Ruling.**
1. `SingleInstance` (public, `MetalUISDL`, class `M`): `static func claim(id: String, forwarding arguments: [String],
   configuration: Configuration = .default) -> Outcome`. `Outcome` is `.primary(SingleInstance)`, `.forwarded`,
   `.unavailable(SingleInstance.Failure)`. A `.primary` value is the held role: a final class, `Sendable`, `Hashable` by identity,
   whose `deinit` releases the lock, stops the listener and removes the socket.
2. `SDLPlatform.Options.singleInstance: SingleInstance?` (default `nil`; `Options` stays `Sendable, Hashable`). With a value,
   `SDLPlatform.init(options:)` attaches the listener to the loop. The trait-off stub declares the same names (guard 1.6).
3. Convenience for the one-line launch: `SDLPlatform.launchingSingleInstance(id:forwarding:options:) throws -> SDLPlatform?` -
   returns `nil` for `.forwarded` (the caller `exit(0)`s; a library never exits the process), a platform otherwise (an
   `.unavailable` claim runs as an independent instance: SN-F).
4. **No `Platform` or `PlatformWindow` requirement is added.** Delivery is `Platform.onOpenURLs`, so `App`, `AS-G` routing,
   parking and the headless platform are untouched; no migration note, no root public declaration, no inventory row.
5. The app decides **which** arguments are documents (`AS-G` item 6: MetalUI reads no `CommandLine.arguments`); the recipe filters with
   `FileManager.fileExists` exactly as `docs/packaging.md` does. A second launch with nothing to forward still raises the primary.
6. The primary's own launch arguments stay `App.open(_:)` (AS-M); `claim` does not deliver them.

**Rejected.** A new `Platform` requirement (every conformer and fake pays for an SDL-only feature); an `App.singleInstance(id:)`
(`App` is portable and the role must be taken before windows exist, before `App.init`); a free function that calls `exit` (a
library ending the process, untestable).

**Cost if wrong.** One public type and one `Options` field in a backend outside the census.

## SN-B - macOS: the API exists in the SDL build only; AppKit apps need nothing

AppKit has no `SingleInstance` (LaunchServices already forwards `application(_:open:)` to a running bundled app, probe `A6`). An SDL
build on macOS (the `Backends/SDL` tests, `MetalUISDLDemo`) uses the same Unix-socket transport as Linux, which is what lets every
transport test run on the development Mac. `swift run` of an AppKit executable is not single-instance by design (it is not a
bundle).

**Cost if wrong.** None to the API; a macOS user wanting it on the AppKit platform writes a bundle.

## SN-C - Linux and macOS transport: `flock` on a lock file elects, a filesystem Unix socket carries

**Finding.** Election by `bind` alone cannot tell a live primary from a crashed one's leftover file without a connect-then-unlink race
(two starters both see ECONNREFUSED, both unlink, both bind). A held `flock` is released by the kernel when the process dies, so
the lock is the truth and the socket only a mailbox.

**Ruling.**
1. Names: `<dir>/msui-<h>.lock` and `<dir>/msui-<h>.sock`, `h` = the first 16 hex digits of SHA-256 over the id's UTF-8 (a short fixed
   name: `sun_path` is 104 bytes on macOS, 108 on Linux; an id is never in the path, so any id is legal; an empty id is refused).
2. A claim opens the lock file (`O_CLOEXEC|O_NOFOLLOW|O_CREAT`, 0600) and `flock(LOCK_EX|LOCK_NB)`. **Won**: unlink any old
   `.sock` (it is stale by definition: nobody holds the lock), `bind` at umask-restricted 0600 (a `umask(0177)` section around the
   bind, restored after), `listen(8)`, start the listener thread. **Lost**: connect to `.sock`, send, await the ack (SN-E).
3. Directory: `$XDG_RUNTIME_DIR` when set; else on macOS `NSTemporaryDirectory()` (per user); else `/tmp/metalui-<uid>` created 0700.
   Whichever, the directory must be a real directory (`lstat`, not a symlink), owned by the effective uid, mode with no group or
   other bits (`& 0077 == 0`); otherwise `.unavailable(.insecureDirectory)`. The path (directory + 25 bytes) must fit `sun_path` or
   `.unavailable(.pathTooLong)` - named, never a truncated bind.
4. The loser that finds the lock held but the connection refused or the socket absent (a primary between `flock` and `listen`)
   retries every 50 ms up to the configuration's `connectTimeout` (default 2 s); then `.unavailable(.noListener)`.
5. The listener closes the lock and socket fds `CLOEXEC`, so a child the app spawns never inherits the role.

**Rejected.** An abstract socket (Linux-only, no macOS twin, no filesystem permission, any user in the network namespace may squat
the name; peer credentials would still be needed); D-Bus `org.freedesktop.Application.Open` (needs a bus, a session, a `.desktop`
file naming the bus name and a D-Bus client: a dependency larger than the feature; an app that already ships a `.desktop` with
`DBusActivatable` can add it later, SN-L); a PID file (stale-PID reuse); connect-probe-then-unlink election (the race above).

**Cost if wrong.** A filesystem socket needs a writable private directory; on a system with neither `XDG_RUNTIME_DIR` nor a usable
`/tmp` the claim answers `.unavailable` and the app runs as today.

## SN-D - Windows transport: a named mutex elects, a named pipe carries (compiled in CI, not run locally)

**Ruling.** In `SDLBridge.c` under `_WIN32`: mutex `Local\MetalUI-<h>-<s>` (`Local\` is the logon session's namespace: per user session,
never cross-user) and pipe `\\.\pipe\MetalUI-<h>-<s>` where `s` is a hash of the user's SID string (a second user cannot guess it
into collision with a squat of the first, and a same-named pipe from another user fails the client's check below). The primary
creates the pipe with `FILE_FLAG_FIRST_PIPE_INSTANCE` (a squatter makes this fail: `.unavailable(.insecure)`), `PIPE_REJECT_REMOTE_CLIENTS`,
byte mode, an explicit security descriptor granting only the current user's SID `GENERIC_READ|GENERIC_WRITE`, one instance served
serially by overlapped `ConnectNamedPipe` on the listener thread (wakeable by an event for shutdown). The client, before writing,
opens the pipe `SECURITY_IDENTIFICATION`, calls `GetNamedPipeServerProcessId`, opens that process's token and compares its user SID to
its own; mismatch is `.unavailable(.insecure)`. A mutex abandoned by a crashed primary (`WAIT_ABANDONED`) is taken over. Framing, limits,
ack and queue are the shared C code (SN-E), so only the OS calls differ.

**Verification.** CI's Windows jobs build it; the UTM VM runs the subprocess test only if `ssh metalui-win` answers, in an
interactive-session task (the SDL windows rule). **No local run is claimed**: human check SI3.

**Cost if wrong.** A Windows-only build or ACL defect, reachable only with the trait and the option; the `.unavailable` path leaves the
app working.

## SN-E - Wire format, limits, ack, the listener

**Ruling.** One connection carries one message: `"MSI1"` (4 bytes) | `u32 BE count` | `count` x (`u32 BE length` | UTF-8 bytes), then the
listener answers one byte: `0x06` (queued) or `0x15` (refused). Limits: count <= 1024, each string 1..=32768 bytes, total frame
<= 1 MiB; no NUL byte, valid UTF-8 (a NUL or an ill-formed sequence is refused, never repaired); an empty string is refused. The
reader enforces them **before allocating** (length checked against the remaining budget), reads with a 2 s deadline for the whole
message (`poll` / overlapped timeout; configuration `readTimeout` so a test shortens it), serves **one connection at a time** (a
stalled client costs at most the timeout, and cannot starve a good one beyond it), closes after the ack, and never executes, expands,
resolves or stats anything it received. **Peer check on accept**: `getpeereid`/`SO_PEERCRED` uid equals the effective uid or the
connection is closed unread (a configuration hook `expectedPeerUID` lets a test prove it). The queue holds at most 64 messages;
the 65th is `0x15`, so a flood cannot grow memory. Strings are carried verbatim: **the sender makes relative paths absolute against its own
cwd** (`claim` does this for any string that is not `scheme://` and is not already absolute, because the primary's cwd is
unrelated).

**Why** one connection, one message: framing needs no stream state, a half-written message is simply dropped and the ack tells the
sender whether it must fall back. The 2 s ack wait is the sender's, so a hung primary costs the second launch two seconds, then it
runs on its own (SN-F).

**Cost if wrong.** A format change before 1.0 is a one-line magic bump.

## SN-F - A failure to forward runs the second instance, never loses the document

`.unavailable(.noListener | .refused | .insecureDirectory | .pathTooLong | .insecure | .io(errno))`: the app decides; `launchingSingleInstance`
returns a platform and the instance runs normally (two windows, as today). A second instance that dropped the user's document because the
primary was wedged would be worse than a second window. `.refused` (NAK: queue full or malformed) also falls back.

## SN-G - Delivery: C listener thread, queue, SDL wake, drained on the main actor

**Ruling.** The listener is a C thread (`mui_instance_*`) that owns the socket, validates (SN-E) and appends to a mutex-guarded queue,
then `SDL_PushEvent`s a user wake event (thread-safe, `CB-H`: no Swift closure or actor hop off the main thread). Messages that arrive
before the platform exists wait in the queue (bounded, SN-E). `SDLPlatform.run` drains the queue once per iteration beside
`drainMainQueue()` (and the wake event makes the blocked `mui_wait_event` return at once) and for each message calls the existing
`handleApplicationOpen(strings)`: strings with a URL scheme pass as is, others become file URLs through
`SDLWindow.fileURLString(fromPath:)` (what `AS-G` item 5's drop path does), then `onOpenURLs` or park. **Order** is connection order, batch
by batch, never interleaved with a window-0 drop in the middle of its `DROP_COMPLETE` batch (separate lists). With no handler the
batch parks (`AS-Q` unchanged: `App.init` installs the handler; a batch delivered before a window with a handler goes to
`App.onOpenURL` or is dropped by `App.open`, divergence 176).

**Rejected.** `DispatchQueue.main.async` from the thread (up to 250 ms latency when the loop blocks in `mui_wait_event`; a Swift closure
off-actor); a `Task { @MainActor }` (does not run in the loop's synchronous top-level, `SV-H`).

## SN-H - Raise the primary, within each platform's limits

**Ruling.** After a delivered (or empty) message the platform raises one window: the key window, else the lowest-id open one, never
with `Options.hidesWindows`. `SDL_RestoreWindow` if minimised, then `SDL_RaiseWindow`; if the window is not key afterwards (read on the next
event pass), `SDL_FlashWindow(SDL_FLASH_UNTIL_FOCUSED)`. **Limits stated, not fought**: Windows grants foreground only to a process
that recently received input (the second instance does, the primary may not: flash is the fallback); Wayland allows activation only with
an `xdg-activation` token. SDL3 honours `XDG_ACTIVATION_TOKEN` in *its own* environment only, so forwarding the second instance's token
is **not built** (SN-L); X11 honours the raise under most window managers; macOS (SDL build) activates the app. A claim option
`raisesWindow` (default `true`) turns it off. A test substitutes the raise (`raiseWindow` closure, in the manner of `showWindow`).

## SN-I - What is never done

No command, no `exec`, no shell, no path existence check, no file read, no expansion (`~`, `$VAR`, globs) in the primary; the forwarded strings reach
only `onOpenURLs`, which the app already treats as untrusted input (`AS-G`). No network socket, no TCP loopback (any local user can
connect to one). No second instance outliving a `.forwarded` result: the caller exits.

## SN-J - Lifecycle of the role

The primary role is held by the `SingleInstance` object. `SDLPlatform` retains it for its life (via `Options`); the listener stops, the socket file is
unlinked and the lock closed in `deinit` and at normal process exit through the platform's `stop` path; **a crash leaves the socket file
and no lock**, which the next claim treats as stale (SN-C item 2). A primary whose last window closed but whose loop still runs keeps the role (the
app decides when it ends; `AS-C`).

## SN-K - Tests are in `Backends/SDL`, drive a real socket in a temporary private directory, and one real second process

`claim(…, configuration: .init(directory:))` takes the directory so a test never touches `XDG_RUNTIME_DIR`. Subprocess cases use a new
executable `SingleInstanceCheck` (modes `primary`, `forward`), launched like `MainQueueDrainCheck`; every test creating an `SDLPlatform` arms
`armMainRunLoopExitCheck()`. The Linux image runs all of it (no window needed: delivery is tested through `onOpenURLs`, the raise through the stub).

## SN-L - Not built, with owners

D-Bus activation (`org.freedesktop.Application`; owner: none, needs a client dependency); forwarding an `xdg-activation` token or
`DESKTOP_STARTUP_ID` (owner: the Wayland check SI4); forwarding the second instance's working directory or environment (an app that needs it
sends it as an argument); a reply channel from the primary (the ack is one byte); a many-message session; macOS `NSAppleEvent` parity for the
AppKit platform (LaunchServices already does it); a Windows `WM_COPYDATA` alternative (rejected: needs a hidden message window SDL does not expose).
