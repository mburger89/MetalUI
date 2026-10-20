#if !defined(_GNU_SOURCE) && defined(__linux__)
#define _GNU_SOURCE 1
#endif
#include "SDLBridge.h"
/* Single-instance launch (item S7, rulings SN-A..SN-P): the transport a second
   launch forwards its arguments over. Compiled only under the `SDL` trait, like
   SDLBridge.c. The election is a flock (Unix) or a named semaphore (Windows)
   that the kernel releases when the holder dies, so the lock is the truth and
   the socket or pipe only a mailbox; the listener is a C thread that validates,
   queues and pushes one SDL wake event, so no Swift code runs off the main
   thread (CB-H). Nothing received is ever executed, expanded or opened (SN-I). */
#ifdef METALUI_SDL
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>
#endif

enum {
    INSTANCE_QUEUE_MAX = 64,            /* SN-E: the 65th pending message is refused */
    INSTANCE_MAX_PAYLOAD = 1 << 20,     /* 1 MiB */
    INSTANCE_MAX_COUNT = 1024,
    INSTANCE_MAX_STRING = 32768,
    INSTANCE_ACK = 0x06,
    INSTANCE_NAK = 0x15,
    INSTANCE_RETRY_MS = 50
};

/* ---- The wake event and the counters ------------------------------------ */

static Uint32 instance_event_type = 0;
static SDL_AtomicInt instance_wakes;
static SDL_AtomicInt payload_high_water;

bool mui_instance_is_wake_event(uint32_t sdl_type) {
    if (instance_event_type == 0 || sdl_type != instance_event_type) return false;
    SDL_AddAtomicInt(&instance_wakes, 1);
    return true;
}

int32_t mui_instance_wakes_consumed(void) { return (int32_t)SDL_GetAtomicInt(&instance_wakes); }
int32_t mui_instance_payload_high_water(void) { return (int32_t)SDL_GetAtomicInt(&payload_high_water); }

/* ---- SHA-256 (the name's hash; no dependency) ---------------------------- */

static uint32_t rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

