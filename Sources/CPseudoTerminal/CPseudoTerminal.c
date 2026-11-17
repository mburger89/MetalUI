#ifndef _WIN32

#ifdef __linux__
#define _GNU_SOURCE
#endif

#include "CPseudoTerminal.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <pthread.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/syscall.h>
#endif

#ifdef __APPLE__
#include <sys/ttycom.h>
#endif

#if defined(__linux__) && defined(__GLIBC__) && defined(__GLIBC_PREREQ)
#if __GLIBC_PREREQ(2, 34)
#define CPT_HAVE_POSIX_SPAWN 1
#endif
#endif
#ifdef __APPLE__
#define CPT_HAVE_POSIX_SPAWN 1
#endif

extern char **environ;

static int set_nonblock_cloexec(int fd) {
    int fl = fcntl(fd, F_GETFL);
    if (fl < 0 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) return -1;
    int fd_fl = fcntl(fd, F_GETFD);
    if (fd_fl < 0 || fcntl(fd, F_SETFD, fd_fl | FD_CLOEXEC) < 0) return -1;
    return 0;
}

int cpt_set_size(int master, unsigned short cols, unsigned short rows) {
    struct winsize ws;
    memset(&ws, 0, sizeof ws);
    ws.ws_col = cols;
    ws.ws_row = rows;
    return ioctl(master, TIOCSWINSZ, &ws);
}

pid_t cpt_foreground_group(int master) {
    return tcgetpgrp(master);
}

int cpt_pidfd_open(pid_t pid) {
#if defined(__linux__) && defined(SYS_pidfd_open)
    return (int)syscall(SYS_pidfd_open, pid, 0);
#else
    (void)pid;
    errno = ENOSYS;
    return -1;
#endif
}

#ifdef CPT_HAVE_POSIX_SPAWN
// The child starts life in `posix_spawn` with POSIX_SPAWN_SETSID, opens the
// slave as its first act (a session leader without a controlling tty acquires
// the tty it opens without O_NOCTTY) and duplicates it onto 0-2. Nothing else
// is inherited: Darwin's CLOEXEC_DEFAULT with `addinherit_np` for 0-2, glibc's
// `addclosefrom_np(3)`.
static int spawn_with_posix_spawn(const char *executable, char *const argv[], char *const envp[],
                                  const char *cwd, const char *slave, pid_t *pid) {
    posix_spawnattr_t attr;
    posix_spawn_file_actions_t fa;
    int rc = posix_spawnattr_init(&attr);
    if (rc) return rc;
    rc = posix_spawn_file_actions_init(&fa);
    if (rc) { posix_spawnattr_destroy(&attr); return rc; }

    sigset_t all, none;
    sigfillset(&all);
    sigdelset(&all, SIGKILL);
    sigdelset(&all, SIGSTOP);
    sigemptyset(&none);
    short flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
#ifdef __APPLE__
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
    rc = posix_spawnattr_setflags(&attr, flags);
    if (!rc) rc = posix_spawnattr_setsigdefault(&attr, &all);
    if (!rc) rc = posix_spawnattr_setsigmask(&attr, &none);
    if (!rc) rc = posix_spawn_file_actions_addopen(&fa, 0, slave, O_RDWR, 0);
    if (!rc) rc = posix_spawn_file_actions_adddup2(&fa, 0, 1);
    if (!rc) rc = posix_spawn_file_actions_adddup2(&fa, 0, 2);
#ifdef __APPLE__
    if (!rc) rc = posix_spawn_file_actions_addinherit_np(&fa, 0);
    if (!rc) rc = posix_spawn_file_actions_addinherit_np(&fa, 1);
    if (!rc) rc = posix_spawn_file_actions_addinherit_np(&fa, 2);
#else
    if (!rc) rc = posix_spawn_file_actions_addclosefrom_np(&fa, 3);
#endif
    if (!rc && cwd) rc = posix_spawn_file_actions_addchdir_np(&fa, cwd);
    if (!rc) rc = posix_spawn(pid, executable, &fa, &attr, argv, envp);

    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&attr);
    return rc;
}
#endif

