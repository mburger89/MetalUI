// POSIX pseudo-terminal shims for MetalUITerminal (ruling TRM-K). The whole
// header is empty on Windows: ConPTY lives in a later phase.
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
#endif
