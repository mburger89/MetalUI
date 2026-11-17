#ifdef _WIN32

// ConPTY engine for PseudoTerminal (ruling TRM-AX). One pty is: two overlapped named pipes whose client ends
// the pseudo console owns, the child in a kill-on-close job, one thread-pool IO for reading, one for writing,
// and one registered wait for the child's exit. No thread per pty: the only threads this file creates are two
// short-lived ones, the pseudo console's closer (`ClosePseudoConsole` can block until its output is read) and the
// teardown, and neither exists while a pty is merely running.

#include "CPseudoTerminal.h"

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

// ConPTY entry points are looked up, so a Windows before 10 1809 gets CPW_UNSUPPORTED instead of a process
// that cannot start, and the build needs no particular NTDDI level.
typedef VOID *cpw_hpcon;
typedef HRESULT(WINAPI *CreatePseudoConsoleFn)(COORD, HANDLE, HANDLE, DWORD, cpw_hpcon *);
typedef HRESULT(WINAPI *ResizePseudoConsoleFn)(cpw_hpcon, COORD);
typedef VOID(WINAPI *ClosePseudoConsoleFn)(cpw_hpcon);

#define CPW_ATTRIBUTE_PSEUDOCONSOLE ((DWORD_PTR)0x00020016)   // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
#define CPW_ATTRIBUTE_JOB_LIST ((DWORD_PTR)0x0002000D)         // PROC_THREAD_ATTRIBUTE_JOB_LIST
#define CPW_STAGE 65536            // one read's size
#define CPW_RING (4 * CPW_STAGE)   // buffered output before reading pauses (back pressure on conhost)
#define CPW_PIPE 65536

typedef struct cpw_chunk {
    struct cpw_chunk *next;
    size_t length;
    uint8_t data[1];
} cpw_chunk;

struct cpw_pty {
    CRITICAL_SECTION lock;
    cpw_callback callback;
    void *context;

    HANDLE out;   // server end of the output pipe, overlapped
    HANDLE in;    // server end of the input pipe, overlapped
    cpw_hpcon console;
    HANDLE process;
    HANDLE job;
    HANDLE wait;
    PTP_IO readIO, writeIO;
    CreatePseudoConsoleFn createConsole;
    ResizePseudoConsoleFn resizeConsole;
    ClosePseudoConsoleFn closeConsole;

    // Reading: a staging buffer for the one read in flight, and a ring the reader drains.
    OVERLAPPED readOverlapped;
    uint8_t stage[CPW_STAGE];
    uint8_t *ring;
    size_t head, count;
    int readInflight, readPaused, ended, discard;
    HANDLE endedEvent;   // manual reset: the read loop is over

    // Writing: chunks in order; at most one write in flight.
    OVERLAPPED writeOverlapped;
    cpw_chunk *first, *last;
    cpw_chunk *current;
    size_t currentOffset;
    int writeInflight;

    int exitRecorded;
    LONG closeStarted;   // the closer thread
    HANDLE closerDone;   // manual reset
};

static void notify(cpw_pty *pty, int event, int32_t value) { pty->callback(pty->context, event, value); }

static void free_chunks(cpw_pty *pty) {   // lock held
    while (pty->first) {
        cpw_chunk *next = pty->first->next;
        free(pty->first);
        pty->first = next;
    }
    pty->last = NULL;
    free(pty->current);
    pty->current = NULL;
    pty->currentOffset = 0;
}

// MARK: Reading

// Lock held. Starts the next read when there is room; returns 1 when the stream ended instead.
static int start_read(cpw_pty *pty) {
    if (pty->ended || pty->readInflight) return 0;
    if (!pty->discard && CPW_RING - pty->count < CPW_STAGE) {
        pty->readPaused = 1;
        return 0;
    }
    pty->readPaused = 0;
    memset(&pty->readOverlapped, 0, sizeof pty->readOverlapped);
    pty->readInflight = 1;
    StartThreadpoolIo(pty->readIO);
    if (!ReadFile(pty->out, pty->stage, CPW_STAGE, NULL, &pty->readOverlapped) && GetLastError() != ERROR_IO_PENDING) {
        CancelThreadpoolIo(pty->readIO);
        pty->readInflight = 0;
        pty->ended = 1;
        SetEvent(pty->endedEvent);
        return 1;
    }
    return 0;
}