static void sha256(const uint8_t *data, size_t length, uint8_t out[32]) {
    static const uint32_t K[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    size_t padded = ((length + 8) / 64 + 1) * 64;
    uint8_t *buffer = calloc(1, padded);
    if (!buffer) { memset(out, 0, 32); return; }
    memcpy(buffer, data, length);
    buffer[length] = 0x80;
    uint64_t bits = (uint64_t)length * 8;
    for (int i = 0; i < 8; i++) buffer[padded - 1 - i] = (uint8_t)(bits >> (8 * i));
    for (size_t block = 0; block < padded; block += 64) {
        uint32_t w[64];
        for (int i = 0; i < 16; i++) {
            const uint8_t *p = buffer + block + 4 * i;
            w[i] = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
        }
        for (int i = 16; i < 64; i++) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; i++) {
            uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            uint32_t ch = (e & f) ^ (~e & g);
            uint32_t t1 = hh + S1 + ch + K[i] + w[i];
            uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t t2 = S0 + maj;
            hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    free(buffer);
    for (int i = 0; i < 8; i++) {
        out[4 * i] = (uint8_t)(h[i] >> 24); out[4 * i + 1] = (uint8_t)(h[i] >> 16);
        out[4 * i + 2] = (uint8_t)(h[i] >> 8); out[4 * i + 3] = (uint8_t)h[i];
    }
}

/* The first `hex_digits` hex digits of SHA-256(bytes), NUL-terminated in `out`. */
static void hash_hex(const void *bytes, size_t length, int hex_digits, char *out) {
    static const char digits[] = "0123456789abcdef";
    uint8_t digest[32];
    sha256((const uint8_t *)bytes, length, digest);
    for (int i = 0; i < hex_digits; i++)
        out[i] = digits[(i % 2 == 0) ? (digest[i / 2] >> 4) : (digest[i / 2] & 0xF)];
    out[hex_digits] = 0;
}

/* ---- The wire (SN-E) ------------------------------------------------------ */

typedef struct { uint32_t count; char **strings; } InstanceMessage;

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static void put_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}

/* Strict UTF-8: no overlong forms, no surrogates, nothing above U+10FFFF. */
static bool valid_utf8(const uint8_t *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        uint8_t c = s[i];
        if (c < 0x80) { i++; continue; }
        size_t extra; uint32_t minimum, code;
        if (c >= 0xC2 && c <= 0xDF) { extra = 1; minimum = 0x80; code = c & 0x1F; }
        else if (c >= 0xE0 && c <= 0xEF) { extra = 2; minimum = 0x800; code = c & 0x0F; }
        else if (c >= 0xF0 && c <= 0xF4) { extra = 3; minimum = 0x10000; code = c & 0x07; }
        else return false;
        if (i + extra >= n) return false;
        for (size_t k = 1; k <= extra; k++) {
            if ((s[i + k] & 0xC0) != 0x80) return false;
            code = (code << 6) | (s[i + k] & 0x3F);
        }
        if (code < minimum || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return false;
        i += extra + 1;
    }
    return true;
}

void mui_instance_free_message(char **strings, uint32_t count) {
    if (!strings) return;
    for (uint32_t i = 0; i < count; i++) free(strings[i]);
    free(strings);
}

/* Decodes a payload that must be consumed exactly (SN-E): every limit is
   checked before the allocation it guards. */
static bool parse_payload(const uint8_t *p, size_t n, InstanceMessage *out) {
    out->count = 0; out->strings = NULL;
    if (n < 4) return false;
    uint32_t count = be32(p);
    if (count > INSTANCE_MAX_COUNT) return false;
    char **strings = count ? calloc(count, sizeof(char *)) : NULL;
    if (count && !strings) return false;
    size_t offset = 4;
    for (uint32_t i = 0; i < count; i++) {
        if (n - offset < 4) { mui_instance_free_message(strings, count); return false; }
        uint32_t length = be32(p + offset);
        offset += 4;
        if (length < 1 || length > INSTANCE_MAX_STRING || length > n - offset
            || memchr(p + offset, 0, length) != NULL || !valid_utf8(p + offset, length)) {
            mui_instance_free_message(strings, count); return false;
        }
        strings[i] = malloc((size_t)length + 1);
        if (!strings[i]) { mui_instance_free_message(strings, count); return false; }
        memcpy(strings[i], p + offset, length);
        strings[i][length] = 0;
        offset += length;
    }
    if (offset != n) { mui_instance_free_message(strings, count); return false; }
    out->count = count; out->strings = strings;
    return true;
}

/* The sender's message: "MSI1", payload length, payload. NULL when a limit would
   be broken (the sender never sends what the listener would refuse by size). */
static uint8_t *encode_message(const char *const *strings, uint32_t count, size_t *size) {
    if (count > INSTANCE_MAX_COUNT) return NULL;
    size_t payload = 4;
    for (uint32_t i = 0; i < count; i++) {
        size_t length = strlen(strings[i]);
        if (length > INSTANCE_MAX_STRING) return NULL;
        payload += 4 + length;
        if (payload > INSTANCE_MAX_PAYLOAD) return NULL;
    }
    uint8_t *bytes = malloc(8 + payload);
    if (!bytes) return NULL;
    memcpy(bytes, "MSI1", 4);
    put_be32(bytes + 4, (uint32_t)payload);
    put_be32(bytes + 8, count);
    size_t offset = 12;
    for (uint32_t i = 0; i < count; i++) {
        size_t length = strlen(strings[i]);
        put_be32(bytes + offset, (uint32_t)length);
        memcpy(bytes + offset + 4, strings[i], length);
        offset += 4 + length;
    }
    *size = 8 + payload;
    return bytes;
}

/* ---- The instance --------------------------------------------------------- */

struct MuiInstance {
    SDL_Mutex *mutex;
    InstanceMessage queue[INSTANCE_QUEUE_MAX];
    uint32_t head, length;
    SDL_AtomicInt wake_type;
    int32_t read_timeout_ms;
    int64_t expected_peer_uid;
    SDL_Thread *thread;
#ifdef _WIN32
    HANDLE semaphore, pipe, stop_event, connect_event;
    char pipe_name[160];
#else
    int lock_fd, listen_fd, stop_pipe[2];
    char socket_path[128];
#endif
};

static int64_t now_ms(void) { return (int64_t)(SDL_GetTicksNS() / 1000000ULL); }

/* Returns false (queue full) without taking ownership. */
static bool enqueue(MuiInstance *in, InstanceMessage message) {
    bool queued = false;
    SDL_LockMutex(in->mutex);
    if (in->length < INSTANCE_QUEUE_MAX) {
        in->queue[(in->head + in->length) % INSTANCE_QUEUE_MAX] = message;
        in->length++;
        queued = true;
    }
    SDL_UnlockMutex(in->mutex);
    return queued;
}

bool mui_instance_next(MuiInstance *in, char ***strings, uint32_t *count) {
    bool found = false;
    SDL_LockMutex(in->mutex);
    if (in->length > 0) {
        InstanceMessage m = in->queue[in->head];
        in->head = (in->head + 1) % INSTANCE_QUEUE_MAX;
        in->length--;
        *strings = m.strings; *count = m.count;
        found = true;
    }
    SDL_UnlockMutex(in->mutex);
    return found;
}

void mui_instance_attach(MuiInstance *in) {
    if (instance_event_type == 0) instance_event_type = SDL_RegisterEvents(1);
    SDL_SetAtomicInt(&in->wake_type, (int)instance_event_type);
}

/* A failed push is ignored: the drain at the top of every loop iteration
   delivers the message (SN-G). */
static void wake(MuiInstance *in) {
    int type = SDL_GetAtomicInt(&in->wake_type);
    if (type == 0) return;
    SDL_Event e;
    SDL_zero(e);
    e.type = (Uint32)type;
    e.common.timestamp = SDL_GetTicksNS();
    SDL_PushEvent(&e);
}

static void note_payload_request(size_t size) {
    int current = SDL_GetAtomicInt(&payload_high_water);
    while ((int)size > current) {
        if (SDL_CompareAndSwapAtomicInt(&payload_high_water, current, (int)size)) break;
        current = SDL_GetAtomicInt(&payload_high_water);
    }
}

/* One connection: a read with one deadline, the checks of SN-E, the enqueue,
   then the ack (after the enqueue, so a sender that saw it knows the message is
   queued). Returns after the ack is written; the caller closes the connection. */
typedef struct InstanceConn InstanceConn;
static bool conn_read(InstanceConn *c, uint8_t *buffer, size_t size, int64_t deadline);
static void conn_ack(InstanceConn *c, uint8_t byte);

static void serve(MuiInstance *in, InstanceConn *conn) {
    int64_t deadline = now_ms() + in->read_timeout_ms;
    uint8_t header[8];
    if (!conn_read(conn, header, sizeof header, deadline)) return;          /* timeout or close: no ack */
    if (memcmp(header, "MSI1", 4) != 0) { conn_ack(conn, INSTANCE_NAK); return; }
    uint32_t length = be32(header + 4);
    if (length > INSTANCE_MAX_PAYLOAD) { conn_ack(conn, INSTANCE_NAK); return; }   /* before any allocation */
    note_payload_request(length);
    uint8_t *payload = malloc(length ? length : 1);
    if (!payload) { conn_ack(conn, INSTANCE_NAK); return; }
    if (!conn_read(conn, payload, length, deadline)) { free(payload); return; }
    InstanceMessage message;
    bool ok = parse_payload(payload, length, &message);
    free(payload);
    if (!ok) { conn_ack(conn, INSTANCE_NAK); return; }
    if (!enqueue(in, message)) {
        mui_instance_free_message(message.strings, message.count);
        conn_ack(conn, INSTANCE_NAK);
        return;
    }
    wake(in);
    conn_ack(conn, INSTANCE_ACK);
}

#ifdef _WIN32
/* ======================= Windows: semaphore and named pipe (SN-D) ======== */

struct InstanceConn { HANDLE pipe; HANDLE event; };

/* Overlapped read or write with a deadline; true when `size` bytes moved. */
static bool overlapped_io(HANDLE pipe, HANDLE event, bool writing, uint8_t *buffer, size_t size, int64_t deadline) {
    size_t done = 0;
    while (done < size) {
        OVERLAPPED o; memset(&o, 0, sizeof o); o.hEvent = event; ResetEvent(event);
        DWORD n = 0;
        BOOL started = writing ? WriteFile(pipe, buffer + done, (DWORD)(size - done), &n, &o)
                               : ReadFile(pipe, buffer + done, (DWORD)(size - done), &n, &o);
        if (!started) {
            if (GetLastError() != ERROR_IO_PENDING) return false;
            int64_t left = deadline - now_ms();
            if (left < 0) left = 0;
            if (WaitForSingleObject(event, (DWORD)left) != WAIT_OBJECT_0) { CancelIo(pipe); GetOverlappedResult(pipe, &o, &n, TRUE); return false; }
            if (!GetOverlappedResult(pipe, &o, &n, FALSE)) return false;
        }
        if (n == 0) return false;
        done += n;
    }
    return true;
}

static bool conn_read(InstanceConn *c, uint8_t *buffer, size_t size, int64_t deadline) {
    return size == 0 ? true : overlapped_io(c->pipe, c->event, false, buffer, size, deadline);
}
static void conn_ack(InstanceConn *c, uint8_t byte) {
    overlapped_io(c->pipe, c->event, true, &byte, 1, now_ms() + 1000);
    FlushFileBuffers(c->pipe);
}

static char *current_user_sid(void) {
    HANDLE token = NULL; char *text = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return NULL;
    DWORD need = 0;
    GetTokenInformation(token, TokenUser, NULL, 0, &need);
    TOKEN_USER *user = need ? malloc(need) : NULL;
    if (user && GetTokenInformation(token, TokenUser, user, need, &need)) {
        LPSTR s = NULL;
        if (ConvertSidToStringSidA(user->User.Sid, &s)) { text = SDL_strdup(s); LocalFree(s); }
    }
    free(user); CloseHandle(token);
    return text;
}

static bool windows_names(const char *id, char *semaphore, size_t sc, char *pipe, size_t pc) {
    char *sid = current_user_sid();
    if (!sid) return false;
    DWORD session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session);
    char scope_input[256];
    snprintf(scope_input, sizeof scope_input, "%s:%lu", sid, (unsigned long)session);
    SDL_free(sid);
    char h[17], s[9];
    hash_hex(id, strlen(id), 16, h);
    hash_hex(scope_input, strlen(scope_input), 8, s);
    snprintf(semaphore, sc, "Local\\MetalUI-%s-%s", h, s);
    snprintf(pipe, pc, "\\\\.\\pipe\\MetalUI-%s-%s", h, s);
    return true;
}

