// Pseudo-terminal shims for MetalUITerminal: POSIX (ruling TRM-K) and, under
// _WIN32, ConPTY (ruling TRM-AX). Each half is empty on the other's platforms.
#ifndef CPSEUDOTERMINAL_H
#define CPSEUDOTERMINAL_H

#ifndef _WIN32

#include <sys/types.h>

/// Which spawn mechanism to use.
enum {
    CPT_AUTO = 0,         ///< posix_spawn where it is sound on this platform, else fork
    CPT_POSIX_SPAWN = 1,  ///< posix_spawn only
    CPT_FORK = 2          ///< the async-signal-safe fork path only
};

/// Where a spawn stopped.
enum {
    CPT_OK = 0,
    CPT_OPEN_FAILED = 1,   ///< posix_openpt, grantpt, unlockpt or ptsname failed
    CPT_SPAWN_FAILED = 2   ///< the child could not be created or could not exec
};

typedef struct {
    int master;      ///< the master fd: non-blocking, close-on-exec
    pid_t pid;       ///< the child, a session leader whose controlling tty is the pty
    int stage;       ///< CPT_OK, CPT_OPEN_FAILED or CPT_SPAWN_FAILED
    int code;        ///< errno of the failing call
    int mechanism;   ///< CPT_POSIX_SPAWN or CPT_FORK: the one that ran
} cpt_result;

/// Opens a pty and starts `executable` on its slave as a new session leader.
/// Only fds 0-2 reach the child. `argv` and `envp` are NULL-terminated.
void cpt_spawn(const char *executable, char *const argv[], char *const envp[],
               const char *cwd, unsigned short cols, unsigned short rows,
               int mechanism, cpt_result *out);

/// TIOCSWINSZ on the master. Returns 0, or -1 with errno.
int cpt_set_size(int master, unsigned short cols, unsigned short rows);

/// The foreground process group of the pty, or -1.
pid_t cpt_foreground_group(int master);

/// A pidfd for `pid` (Linux 5.3+), or -1 with errno (ENOSYS elsewhere).
int cpt_pidfd_open(pid_t pid);

#endif
#ifdef _WIN32

#include <stddef.h>
#include <stdint.h>

/// What a callback reports.
#define CPW_EVENT_READABLE 0   ///< output is buffered or the stream ended
#define CPW_EVENT_EXITED 1     ///< the child ended; `value` is its exit code
#define CPW_EVENT_RELEASED 2   ///< teardown finished: no callback follows, release the context

/// Called from a thread-pool thread, never with a lock of the engine held. `value` is the exit code for
/// CPW_EVENT_EXITED and, for CPW_EVENT_RELEASED, 1 when every teardown step finished in time.
typedef void (*cpw_callback)(void *context, int event, int32_t value);

/// Where a spawn stopped.
enum {
    CPW_OK = 0,
    CPW_OPEN_FAILED = 1,    ///< a pipe or the pseudo console could not be created
    CPW_SPAWN_FAILED = 2,   ///< the child could not be created
    CPW_UNSUPPORTED = 3     ///< this Windows has no ConPTY (before 10 1809)
};

typedef struct cpw_pty cpw_pty;

typedef struct {
    cpw_pty *pty;
    int stage;           ///< CPW_OK, CPW_OPEN_FAILED, CPW_SPAWN_FAILED or CPW_UNSUPPORTED
    uint32_t code;       ///< GetLastError (or the HRESULT) of the failing call
    uint32_t pid;
} cpw_result;

/// Starts `application` (a full path, or a bare name searched on PATH) on a new pseudo console.
/// `commandLine` is mutable and NUL-terminated; `environment` is a sorted block ending in two
/// NULs; `cwd` is NUL-terminated. All UTF-16. `callback` runs with `context` for the pty's life.
void cpw_spawn(const uint16_t *application, uint16_t *commandLine, const uint16_t *environment,
               const uint16_t *cwd, unsigned short cols, unsigned short rows,
               cpw_callback callback, void *context, cpw_result *out);

/// Copies buffered output: bytes copied (> 0), 0 when none, -1 at end of stream with nothing left.
long cpw_read(cpw_pty *pty, void *buffer, size_t capacity);
/// Nonzero when output is buffered or the stream has ended (a read would not return 0).
int cpw_available(cpw_pty *pty);
/// Queues bytes for the child; returns at once, never drops.
void cpw_write(cpw_pty *pty, const void *bytes, size_t count);
/// ResizePseudoConsole.
void cpw_resize(cpw_pty *pty, unsigned short cols, unsigned short rows);
/// TerminateJobObject: ends the child and everything it started.
void cpw_terminate(cpw_pty *pty);
/// Starts teardown, which finishes on its own thread; the pty must not be touched afterwards.
void cpw_close(cpw_pty *pty);

#endif
#endif
