#ifndef SDL_TEST_PROCESS_GUARD_H
#define SDL_TEST_PROCESS_GUARD_H

#if defined(_WIN32)
/* A DWORD, spelled without <windows.h> so the header stays cheap to import. */
typedef unsigned long muitg_pid_t;
#else
#include <sys/types.h>
typedef pid_t muitg_pid_t;
#endif

/// Test-only process guard of `MetalUISDLTests` (rulings TL-B, TL-D, TL-E, item HG; the Windows
/// half WG-B...WG-G, item WG). A constructor runs before `main` in the test helper and in every
/// exit-test child of the same binary; Swift calls the `muitg_` seams. POSIX decides an orphan from
/// `getppid()`; Windows waits on a handle to the parent opened at start (it never reparents).

/// The deadline in seconds `value` names: nil, empty, unparsable, negative or over a day give the
/// default 600; "0" gives 0 (disabled). Pure.
int muitg_parse_deadline_seconds(const char *value);

/// The id of this process's parent: `getppid()`, or on Windows the Toolhelp snapshot's answer;
/// 0 when unanswerable (WG-B).
muitg_pid_t muitg_parent_pid(void);

/// Starts one detached thread that watches `original` and calls `onOrphan` once when it is no longer
/// this process's parent, then returns. POSIX polls `getppid()` every `pollMilliseconds`; Windows opens
/// the process synchronously, here, and calls `onOrphan` at once (before returning) when it cannot be
/// opened or started after this process, else waits on the handle (WG-B). `onPoll` (may be NULL)
/// runs after each unsignalled wait or check.
void muitg_watch_parent(muitg_pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void));

/// Starts one detached thread that calls `onExpire` once after `milliseconds` (> 0), then returns.
void muitg_start_deadline(int milliseconds, void (*onExpire)(void));

/// The deadline in milliseconds the constructor armed before `main`, or 0 when it armed none
/// (`METALUI_TEST_DEADLINE_SECONDS=0`). Read-back seam of TL-K.
int muitg_constructor_armed_deadline_milliseconds(void);

#if defined(_WIN32)
/// Nonzero when process `pid` can be opened and its creation time is not later than this process's:
/// the PID-reuse guard of WG-C. 0 when it cannot be opened or started after us.
int muitg_process_started_before_us(muitg_pid_t pid);
#endif

#endif