bool mui_instance_paths(const char *id, const char *directory, char *lock, size_t lc, char *sock, size_t sc) {
    (void)directory;
    if (!id || !*id) return false;
    char semaphore[160], pipe[160];
    if (!windows_names(id, semaphore, sizeof semaphore, pipe, sizeof pipe)) return false;
    snprintf(lock, lc, "%s", semaphore);
    snprintf(sock, sc, "%s", pipe);
    return true;
}

static bool user_sid_of_process(DWORD pid, TOKEN_USER **out) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid), token = NULL;
    if (!process) return false;
    bool ok = false;
    if (OpenProcessToken(process, TOKEN_QUERY, &token)) {
        DWORD need = 0;
        GetTokenInformation(token, TokenUser, NULL, 0, &need);
        TOKEN_USER *user = need ? malloc(need) : NULL;
        if (user && GetTokenInformation(token, TokenUser, user, need, &need)) { *out = user; ok = true; }
        else free(user);
        CloseHandle(token);
    }
    CloseHandle(process);
    return ok;
}

static int instance_listener(void *data) {
    MuiInstance *in = data;
    for (;;) {
        OVERLAPPED o; memset(&o, 0, sizeof o); o.hEvent = in->connect_event; ResetEvent(in->connect_event);
        BOOL connected = ConnectNamedPipe(in->pipe, &o);
        DWORD error = connected ? 0 : GetLastError();
        if (!connected && error == ERROR_IO_PENDING) {
            HANDLE waits[2] = {in->connect_event, in->stop_event};
            if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) != WAIT_OBJECT_0) { CancelIo(in->pipe); return 0; }
        } else if (!connected && error != ERROR_PIPE_CONNECTED) {
            if (WaitForSingleObject(in->stop_event, 50) == WAIT_OBJECT_0) return 0;
            continue;
        }
        if (WaitForSingleObject(in->stop_event, 0) == WAIT_OBJECT_0) return 0;
        InstanceConn conn = {in->pipe, CreateEventA(NULL, TRUE, FALSE, NULL)};
        serve(in, &conn);
        CloseHandle(conn.event);
        DisconnectNamedPipe(in->pipe);
    }
}

