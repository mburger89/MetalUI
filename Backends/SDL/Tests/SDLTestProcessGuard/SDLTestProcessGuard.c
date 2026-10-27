#include "SDLTestProcessGuard.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MUITG_DEFAULT_DEADLINE_SECONDS 600
#define MUITG_MAX_DEADLINE_SECONDS 86400

int muitg_parse_deadline_seconds(const char *value) {
    if (value == NULL || value[0] == '\0') return MUITG_DEFAULT_DEADLINE_SECONDS;
    char *end = NULL;
    errno = 0;
    long parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0') return MUITG_DEFAULT_DEADLINE_SECONDS;
    if (parsed < 0 || parsed > MUITG_MAX_DEADLINE_SECONDS) return MUITG_DEFAULT_DEADLINE_SECONDS;
    return (int)parsed;
}


#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

/* The Windows half (WG-B...WG-G). Nothing here was compiled on Windows by the author (WG-I). */

/* The UCRT marks `getenv` deprecated; read the Win32 block the constructor also writes (WG-F). Returns NULL
   when unset, the value otherwise (a value longer than the buffer reads as empty, which the parser treats as
   junk, the default). One static buffer: each result is used before the next call. */
static const char *muitg_env(const char *name) {
    static char buffer[128];
    DWORD length = GetEnvironmentVariableA(name, buffer, (DWORD)sizeof buffer);
    if (length == 0) return GetLastError() == ERROR_ENVVAR_NOT_FOUND ? NULL : "";
    return length < sizeof buffer ? buffer : "";
}

muitg_pid_t muitg_parent_pid(void) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32 entry;
    entry.dwSize = sizeof entry;
    DWORD self = GetCurrentProcessId();
    DWORD parent = 0;
    if (Process32First(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == self) { parent = entry.th32ParentProcessID; break; }
        } while (Process32Next(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return parent;
}

static int muitg_creation_time(HANDLE process, ULONGLONG *out) {
    FILETIME created, exited, kernel, user;
    if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return 0;
    ULARGE_INTEGER value;
    value.LowPart = created.dwLowDateTime;
    value.HighPart = created.dwHighDateTime;
    *out = value.QuadPart;
    return 1;
}

/* WG-C: the candidate's creation time is not later than ours. */
static int muitg_handle_started_before_us(HANDLE candidate) {
    ULONGLONG theirs, ours;
    if (!muitg_creation_time(candidate, &theirs)) return 0;
    if (!muitg_creation_time(GetCurrentProcess(), &ours)) return 0;
    return theirs <= ours;
}

int muitg_process_started_before_us(muitg_pid_t pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    if (process == NULL) return 0;
    int answer = muitg_handle_started_before_us(process);
    CloseHandle(process);
    return answer;
}

typedef struct {
    HANDLE parent;
    DWORD pollMilliseconds;
    void (*onOrphan)(void);
    void (*onPoll)(void);
} muitg_watch;

static DWORD WINAPI muitg_watch_main(LPVOID raw) {
    muitg_watch watch = *(muitg_watch *)raw;
    free(raw);
    for (;;) {
        DWORD result = WaitForSingleObject(watch.parent, watch.pollMilliseconds);
        int orphaned = result != WAIT_TIMEOUT; /* signalled, or a failed wait: do not guess alive */
        if (orphaned) {
            if (watch.onOrphan) watch.onOrphan();
        }
        if (watch.onPoll && !orphaned) watch.onPoll();
        if (orphaned) break;
    }
    CloseHandle(watch.parent);
    return 0;
}

static void muitg_spawn_detached(LPTHREAD_START_ROUTINE body, void *arg) {
    HANDLE thread = CreateThread(NULL, 0, body, arg, 0, NULL);
    if (thread == NULL) { free(arg); return; }
    CloseHandle(thread);
}

void muitg_watch_parent(muitg_pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void)) {
    /* WG-B: open here, in the caller, before any thread exists; never re-resolve the PID. */
    HANDLE parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)original);
    if (parent == NULL || !muitg_handle_started_before_us(parent)) {
        if (parent != NULL) CloseHandle(parent);
        if (onOrphan) onOrphan();
        return;
    }
    muitg_watch *watch = malloc(sizeof(muitg_watch));
    if (watch == NULL) { CloseHandle(parent); return; }
    watch->parent = parent;
    watch->pollMilliseconds = pollMilliseconds > 0 ? (DWORD)pollMilliseconds : 1;
    watch->onOrphan = onOrphan;
    watch->onPoll = onPoll;
    muitg_spawn_detached(muitg_watch_main, watch);
}

typedef struct {
    DWORD milliseconds;
    void (*onExpire)(void);
} muitg_expiry;

static DWORD WINAPI muitg_deadline_main(LPVOID raw) {
    muitg_expiry expiry = *(muitg_expiry *)raw;
    free(raw);
    Sleep(expiry.milliseconds);
    expiry.onExpire();
    return 0;
}