// Everything between `fork` and `execve` is async-signal-safe: setsid, open,
// ioctl, dup2, close, close_range, sigaction, sigprocmask, chdir, execve,
// write, _exit. Arguments, the environment and the descriptor limit are
// prepared before the fork.
static int spawn_with_fork(const char *executable, char *const argv[], char *const envp[],
                           const char *cwd, const char *slave, pid_t *pid) {
    int errpipe[2];
    if (pipe(errpipe) < 0) return errno;
    // Move both ends above 2 (the parent may have 0-2 closed) and make them close-on-exec.
    for (int i = 0; i < 2; i++) {
        int moved = fcntl(errpipe[i], F_DUPFD_CLOEXEC, 10);
        int e = errno;
        close(errpipe[i]);
        if (moved < 0) { close(errpipe[1 - i]); return e; }
        errpipe[i] = moved;
    }
    long maxfd = sysconf(_SC_OPEN_MAX);
    if (maxfd < 0 || maxfd > 1 << 20) maxfd = 1 << 20;

    sigset_t all, old;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, &old);  // no handler runs in the child before exec
    pid_t child = fork();
    if (child < 0) {
        int e = errno;
        pthread_sigmask(SIG_SETMASK, &old, NULL);
        close(errpipe[0]); close(errpipe[1]);
        return e;
    }
    if (child == 0) {
        int fail = 0;
        if (setsid() < 0) { fail = errno; goto bail; }
        int fd = open(slave, O_RDWR);
        if (fd < 0) { fail = errno; goto bail; }
#ifdef TIOCSCTTY
        ioctl(fd, TIOCSCTTY, 0);  // already ours if the open acquired it; harmless then
#endif
        if (dup2(fd, 0) < 0 || dup2(fd, 1) < 0 || dup2(fd, 2) < 0) { fail = errno; goto bail; }
        if (fd > 2) close(fd);
        {
            // errpipe[1] is close-on-exec and stays open to report an exec failure.
            int keep = errpipe[1];
#if defined(__linux__) && defined(SYS_close_range)
            int ok = (keep <= 3 || syscall(SYS_close_range, 3u, (unsigned)keep - 1u, 0u) == 0)
                  && syscall(SYS_close_range, (unsigned)keep + 1u, ~0u, 0u) == 0;
            if (!ok)
#endif
            {
                for (long i = 3; i < maxfd; i++) if (i != keep) close((int)i);
            }
        }
        for (int s = 1; s < 32; s++) {
            if (s == SIGKILL || s == SIGSTOP) continue;
            struct sigaction sa;
            memset(&sa, 0, sizeof sa);
            sa.sa_handler = SIG_DFL;
            sigaction(s, &sa, NULL);
        }
        sigset_t none;
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        if (cwd && chdir(cwd) < 0) { fail = errno; goto bail; }
        execve(executable, argv, envp);
        fail = errno;
    bail:
        {
            ssize_t w = write(errpipe[1], &fail, sizeof fail);
            (void)w;
        }
        _exit(127);
    }
    pthread_sigmask(SIG_SETMASK, &old, NULL);
    close(errpipe[1]);
    int fail = 0;
    ssize_t n;
    do { n = read(errpipe[0], &fail, sizeof fail); } while (n < 0 && errno == EINTR);
    close(errpipe[0]);
    *pid = child;
    if (n == (ssize_t)sizeof fail) {
        int st;
        waitpid(child, &st, 0);
        return fail ? fail : ENOEXEC;
    }
    return 0;
}

void cpt_spawn(const char *executable, char *const argv[], char *const envp[],
               const char *cwd, unsigned short cols, unsigned short rows,
               int mechanism, cpt_result *out) {
    memset(out, 0, sizeof *out);
    out->master = -1;
    out->pid = -1;

    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || set_nonblock_cloexec(master) < 0 || grantpt(master) < 0 || unlockpt(master) < 0) {
        out->stage = CPT_OPEN_FAILED;
        out->code = errno;
        if (master >= 0) close(master);
        return;
    }
    char slave[PATH_MAX];
#ifdef __APPLE__
    char name[128];
    if (ioctl(master, TIOCPTYGNAME, name) < 0) {
        out->stage = CPT_OPEN_FAILED; out->code = errno; close(master); return;
    }
    strlcpy(slave, name, sizeof slave);
#else
    int pe = ptsname_r(master, slave, sizeof slave);
    if (pe != 0) {
        out->stage = CPT_OPEN_FAILED; out->code = pe; close(master); return;
    }
#endif
    // The size is set before the child exists so its first `stty size` is right. Darwin forgets a size
    // set on a pty nobody has opened, so the parent holds the slave open (no controlling tty taken)
    // until the child has its own.
    int hold = open(slave, O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (hold >= 0) cpt_set_size(hold, cols, rows);
    else cpt_set_size(master, cols, rows);

    int use_spawn = 0;
#ifdef CPT_HAVE_POSIX_SPAWN
    use_spawn = mechanism != CPT_FORK;
#endif
    pid_t pid = -1;
    int rc;
#ifdef CPT_HAVE_POSIX_SPAWN
    if (use_spawn) rc = spawn_with_posix_spawn(executable, argv, envp, cwd, slave, &pid);
    else
#endif
    rc = spawn_with_fork(executable, argv, envp, cwd, slave, &pid);
    if (hold >= 0) close(hold);
    if (rc != 0) {
        out->stage = CPT_SPAWN_FAILED;
        out->code = rc;
        close(master);
        return;
    }
    out->master = master;
    out->pid = pid;
    out->mechanism = use_spawn ? CPT_POSIX_SPAWN : CPT_FORK;
}

#endif