static int32_t forward_over(const char *pipe_name, const uint8_t *bytes, size_t size,
                            int32_t connect_ms, int32_t read_ms, int32_t *error) {
    int64_t deadline = now_ms() + connect_ms;
    HANDLE pipe;
    for (;;) {
        pipe = CreateFileA(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
                           FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
        if (pipe != INVALID_HANDLE_VALUE) break;
        DWORD e = GetLastError();
        if (now_ms() >= deadline) { *error = (int32_t)e; return MUI_INSTANCE_NO_LISTENER; }
        if (e == ERROR_PIPE_BUSY) WaitNamedPipeA(pipe_name, INSTANCE_RETRY_MS);
        else SDL_Delay(INSTANCE_RETRY_MS);
    }
    int32_t result = MUI_INSTANCE_IO;
    /* The server must be this user's process (SN-D): never write to a squatter. */
    ULONG server_pid = 0;
    TOKEN_USER *theirs = NULL, *mine = NULL;
    if (!GetNamedPipeServerProcessId(pipe, &server_pid)
        || !user_sid_of_process(server_pid, &theirs) || !user_sid_of_process(GetCurrentProcessId(), &mine)
        || !EqualSid(theirs->User.Sid, mine->User.Sid)) {
        result = MUI_INSTANCE_INSECURE;
    } else {
        HANDLE event = CreateEventA(NULL, TRUE, FALSE, NULL);
        uint8_t ack = 0;
        if (!overlapped_io(pipe, event, true, (uint8_t *)bytes, size, now_ms() + read_ms)) {
            *error = (int32_t)GetLastError();
        } else if (!overlapped_io(pipe, event, false, &ack, 1, now_ms() + read_ms)) {
            *error = (int32_t)GetLastError(); result = (*error == ERROR_BROKEN_PIPE) ? MUI_INSTANCE_REFUSED : MUI_INSTANCE_IO;
        } else {
            result = ack == INSTANCE_ACK ? MUI_INSTANCE_FORWARDED : MUI_INSTANCE_REFUSED;
        }
        CloseHandle(event);
    }
    free(theirs); free(mine);
    CloseHandle(pipe);
    return result;
}

int32_t mui_instance_claim(const char *id, const char *directory, const char *const *strings, uint32_t count,
                           int32_t connect_ms, int32_t read_ms, int64_t expected_uid,
                           MuiInstance **out, int32_t *error) {
    (void)directory; (void)expected_uid;
    *out = NULL; *error = 0;
    if (!id || !*id) return MUI_INSTANCE_EMPTY_ID;
    char semaphore_name[160], pipe_name[160];
    if (!windows_names(id, semaphore_name, sizeof semaphore_name, pipe_name, sizeof pipe_name)) {
        *error = (int32_t)GetLastError(); return MUI_INSTANCE_IO;
    }
    /* A named semaphore, count 1: unlike a mutex it has no thread owner and is not
       recursive, so a second claim on the winner's own thread still loses (SN-P). The
       kernel destroys it with its last handle, so a crashed primary frees the role. */
    HANDLE semaphore = CreateSemaphoreA(NULL, 1, 1, semaphore_name);
    if (!semaphore) { *error = (int32_t)GetLastError(); return MUI_INSTANCE_IO; }
    if (WaitForSingleObject(semaphore, 0) != WAIT_OBJECT_0) {
        CloseHandle(semaphore);
        size_t size = 0;
        uint8_t *bytes = encode_message(strings, count, &size);
        if (!bytes) return MUI_INSTANCE_REFUSED;
        int32_t r = forward_over(pipe_name, bytes, size, connect_ms, read_ms, error);
        free(bytes);
        return r;
    }
    MuiInstance *in = calloc(1, sizeof *in);
    if (!in) { CloseHandle(semaphore); return MUI_INSTANCE_IO; }
    in->semaphore = semaphore;
    in->mutex = SDL_CreateMutex();
    in->read_timeout_ms = read_ms;
    in->expected_peer_uid = expected_uid;
    snprintf(in->pipe_name, sizeof in->pipe_name, "%s", pipe_name);
    char *sid = current_user_sid();
    char sddl[160];
    snprintf(sddl, sizeof sddl, "D:P(A;;GA;;;%s)", sid ? sid : "");
    SDL_free(sid);
    SECURITY_ATTRIBUTES attributes = {sizeof attributes, NULL, FALSE};
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(sddl, SDDL_REVISION_1, &attributes.lpSecurityDescriptor, NULL)) {
        *error = (int32_t)GetLastError();
        CloseHandle(semaphore); SDL_DestroyMutex(in->mutex); free(in);
        return MUI_INSTANCE_IO;
    }
    in->pipe = CreateNamedPipeA(pipe_name,
                                PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                1, 4096, 4096, 0, &attributes);
    LocalFree(attributes.lpSecurityDescriptor);
    if (in->pipe == INVALID_HANDLE_VALUE) {
        *error = (int32_t)GetLastError();
        CloseHandle(semaphore); SDL_DestroyMutex(in->mutex); free(in);
        return MUI_INSTANCE_INSECURE;   /* FIRST_PIPE_INSTANCE failed: a squatter */
    }
    in->stop_event = CreateEventA(NULL, TRUE, FALSE, NULL);
    in->connect_event = CreateEventA(NULL, TRUE, FALSE, NULL);
    in->thread = SDL_CreateThread(instance_listener, "metalui-instance", in);
    if (!in->thread) {
        *error = (int32_t)GetLastError();
        CloseHandle(in->pipe); CloseHandle(in->stop_event); CloseHandle(in->connect_event);
        CloseHandle(semaphore); SDL_DestroyMutex(in->mutex); free(in);
        return MUI_INSTANCE_IO;
    }
    *out = in;
    return MUI_INSTANCE_PRIMARY;
}