static VOID CALLBACK read_done(PTP_CALLBACK_INSTANCE instance, PVOID context, PVOID overlapped, ULONG result,
                               ULONG_PTR bytes, PTP_IO io) {
    (void)instance; (void)overlapped; (void)io;
    cpw_pty *pty = context;
    EnterCriticalSection(&pty->lock);
    pty->readInflight = 0;
    int discarding = pty->discard;
    if (result != NO_ERROR) {
        pty->ended = 1;
        SetEvent(pty->endedEvent);
    } else if (!discarding) {
        for (size_t i = 0; i < bytes; i++) pty->ring[(pty->head + pty->count + i) % CPW_RING] = pty->stage[i];
        pty->count += bytes;
    }
    if (!pty->ended) start_read(pty);
    LeaveCriticalSection(&pty->lock);
    if (!discarding) notify(pty, CPW_EVENT_READABLE, 0);
}

long cpw_read(cpw_pty *pty, void *buffer, size_t capacity) {
    EnterCriticalSection(&pty->lock);
    long result;
    if (pty->count > 0 && capacity > 0) {
        size_t n = pty->count < capacity ? pty->count : capacity;
        for (size_t i = 0; i < n; i++) ((uint8_t *)buffer)[i] = pty->ring[(pty->head + i) % CPW_RING];
        pty->head = (pty->head + n) % CPW_RING;
        pty->count -= n;
        result = (long)n;
        // If that read fails the stream has ended, which the caller's next read reports: no callback from here
        // (the caller holds its own lock, and the callback takes it).
        if (pty->readPaused) start_read(pty);
    } else {
        result = pty->ended && pty->count == 0 ? -1 : 0;
    }
    LeaveCriticalSection(&pty->lock);
    return result;
}

int cpw_available(cpw_pty *pty) {
    EnterCriticalSection(&pty->lock);
    int available = pty->count > 0 || pty->ended;
    LeaveCriticalSection(&pty->lock);
    return available;
}

// MARK: Writing

// Lock held. Issues the write of what is left of the current chunk, taking the next chunk when none is current.
static void start_write(cpw_pty *pty) {
    while (!pty->writeInflight) {
        if (!pty->current) {
            if (!pty->first) return;
            pty->current = pty->first;
            pty->first = pty->first->next;
            if (!pty->first) pty->last = NULL;
            pty->currentOffset = 0;
        }
        size_t left = pty->current->length - pty->currentOffset;
        DWORD n = left > 0x40000000 ? 0x40000000 : (DWORD)left;
        memset(&pty->writeOverlapped, 0, sizeof pty->writeOverlapped);
        pty->writeInflight = 1;
        StartThreadpoolIo(pty->writeIO);
        if (!WriteFile(pty->in, pty->current->data + pty->currentOffset, n, NULL, &pty->writeOverlapped) &&
            GetLastError() != ERROR_IO_PENDING) {
            CancelThreadpoolIo(pty->writeIO);
            pty->writeInflight = 0;
            free_chunks(pty);   // the pipe is gone: nothing can be delivered
            return;
        }
    }
}

static VOID CALLBACK write_done(PTP_CALLBACK_INSTANCE instance, PVOID context, PVOID overlapped, ULONG result,
                                ULONG_PTR bytes, PTP_IO io) {
    (void)instance; (void)overlapped; (void)io;
    cpw_pty *pty = context;
    EnterCriticalSection(&pty->lock);
    pty->writeInflight = 0;
    if (result != NO_ERROR) {
        free_chunks(pty);
    } else if (pty->current) {
        pty->currentOffset += bytes;
        if (pty->currentOffset >= pty->current->length) {
            free(pty->current);
            pty->current = NULL;
        }
        start_write(pty);
    }
    LeaveCriticalSection(&pty->lock);
}

void cpw_write(cpw_pty *pty, const void *bytes, size_t count) {
    if (count == 0) return;
    cpw_chunk *chunk = malloc(sizeof(cpw_chunk) + count);
    if (!chunk) return;
    chunk->next = NULL;
    chunk->length = count;
    memcpy(chunk->data, bytes, count);
    EnterCriticalSection(&pty->lock);
    if (pty->discard) {   // closing
        free(chunk);
    } else {
        if (pty->last) pty->last->next = chunk; else pty->first = chunk;
        pty->last = chunk;
        start_write(pty);
    }
    LeaveCriticalSection(&pty->lock);
}

// MARK: Control, exit and teardown

