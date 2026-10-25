#include "SDLTestProcessGuard.h"

#if !defined(_WIN32)

#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define MUITG_DEFAULT_DEADLINE_SECONDS 600
#define MUITG_MAX_DEADLINE_SECONDS 86400

static void muitg_sleep_ms(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {}
}

int muitg_parse_deadline_seconds(const char *value) {
    if (value == NULL || value[0] == '\0') return MUITG_DEFAULT_DEADLINE_SECONDS;
    char *end = NULL;
    errno = 0;
    long parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0') return MUITG_DEFAULT_DEADLINE_SECONDS;
    if (parsed < 0 || parsed > MUITG_MAX_DEADLINE_SECONDS) return MUITG_DEFAULT_DEADLINE_SECONDS;
    return (int)parsed;
}

typedef struct {
    pid_t original;
    int pollMilliseconds;
    void (*onOrphan)(void);
    void (*onPoll)(void);
} muitg_watch;

static void *muitg_watch_main(void *raw) {
    muitg_watch watch = *(muitg_watch *)raw;
    free(raw);
    for (;;) {
        muitg_sleep_ms(watch.pollMilliseconds);
        int orphaned = getppid() != watch.original;
        if (orphaned) {
            if (watch.onOrphan) watch.onOrphan();
        }
        if (watch.onPoll) watch.onPoll();
        if (orphaned) return NULL;
    }
}

static void muitg_spawn_detached(void *(*body)(void *), void *arg) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    if (pthread_create(&thread, &attr, body, arg) != 0) free(arg);
    pthread_attr_destroy(&attr);
}

void muitg_watch_parent(pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void)) {
    muitg_watch *watch = malloc(sizeof(muitg_watch));
    if (watch == NULL) return;
    watch->original = original;
    watch->pollMilliseconds = pollMilliseconds > 0 ? pollMilliseconds : 1;
    watch->onOrphan = onOrphan;
    watch->onPoll = onPoll;
    muitg_spawn_detached(muitg_watch_main, watch);
}

typedef struct {
    int milliseconds;
    void (*onExpire)(void);
} muitg_expiry;

static void *muitg_deadline_main(void *raw) {
    muitg_expiry expiry = *(muitg_expiry *)raw;
    free(raw);
    muitg_sleep_ms(expiry.milliseconds);
    expiry.onExpire();
    return NULL;
}

void muitg_start_deadline(int milliseconds, void (*onExpire)(void)) {
    if (milliseconds <= 0 || onExpire == NULL) return;
    muitg_expiry *expiry = malloc(sizeof(muitg_expiry));
    if (expiry == NULL) return;
    expiry->milliseconds = milliseconds;
    expiry->onExpire = onExpire;
    muitg_spawn_detached(muitg_deadline_main, expiry);
}

/* ---- the constructor's own callbacks ---- */

static void muitg_orphaned(void) {
    static const char message[] =
        "error: the process that started this test run is gone; exiting (TL-E)\n";
    (void)!write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(70);
}

static int muitg_deadline_seconds_in_force = MUITG_DEFAULT_DEADLINE_SECONDS;

#if defined(__APPLE__)
static void muitg_run_sample(char *path, size_t pathSize) {
    const char *tmp = getenv("TMPDIR");
    if (tmp == NULL || tmp[0] == '\0') tmp = "/tmp";
    snprintf(path, pathSize, "%s%smetalui-hang-%d.txt", tmp, tmp[strlen(tmp) - 1] == '/' ? "" : "/", (int)getpid());
    char pidText[32];
    snprintf(pidText, sizeof pidText, "%d", (int)getpid());
    char *argv[] = {"/usr/bin/sample", pidText, "3", "-file", path, NULL};
    pid_t child;
    if (posix_spawn(&child, "/usr/bin/sample", NULL, NULL, argv, environ) != 0) {
        path[0] = '\0';
        return;
    }
    /* Best effort, bounded by 10 s (TL-H). */
    for (int waited = 0; waited < 100; waited++) {
        int status;
        pid_t done = waitpid(child, &status, WNOHANG);
        if (done == child || done == -1) return;
        muitg_sleep_ms(100);
    }
    kill(child, SIGKILL);
    int status;
    waitpid(child, &status, 0);
}
#endif

static void muitg_deadline_expired(void) {
    char path[PATH_MAX];
    path[0] = '\0';
#if defined(__APPLE__)
    muitg_run_sample(path, sizeof path);
#endif
    char message[PATH_MAX + 256];
    snprintf(message, sizeof message,
             "error: the test process ran past its deadline (METALUI_TEST_DEADLINE_SECONDS=%d); a blocked wait?%s%s (TL-D)\n",
             muitg_deadline_seconds_in_force, path[0] ? " sample: " : "", path);
    (void)!write(STDERR_FILENO, message, strlen(message));
    _exit(71);
}

__attribute__((constructor))
static void muitg_constructor(void) {
    /* TL-B: SDL's own SIGINT/SIGTERM handlers turn the signal into an event nobody reads. */
    setenv("SDL_NO_SIGNAL_HANDLERS", "1", 0);
    muitg_watch_parent(getppid(), 500, muitg_orphaned, NULL);
    int seconds = muitg_parse_deadline_seconds(getenv("METALUI_TEST_DEADLINE_SECONDS"));
    muitg_deadline_seconds_in_force = seconds;
    if (seconds > 0) muitg_start_deadline(seconds * 1000, muitg_deadline_expired);
}

#endif