static void release_transport(MuiInstance *in) {
    SetEvent(in->stop_event);
    SDL_WaitThread(in->thread, NULL);
    CloseHandle(in->pipe); CloseHandle(in->stop_event); CloseHandle(in->connect_event);
    CloseHandle(in->semaphore);
}

#else
/* ======================= Unix: flock and a filesystem socket (SN-C) ====== */

struct InstanceConn { int fd; };

static bool conn_read(InstanceConn *c, uint8_t *buffer, size_t size, int64_t deadline) {
    size_t done = 0;
    while (done < size) {
        int64_t left = deadline - now_ms();
        if (left < 0) return false;
        struct pollfd p = {c->fd, POLLIN, 0};
        int r = poll(&p, 1, (int)left);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        ssize_t n = read(c->fd, buffer + done, size - done);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return false;
        done += (size_t)n;
    }
    return true;
}

static void conn_ack(InstanceConn *c, uint8_t byte) {
#ifdef MSG_NOSIGNAL
    (void)send(c->fd, &byte, 1, MSG_NOSIGNAL);
#else
    (void)write(c->fd, &byte, 1);
#endif
}

static void set_cloexec(int fd) { int f = fcntl(fd, F_GETFD); if (f >= 0) fcntl(fd, F_SETFD, f | FD_CLOEXEC); }
static void set_nonblock(int fd) { int f = fcntl(fd, F_GETFL); if (f >= 0) fcntl(fd, F_SETFL, f | O_NONBLOCK); }

