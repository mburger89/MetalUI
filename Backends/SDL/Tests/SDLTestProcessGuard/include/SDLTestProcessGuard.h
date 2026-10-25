#ifndef SDL_TEST_PROCESS_GUARD_H
#define SDL_TEST_PROCESS_GUARD_H

#if !defined(_WIN32)
#include <sys/types.h>

/// Test-only process guard of `MetalUISDLTests` (rulings TL-B, TL-D, TL-E, item HG). Compiled out
/// under `_WIN32` (TL-I): every function is then absent. A constructor runs before `main` in the
/// test helper and in every exit-test child of the same binary; Swift calls the `muitg_` seams.

/// The deadline in seconds `value` names: nil, empty, unparsable, negative or over a day give the
/// default 600; "0" gives 0 (disabled). Pure.
int muitg_parse_deadline_seconds(const char *value);

/// Starts one detached thread that polls `getppid()` every `pollMilliseconds` and calls `onOrphan`
/// once when it differs from `original`, then returns. `onPoll` (may be NULL) runs after each check.
void muitg_watch_parent(pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void));

/// Starts one detached thread that calls `onExpire` once after `milliseconds` (> 0), then returns.
void muitg_start_deadline(int milliseconds, void (*onExpire)(void));

/// The deadline in milliseconds the constructor armed before `main`, or 0 when it armed none
/// (`METALUI_TEST_DEADLINE_SECONDS=0`). Read-back seam of TL-K.
int muitg_constructor_armed_deadline_milliseconds(void);

#endif

#endif