void cpw_resize(cpw_pty *pty, unsigned short cols, unsigned short rows) {
    COORD size = {(SHORT)(cols > 0 ? cols : 1), (SHORT)(rows > 0 ? rows : 1)};
    EnterCriticalSection(&pty->lock);
    if (pty->console) pty->resizeConsole(pty->console, size);
    LeaveCriticalSection(&pty->lock);
}

void cpw_terminate(cpw_pty *pty) {
    EnterCriticalSection(&pty->lock);
    if (pty->job && !pty->exitRecorded) TerminateJobObject(pty->job, 1);
    LeaveCriticalSection(&pty->lock);
}

// ClosePseudoConsole flushes what conhost still holds into the output pipe, so it can wait for a reader. The
// read loop keeps running (draining into the ring, or discarding once closing), which is what stops this
// deadlocking; and it runs here so a thread-pool thread never waits on it.
static DWORD WINAPI closer_main(LPVOID argument) {
    cpw_pty *pty = argument;
    EnterCriticalSection(&pty->lock);
    cpw_hpcon console = pty->console;
    pty->console = NULL;
    LeaveCriticalSection(&pty->lock);
    if (console) pty->closeConsole(console);
    SetEvent(pty->closerDone);
    return 0;
}

static void start_closer(cpw_pty *pty) {
    if (InterlockedCompareExchange(&pty->closeStarted, 1, 0) != 0) return;
    HANDLE thread = CreateThread(NULL, 0, closer_main, pty, 0, NULL);
    if (thread) CloseHandle(thread); else closer_main(pty);
}

static void record_exit(cpw_pty *pty) {
    DWORD code = 0;
    if (!GetExitCodeProcess(pty->process, &code)) code = (DWORD)-1;
    EnterCriticalSection(&pty->lock);
    int first = !pty->exitRecorded;
    pty->exitRecorded = 1;
    LeaveCriticalSection(&pty->lock);
    if (first) notify(pty, CPW_EVENT_EXITED, (int32_t)code);
    // The pseudo console's output pipe stays open until it is closed; closing it is what ends the stream.
    start_closer(pty);
}

static VOID CALLBACK exited(PVOID context, BOOLEAN timedOut) {
    (void)timedOut;
    record_exit(context);
}

static DWORD WINAPI teardown_main(LPVOID argument) {
    cpw_pty *pty = argument;
    // Discard from here on, and start reading again if back pressure had stopped it.
    EnterCriticalSection(&pty->lock);
    pty->discard = 1;
    free_chunks(pty);
    HANDLE job = pty->job;
    pty->job = NULL;
    start_read(pty);
    LeaveCriticalSection(&pty->lock);
    if (job) CloseHandle(job);   // kill-on-close: the child and all it started
    start_closer(pty);
    int clean = WaitForSingleObject(pty->closerDone, 30000) == WAIT_OBJECT_0;
    if (WaitForSingleObject(pty->endedEvent, 5000) != WAIT_OBJECT_0) {
        CancelIoEx(pty->out, NULL);
        WaitForSingleObject(pty->endedEvent, 5000);
    }
    WaitForSingleObject(pty->process, 10000);
    record_exit(pty);
    UnregisterWaitEx(pty->wait, INVALID_HANDLE_VALUE);
    CancelIoEx(pty->in, NULL);
    CancelIoEx(pty->out, NULL);
    WaitForThreadpoolIoCallbacks(pty->readIO, FALSE);
    WaitForThreadpoolIoCallbacks(pty->writeIO, FALSE);
    CloseThreadpoolIo(pty->readIO);
    CloseThreadpoolIo(pty->writeIO);
    CloseHandle(pty->out);
    CloseHandle(pty->in);
    CloseHandle(pty->process);
    void *context = pty->context;
    cpw_callback callback = pty->callback;
    if (clean) {
        CloseHandle(pty->closerDone);
        CloseHandle(pty->endedEvent);
        free(pty->ring);
        DeleteCriticalSection(&pty->lock);
        free(pty);   // a closer that never finished would still touch it: leak instead
    }
    callback(context, CPW_EVENT_RELEASED, clean);
    return 0;
}

void cpw_close(cpw_pty *pty) {
    HANDLE thread = CreateThread(NULL, 0, teardown_main, pty, 0, NULL);
    if (thread) CloseHandle(thread); else teardown_main(pty);
}

// MARK: Spawn

static LONG pipeCounter;