static int new_socket(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    set_cloexec(fd);
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
    return fd;
}

/* The uid of the process at the other end, or false. */
static bool peer_uid(int fd, uid_t *uid) {
#if defined(__linux__)
    struct ucred cred; socklen_t length = sizeof cred;
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &length) != 0) return false;
    *uid = cred.uid; return true;
#else
    gid_t gid;
    return getpeereid(fd, uid, &gid) == 0;
#endif
}

static int instance_listener(void *data) {
    MuiInstance *in = data;
    for (;;) {
        struct pollfd fds[2] = {{in->listen_fd, POLLIN, 0}, {in->stop_pipe[0], POLLIN, 0}};
        int r = poll(fds, 2, -1);
        if (r < 0) { if (errno == EINTR) continue; return 0; }
        if (fds[1].revents != 0) return 0;
        if (!(fds[0].revents & POLLIN)) continue;
        int fd = accept(in->listen_fd, NULL, NULL);
        if (fd < 0) continue;
        set_cloexec(fd);
        set_nonblock(fd);
        uid_t uid;
        uid_t expected = in->expected_peer_uid >= 0 ? (uid_t)in->expected_peer_uid : geteuid();
        if (peer_uid(fd, &uid) && uid == expected) {
            InstanceConn conn = {fd};
            serve(in, &conn);
        }   /* another user's connection, or one with no credentials: closed unread */
        close(fd);
    }
}

/* The directory a claim uses (SN-C item 3), into `out`; false with *error. */
static bool default_directory(char *out, size_t capacity, int32_t *error) {
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    if (xdg && *xdg) { snprintf(out, capacity, "%s", xdg); return true; }
#if defined(__APPLE__)
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, out, capacity);
    if (n > 0 && n <= capacity) {
        size_t length = strlen(out);
        while (length > 1 && out[length - 1] == '/') out[--length] = 0;
        return true;
    }
#endif
    snprintf(out, capacity, "/tmp/metalui-%lu", (unsigned long)geteuid());
    if (mkdir(out, 0700) != 0 && errno != EEXIST) { *error = errno; return false; }
    return true;
}