void muitg_start_deadline(int milliseconds, void (*onExpire)(void)) {
    if (milliseconds <= 0 || onExpire == NULL) return;
    muitg_expiry *expiry = malloc(sizeof(muitg_expiry));
    if (expiry == NULL) return;
    expiry->milliseconds = (DWORD)milliseconds;
    expiry->onExpire = onExpire;
    muitg_spawn_detached(muitg_deadline_main, expiry);
}

/* ---- the constructor's own callbacks ---- */

/* WG-D: the handle API and TerminateProcess; _exit would run the loader's detach path. */
static void muitg_die(const char *message, UINT code) {
    DWORD written;
    HANDLE err = GetStdHandle(STD_ERROR_HANDLE);
    if (err != NULL && err != INVALID_HANDLE_VALUE) WriteFile(err, message, (DWORD)strlen(message), &written, NULL);
    TerminateProcess(GetCurrentProcess(), code);
    for (;;) Sleep(1000);
}

static void muitg_orphaned(void) {
    muitg_die("error: the process that started this test run is gone; exiting (TL-E)\n", 70);
}

static int muitg_deadline_seconds_in_force = MUITG_DEFAULT_DEADLINE_SECONDS;
static int muitg_armed_deadline = 0;

static void muitg_deadline_expired(void) {
    char message[320];
    snprintf(message, sizeof message,
             "error: the test process ran past its deadline (METALUI_TEST_DEADLINE_SECONDS=%d); a blocked wait? (TL-D)\n",
             muitg_deadline_seconds_in_force);
    muitg_die(message, 71);
}

static void muitg_arm_deadline(int milliseconds) {
    muitg_start_deadline(milliseconds, muitg_deadline_expired);
    muitg_armed_deadline = milliseconds;
}

int muitg_constructor_armed_deadline_milliseconds(void) {
    return muitg_armed_deadline;
}

static void muitg_constructor_body(void) {
    /* WG-F: SDL's CRT signal(SIGINT) handler would turn Ctrl+C into an event nobody reads. */
    if (muitg_env("SDL_NO_SIGNAL_HANDLERS") == NULL) {
        _putenv_s("SDL_NO_SIGNAL_HANDLERS", "1");
        SetEnvironmentVariableA("SDL_NO_SIGNAL_HANDLERS", "1");
    }
    muitg_pid_t parent = muitg_parent_pid();
    if (parent != 0) muitg_watch_parent(parent, 500, muitg_orphaned, NULL);
    int seconds = muitg_parse_deadline_seconds(muitg_env("METALUI_TEST_DEADLINE_SECONDS"));
    muitg_deadline_seconds_in_force = seconds;
    if (seconds > 0) muitg_arm_deadline(seconds * 1000);
}

/* WG-G: clang lowers the attribute to a .CRT$XCU initializer; MSVC proper needs the section by hand. */
#if defined(__clang__) || defined(__GNUC__)
__attribute__((constructor))
static void muitg_constructor(void) { muitg_constructor_body(); }
#else
static void muitg_constructor(void) { muitg_constructor_body(); }
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU")) static void (*muitg_constructor_pointer)(void) = muitg_constructor;
#endif

#else

#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

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

static void muitg_sleep_ms(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {}
}

typedef struct {
    muitg_pid_t original;
    int pollMilliseconds;
    void (*onOrphan)(void);
    void (*onPoll)(void);
} muitg_watch;

static void *muitg_watch_main(void *raw) {
    muitg_watch watch = *(muitg_watch *)raw;
    free(raw);
    for (;;) {
        muitg_sleep_ms(watch.pollMilliseconds);
        int orphaned = getppid() != (pid_t)watch.original;
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

muitg_pid_t muitg_parent_pid(void) {
    return getppid();
}

void muitg_watch_parent(muitg_pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void)) {
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
static int muitg_armed_deadline = 0;

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

static void muitg_deadline_expired(void);

/* The constructor's one arming site; records what it armed for the read-back (TL-K). */
static void muitg_arm_deadline(int milliseconds) {
    muitg_start_deadline(milliseconds, muitg_deadline_expired);
    muitg_armed_deadline = milliseconds;
}

int muitg_constructor_armed_deadline_milliseconds(void) {
    return muitg_armed_deadline;
}

__attribute__((constructor))
static void muitg_constructor(void) {
    /* TL-B: SDL's own SIGINT/SIGTERM handlers turn the signal into an event nobody reads. */
    setenv("SDL_NO_SIGNAL_HANDLERS", "1", 0);
    muitg_watch_parent(muitg_parent_pid(), 500, muitg_orphaned, NULL);
    int seconds = muitg_parse_deadline_seconds(getenv("METALUI_TEST_DEADLINE_SECONDS"));
    muitg_deadline_seconds_in_force = seconds;
    if (seconds > 0) muitg_arm_deadline(seconds * 1000);
}

#endif