static HANDLE open_pipe(DWORD serverAccess, DWORD clientAccess, HANDLE *client, const wchar_t *tag) {
    wchar_t name[128];
    swprintf(name, 128, L"\\\\.\\pipe\\MetalUI-pty-%lu-%ld-%lu-%ls", GetCurrentProcessId(),
             InterlockedIncrement(&pipeCounter), GetTickCount(), tag);
    HANDLE server = CreateNamedPipeW(name, serverAccess | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                                     PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                     1, CPW_PIPE, CPW_PIPE, 0, NULL);
    if (server == INVALID_HANDLE_VALUE) return INVALID_HANDLE_VALUE;
    // The pseudo console reads and writes its ends synchronously: no FILE_FLAG_OVERLAPPED here.
    *client = CreateFileW(name, clientAccess, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (*client == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        CloseHandle(server);
        SetLastError(error);
        return INVALID_HANDLE_VALUE;
    }
    return server;
}

static void fail(cpw_result *out, int stage, DWORD code) {
    out->stage = stage;
    out->code = code;
}

void cpw_spawn(const uint16_t *application, uint16_t *commandLine, const uint16_t *environment,
               const uint16_t *cwd, unsigned short cols, unsigned short rows,
               cpw_callback callback, void *context, cpw_result *out) {
    memset(out, 0, sizeof *out);
    HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
    CreatePseudoConsoleFn create = (CreatePseudoConsoleFn)(void *)GetProcAddress(kernel, "CreatePseudoConsole");
    ResizePseudoConsoleFn resize = (ResizePseudoConsoleFn)(void *)GetProcAddress(kernel, "ResizePseudoConsole");
    ClosePseudoConsoleFn close = (ClosePseudoConsoleFn)(void *)GetProcAddress(kernel, "ClosePseudoConsole");
    if (!create || !resize || !close) { fail(out, CPW_UNSUPPORTED, ERROR_CALL_NOT_IMPLEMENTED); return; }

    cpw_pty *pty = calloc(1, sizeof *pty);
    if (!pty) { fail(out, CPW_OPEN_FAILED, ERROR_OUTOFMEMORY); return; }
    InitializeCriticalSection(&pty->lock);
    pty->callback = callback;
    pty->context = context;
    pty->createConsole = create;
    pty->resizeConsole = resize;
    pty->closeConsole = close;
    pty->ring = malloc(CPW_RING);
    pty->endedEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    pty->closerDone = CreateEventW(NULL, TRUE, FALSE, NULL);
    pty->out = pty->in = INVALID_HANDLE_VALUE;

    HANDLE clientIn = INVALID_HANDLE_VALUE, clientOut = INVALID_HANDLE_VALUE;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    PROCESS_INFORMATION info = {0};
    int stage = CPW_OPEN_FAILED;
    DWORD code = 0;
    int processStarted = 0;

    if (!pty->ring || !pty->endedEvent || !pty->closerDone) { code = ERROR_OUTOFMEMORY; goto failed; }
    pty->out = open_pipe(PIPE_ACCESS_INBOUND, GENERIC_WRITE, &clientOut, L"out");
    if (pty->out == INVALID_HANDLE_VALUE) { code = GetLastError(); goto failed; }
    pty->in = open_pipe(PIPE_ACCESS_OUTBOUND, GENERIC_READ, &clientIn, L"in");
    if (pty->in == INVALID_HANDLE_VALUE) { code = GetLastError(); goto failed; }
    pty->readIO = CreateThreadpoolIo(pty->out, read_done, pty, NULL);
    if (!pty->readIO) { code = GetLastError(); goto failed; }
    pty->writeIO = CreateThreadpoolIo(pty->in, write_done, pty, NULL);
    if (!pty->writeIO) { code = GetLastError(); goto failed; }

    COORD size = {(SHORT)(cols > 0 ? cols : 1), (SHORT)(rows > 0 ? rows : 1)};
    HRESULT hr = create(size, clientIn, clientOut, 0, &pty->console);
    if (FAILED(hr)) { code = (DWORD)hr; goto failed; }
    // The pseudo console holds its own duplicates now.
    CloseHandle(clientIn); clientIn = INVALID_HANDLE_VALUE;
    CloseHandle(clientOut); clientOut = INVALID_HANDLE_VALUE;

    stage = CPW_SPAWN_FAILED;
    pty->job = CreateJobObjectW(NULL, NULL);
    if (!pty->job) { code = GetLastError(); goto failed; }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
    memset(&limits, 0, sizeof limits);
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(pty->job, JobObjectExtendedLimitInformation, &limits, sizeof limits)) {
        code = GetLastError();
        goto failed;
    }

    SIZE_T attributeSize = 0;
    InitializeProcThreadAttributeList(NULL, 2, 0, &attributeSize);
    attributes = HeapAlloc(GetProcessHeap(), 0, attributeSize);
    if (!attributes || !InitializeProcThreadAttributeList(attributes, 2, 0, &attributeSize)) {
        code = GetLastError();
        if (attributes) { HeapFree(GetProcessHeap(), 0, attributes); attributes = NULL; }
        goto failed;
    }
    if (!UpdateProcThreadAttribute(attributes, 0, CPW_ATTRIBUTE_PSEUDOCONSOLE, pty->console, sizeof(cpw_hpcon),
                                   NULL, NULL)) {
        code = GetLastError();
        goto failed;
    }
    // The child is born in the job (Windows 10 1709+), so it is neither started suspended nor assigned later:
    // a console child created suspended showed conhost no output in CI.
    if (!UpdateProcThreadAttribute(attributes, 0, CPW_ATTRIBUTE_JOB_LIST, &pty->job, sizeof(HANDLE), NULL, NULL)) {
        code = GetLastError();
        goto failed;
    }

    wchar_t found[MAX_PATH];
    const wchar_t *program = (const wchar_t *)application;
    if (!wcspbrk(program, L"\\/:")) {
        DWORD n = SearchPathW(NULL, program, L".exe", MAX_PATH, found, NULL);
        if (n == 0 || n >= MAX_PATH) { code = n == 0 ? GetLastError() : ERROR_FILENAME_EXCED_RANGE; goto failed; }
        program = found;
    }
    STARTUPINFOEXW startup;
    memset(&startup, 0, sizeof startup);
    startup.StartupInfo.cb = sizeof startup;
    startup.lpAttributeList = attributes;
    // No handle is inherited.
    if (!CreateProcessW(program, (wchar_t *)commandLine, NULL, NULL, FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                        (LPVOID)environment, (const wchar_t *)cwd, &startup.StartupInfo, &info)) {
        code = GetLastError();
        goto failed;
    }
    processStarted = 1;
    pty->process = info.hProcess;
    DeleteProcThreadAttributeList(attributes);
    HeapFree(GetProcessHeap(), 0, attributes);
    attributes = NULL;
    CloseHandle(info.hThread);
    info.hThread = NULL;

    if (!RegisterWaitForSingleObject(&pty->wait, pty->process, exited, pty, INFINITE, WT_EXECUTEONLYONCE)) {
        code = GetLastError();
        goto failed;
    }
    EnterCriticalSection(&pty->lock);
    int ended = start_read(pty);
    LeaveCriticalSection(&pty->lock);
    if (ended) notify(pty, CPW_EVENT_READABLE, 0);
    out->pty = pty;
    out->stage = CPW_OK;
    out->pid = info.dwProcessId;
    return;

failed:
    if (processStarted) { TerminateProcess(info.hProcess, 1); }
    if (info.hThread) CloseHandle(info.hThread);
    if (attributes) { DeleteProcThreadAttributeList(attributes); HeapFree(GetProcessHeap(), 0, attributes); }
    if (clientIn != INVALID_HANDLE_VALUE) CloseHandle(clientIn);
    if (clientOut != INVALID_HANDLE_VALUE) CloseHandle(clientOut);
    if (pty->console) close(pty->console);   // nothing was read, and the child (if any) is gone or dying
    if (pty->job) CloseHandle(pty->job);
    if (pty->process) CloseHandle(pty->process);
    if (pty->readIO) CloseThreadpoolIo(pty->readIO);
    if (pty->writeIO) CloseThreadpoolIo(pty->writeIO);
    if (pty->out != INVALID_HANDLE_VALUE) CloseHandle(pty->out);
    if (pty->in != INVALID_HANDLE_VALUE) CloseHandle(pty->in);
    if (pty->endedEvent) CloseHandle(pty->endedEvent);
    if (pty->closerDone) CloseHandle(pty->closerDone);
    free(pty->ring);
    DeleteCriticalSection(&pty->lock);
    free(pty);
    fail(out, stage, code);
}

#endif