static void file_names(const char *id, char *lock_name, char *socket_name) {
    char h[17];
    hash_hex(id, strlen(id), 16, h);
    snprintf(lock_name, 32, "msui-%s.lock", h);
    snprintf(socket_name, 32, "msui-%s.sock", h);
}

bool mui_instance_paths(const char *id, const char *directory, char *lock, size_t lc, char *sock, size_t sc) {
    if (!id || !*id) return false;
    char dir[1024], lock_name[32], socket_name[32];
    int32_t error = 0;
    if (directory) snprintf(dir, sizeof dir, "%s", directory);
    else if (!default_directory(dir, sizeof dir, &error)) return false;
    file_names(id, lock_name, socket_name);
    int a = snprintf(lock, lc, "%s/%s", dir, lock_name);
    int b = snprintf(sock, sc, "%s/%s", dir, socket_name);
    return a > 0 && b > 0 && (size_t)a < lc && (size_t)b < sc;
}

static int32_t forward_over(const char *socket_path, const uint8_t *bytes, size_t size,
                            int32_t connect_ms, int32_t read_ms, int32_t *error) {
    struct sockaddr_un address;
    memset(&address, 0, sizeof address);
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof address.sun_path, "%s", socket_path);
    int64_t deadline = now_ms() + connect_ms;
    int fd;
    for (;;) {
        fd = new_socket();
        if (fd < 0) { *error = errno; return MUI_INSTANCE_IO; }
        set_nonblock(fd);
        if (connect(fd, (struct sockaddr *)&address, sizeof address) == 0) break;
        int e = errno;
        close(fd);
        if (now_ms() >= deadline) { *error = e; return MUI_INSTANCE_NO_LISTENER; }
        SDL_Delay(INSTANCE_RETRY_MS);   /* between the primary's flock and its listen, or a full backlog */
    }
    int32_t result = MUI_INSTANCE_IO;
    uid_t uid;
    if (!peer_uid(fd, &uid) || uid != geteuid()) { close(fd); return MUI_INSTANCE_INSECURE; }
    int64_t write_deadline = now_ms() + read_ms;
    size_t sent = 0;
    while (sent < size) {
        int64_t left = write_deadline - now_ms();
        if (left < 0) { *error = ETIMEDOUT; close(fd); return MUI_INSTANCE_IO; }
        struct pollfd p = {fd, POLLOUT, 0};
        int r = poll(&p, 1, (int)left);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) { *error = ETIMEDOUT; close(fd); return MUI_INSTANCE_IO; }
#ifdef MSG_NOSIGNAL
        ssize_t n = send(fd, bytes + sent, size - sent, MSG_NOSIGNAL);
#else
        ssize_t n = write(fd, bytes + sent, size - sent);
#endif
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n < 0) { *error = errno; close(fd); return errno == EPIPE ? MUI_INSTANCE_REFUSED : MUI_INSTANCE_IO; }
        sent += (size_t)n;
    }
    uint8_t ack = 0;
    InstanceConn conn = {fd};
    if (conn_read(&conn, &ack, 1, now_ms() + read_ms)) result = ack == INSTANCE_ACK ? MUI_INSTANCE_FORWARDED : MUI_INSTANCE_REFUSED;
    else { *error = ETIMEDOUT; result = MUI_INSTANCE_IO; }
    close(fd);
    return result;
}

int32_t mui_instance_claim(const char *id, const char *directory, const char *const *strings, uint32_t count,
                           int32_t connect_ms, int32_t read_ms, int64_t expected_uid,
                           MuiInstance **out, int32_t *error) {
    *out = NULL; *error = 0;
    if (!id || !*id) return MUI_INSTANCE_EMPTY_ID;
    char dir[1024], lock_name[32], socket_name[32];
    if (directory) {
        if (strlen(directory) >= sizeof dir) return MUI_INSTANCE_PATH_TOO_LONG;
        snprintf(dir, sizeof dir, "%s", directory);
    } else if (!default_directory(dir, sizeof dir, error)) {
        return MUI_INSTANCE_IO;
    }
    file_names(id, lock_name, socket_name);
    struct sockaddr_un probe;
    size_t socket_length = strlen(dir) + 1 + strlen(socket_name);
    if (socket_length >= sizeof probe.sun_path) return MUI_INSTANCE_PATH_TOO_LONG;   /* named, never truncated */

    struct stat info;
    if (lstat(dir, &info) != 0) { *error = errno; return MUI_INSTANCE_IO; }
    if (!S_ISDIR(info.st_mode) || info.st_uid != geteuid() || (info.st_mode & 0077) != 0)
        return MUI_INSTANCE_INSECURE_DIRECTORY;

    char lock_path[1100], socket_path[1100];
    snprintf(lock_path, sizeof lock_path, "%s/%s", dir, lock_name);
    snprintf(socket_path, sizeof socket_path, "%s/%s", dir, socket_name);
    int lock_fd = open(lock_path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (lock_fd < 0) { *error = errno; return MUI_INSTANCE_IO; }
    set_cloexec(lock_fd);
    if (flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
        int e = errno;
        close(lock_fd);
        if (e != EWOULDBLOCK) { *error = e; return MUI_INSTANCE_IO; }
        size_t size = 0;
        uint8_t *bytes = encode_message(strings, count, &size);
        if (!bytes) return MUI_INSTANCE_REFUSED;
        int32_t r = forward_over(socket_path, bytes, size, connect_ms, read_ms, error);
        free(bytes);
        return r;
    }

    /* Won: whatever is at the socket's name is stale by definition (SN-C item 2). */
    unlink(socket_path);
    int listen_fd = new_socket();
    if (listen_fd < 0) { *error = errno; close(lock_fd); return MUI_INSTANCE_IO; }
    struct sockaddr_un address;
    memset(&address, 0, sizeof address);
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof address.sun_path, "%s", socket_path);
    mode_t previous = umask(0177);
    int bound = bind(listen_fd, (struct sockaddr *)&address, sizeof address);
    int bind_error = errno;
    umask(previous);
    if (bound != 0 || listen(listen_fd, 8) != 0) {
        *error = bound != 0 ? bind_error : errno;
        close(listen_fd); close(lock_fd);
        return MUI_INSTANCE_IO;
    }
    MuiInstance *in = calloc(1, sizeof *in);
    if (!in) { close(listen_fd); close(lock_fd); return MUI_INSTANCE_IO; }
    in->mutex = SDL_CreateMutex();
    in->lock_fd = lock_fd; in->listen_fd = listen_fd;
    in->read_timeout_ms = read_ms;
    in->expected_peer_uid = expected_uid;
    snprintf(in->socket_path, sizeof in->socket_path, "%s", socket_path);
    if (pipe(in->stop_pipe) != 0) {
        *error = errno;
        unlink(socket_path); close(listen_fd); close(lock_fd); SDL_DestroyMutex(in->mutex); free(in);
        return MUI_INSTANCE_IO;
    }
    set_cloexec(in->stop_pipe[0]); set_cloexec(in->stop_pipe[1]);
    in->thread = SDL_CreateThread(instance_listener, "metalui-instance", in);
    if (!in->thread) {
        *error = EAGAIN;
        unlink(socket_path); close(listen_fd); close(lock_fd);
        close(in->stop_pipe[0]); close(in->stop_pipe[1]); SDL_DestroyMutex(in->mutex); free(in);
        return MUI_INSTANCE_IO;
    }
    *out = in;
    return MUI_INSTANCE_PRIMARY;
}

static void release_transport(MuiInstance *in) {
    uint8_t byte = 1;
    (void)write(in->stop_pipe[1], &byte, 1);
    SDL_WaitThread(in->thread, NULL);
    unlink(in->socket_path);   /* before the lock goes, so a new primary never loses its socket to us */
    close(in->listen_fd);
    close(in->stop_pipe[0]); close(in->stop_pipe[1]);
    close(in->lock_fd);
}
#endif

void mui_instance_release(MuiInstance *in) {
    if (!in) return;
    release_transport(in);
    for (;;) {
        char **strings; uint32_t count;
        if (!mui_instance_next(in, &strings, &count)) break;
        mui_instance_free_message(strings, count);
    }
    SDL_DestroyMutex(in->mutex);
    free(in);
}

bool mui_window_raise(void *window) {
    SDL_Window *w = (SDL_Window *)window;
    if (SDL_GetWindowFlags(w) & SDL_WINDOW_MINIMIZED) SDL_RestoreWindow(w);
    bool raised = SDL_RaiseWindow(w);
    if (!(SDL_GetWindowFlags(w) & SDL_WINDOW_INPUT_FOCUS)) SDL_FlashWindow(w, SDL_FLASH_UNTIL_FOCUSED);
    return raised;
}

#else
/* Built without the `SDL` trait: no SDL3 header, no SDL3 link. */
int mui_instance_built_without_sdl = 1;
#endif
