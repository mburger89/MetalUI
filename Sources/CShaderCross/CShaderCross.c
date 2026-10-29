/* The run-time shader compiler loader (items XP-G25 and XP-G27, rulings RC-B..RC-S, HX-C, HX-D).
   SDL_shadercross is loaded with dlopen (LoadLibraryW on Windows), never linked, so MetalUI builds with
   no shadercross header or library and an absent library is a named error. The shadercross structs are
   mirrored here and pinned by static asserts to the layout measured at the pin
   (1ff05bec573988a98ef9e0260b4da44f512b8367, RC-H arm I, HX-B). The three SDL functions (SDL_GetError,
   SDL_ClearError, SDL_free) are resolved through the shadercross library's own handle, so they are always
   the SDL3 instance shadercross itself calls (HX-D). No SDL header: portable on every platform. */
#include "CShaderCross.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

/* Mirrors of SDL_shadercross.h at the pin. Enums are plain `int`; the stage is compute (2). */
enum { MUI_RSC_STAGE_COMPUTE = 2 };
typedef struct { char *name; char *value; } SCDefine;
typedef struct {
    const char *source;
    const char *entrypoint;
    const char *include_dir;
    SCDefine *defines;
    int shader_stage;
    uint32_t props;
} SCHLSLInfo;
typedef struct {
    const uint8_t *bytecode;
    size_t bytecode_size;
    const char *entrypoint;
    int shader_stage;
    uint32_t props;
} SCSPIRVInfo;
typedef struct {
    uint32_t num_samplers, num_readonly_storage_textures, num_readonly_storage_buffers,
             num_readwrite_storage_textures, num_readwrite_storage_buffers, num_uniform_buffers,
             threadcount_x, threadcount_y, threadcount_z;
} SCComputeMetadata;

#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
_Static_assert(sizeof(SCHLSLInfo) == 40 && offsetof(SCHLSLInfo, defines) == 24 && offsetof(SCHLSLInfo, shader_stage) == 32
               && offsetof(SCHLSLInfo, props) == 36, "SDL_ShaderCross_HLSL_Info layout");
_Static_assert(sizeof(SCDefine) == 16, "SDL_ShaderCross_HLSL_Define layout");
_Static_assert(sizeof(SCSPIRVInfo) == 32 && offsetof(SCSPIRVInfo, entrypoint) == 16 && offsetof(SCSPIRVInfo, shader_stage) == 24
               && offsetof(SCSPIRVInfo, props) == 28, "SDL_ShaderCross_SPIRV_Info layout");
#endif
_Static_assert(sizeof(SCComputeMetadata) == 36, "SDL_ShaderCross_ComputePipelineMetadata layout");
_Static_assert(sizeof(MuiRSCReflection) == sizeof(SCComputeMetadata), "reflection mirror");

struct MuiRSC {
    void *object;
    bool (*init)(void);
    void *(*compile_spirv)(const SCHLSLInfo *, size_t *);
    void *(*compile_dxil)(const SCHLSLInfo *, size_t *);
    void *(*transpile_msl)(const SCSPIRVInfo *);
    SCComputeMetadata *(*reflect)(const uint8_t *, size_t, uint32_t);
    const char *(*get_error)(void);
    bool (*clear_error)(void);
    void (*sdl_free)(void *);
};

static atomic_int g_loads;
static atomic_int g_empty_diagnostics;
static atomic_int g_inited;   /* Init runs once per process (the header: once, from one thread) */

int32_t mui_rsc_loads(void) { return atomic_load(&g_loads); }
void mui_rsc_test_empty_diagnostics(bool empty) { atomic_store(&g_empty_diagnostics, empty ? 1 : 0); }
void mui_rsc_free(const MuiRSC *rsc, void *pointer) { rsc->sdl_free(pointer); }

static void write_text(char *error, size_t capacity, const char *prefix, const char *text) {
    if (error == NULL || capacity == 0) return;
    snprintf(error, capacity, "%s%s", prefix, text ? text : "");
}

/* The compiler's own text, read on the calling thread right after the failing call (RC-D). */
static void set_error(const MuiRSC *rsc, char *error, size_t capacity, const char *prefix) {
    write_text(error, capacity, prefix, atomic_load(&g_empty_diagnostics) ? "" : rsc->get_error());
}

#ifdef _WIN32
static wchar_t *widen(const char *path) {
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *wide = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (wide == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n) <= 0) { free(wide); return NULL; }
    return wide;
}

static void add_dll_directory(const char *path) {
    wchar_t *wide = widen(path);
    if (wide == NULL) return;
    wchar_t *slash = NULL;
    for (wchar_t *p = wide; *p; ++p) if (*p == L'\\' || *p == L'/') slash = p;
    if (slash != NULL) { *slash = 0; SetDllDirectoryW(wide); }
    free(wide);
}

static void load_error_text(char *buffer, size_t capacity) {
    DWORD code = GetLastError();
    wchar_t *message = NULL;
    DWORD n = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                             NULL, code, 0, (LPWSTR)&message, 0, NULL);
    char utf8[1024]; utf8[0] = 0;
    if (n > 0 && message != NULL) {
        WideCharToMultiByte(CP_UTF8, 0, message, -1, utf8, (int)sizeof utf8, NULL, NULL);
        size_t len = strlen(utf8);
        while (len > 0 && (utf8[len - 1] == '\r' || utf8[len - 1] == '\n' || utf8[len - 1] == ' ')) utf8[--len] = 0;
    }
    if (message != NULL) LocalFree(message);
    snprintf(buffer, capacity, "LoadLibrary failed (%lu): %s", (unsigned long)code, utf8);
}

static void *open_library(const char *path) {
    wchar_t *wide = widen(path);
    if (wide == NULL) return NULL;
    void *handle = (void *)LoadLibraryW(wide);
    free(wide);
    return handle;
}
static void *find_symbol(void *handle, const char *name) { return (void *)GetProcAddress((HMODULE)handle, name); }
#else
static void load_error_text(char *buffer, size_t capacity) {
    const char *text = dlerror();
    snprintf(buffer, capacity, "%s", text ? text : "");
}
static void *open_library(const char *path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void *find_symbol(void *handle, const char *name) { return dlsym(handle, name); }
#endif

bool mui_rsc_process_has_sdl3(void) {
#ifdef _WIN32
    return GetModuleHandleW(L"SDL3.dll") != NULL;
#else
    return dlsym(RTLD_DEFAULT, "SDL_GetVersion") != NULL;
#endif
}

MuiRSC *mui_rsc_load(const char *path, const char *const *preload, uint32_t preload_count,
                     bool counted, char *error, size_t error_capacity) {
    if (error && error_capacity) error[0] = 0;
#ifdef _WIN32
    add_dll_directory(path);
#endif
    char text[2048];
    for (uint32_t i = 0; i < preload_count; i++) {
        /* Dependents stay loaded for the life of the process: the library's own load then finds them by name. */
        if (open_library(preload[i]) == NULL) {
            load_error_text(text, sizeof text);
            if (error && error_capacity) snprintf(error, error_capacity, "failed to load dependent %s: %s", preload[i], text);
            return NULL;
        }
    }
    void *object = open_library(path);
    if (object == NULL) {
        load_error_text(text, sizeof text);
        write_text(error, error_capacity, "", text);
        return NULL;
    }
    MuiRSC *rsc = (MuiRSC *)calloc(1, sizeof *rsc);
    if (rsc == NULL) { write_text(error, error_capacity, "out of memory", ""); return NULL; }
    rsc->object = object;
    rsc->init = (bool (*)(void))find_symbol(object, "SDL_ShaderCross_Init");
    rsc->compile_spirv = (void *(*)(const SCHLSLInfo *, size_t *))find_symbol(object, "SDL_ShaderCross_CompileSPIRVFromHLSL");
    rsc->compile_dxil = (void *(*)(const SCHLSLInfo *, size_t *))find_symbol(object, "SDL_ShaderCross_CompileDXILFromHLSL");
    rsc->transpile_msl = (void *(*)(const SCSPIRVInfo *))find_symbol(object, "SDL_ShaderCross_TranspileMSLFromSPIRV");
    rsc->reflect = (SCComputeMetadata *(*)(const uint8_t *, size_t, uint32_t))find_symbol(object, "SDL_ShaderCross_ReflectComputeSPIRV");
    /* The three SDL calls come from the instance shadercross itself uses (HX-D). On Windows the handle's
       dependency tree is not searchable, so the SDL3.dll module the loader bound is read instead. */
    void *sdl = object;
#ifdef _WIN32
    sdl = (void *)GetModuleHandleW(L"SDL3.dll");
#endif
    if (sdl != NULL) {
        rsc->get_error = (const char *(*)(void))find_symbol(sdl, "SDL_GetError");
        rsc->clear_error = (bool (*)(void))find_symbol(sdl, "SDL_ClearError");
        rsc->sdl_free = (void (*)(void *))find_symbol(sdl, "SDL_free");
    }
    const char *missing =
        !rsc->init ? "SDL_ShaderCross_Init" : !rsc->compile_spirv ? "SDL_ShaderCross_CompileSPIRVFromHLSL"
        : !rsc->compile_dxil ? "SDL_ShaderCross_CompileDXILFromHLSL"
        : !rsc->transpile_msl ? "SDL_ShaderCross_TranspileMSLFromSPIRV" : !rsc->reflect ? "SDL_ShaderCross_ReflectComputeSPIRV"
        : !rsc->get_error ? "SDL_GetError" : !rsc->clear_error ? "SDL_ClearError" : !rsc->sdl_free ? "SDL_free" : NULL;
    if (missing != NULL) {
        if (error && error_capacity) snprintf(error, error_capacity, "%s is not SDL_shadercross at the pin: %s is missing", path, missing);
        free(rsc);   /* the object is left loaded: a library is never unloaded (RC-B) */
        return NULL;
    }
    rsc->clear_error();
    int expected = 0;
    if (atomic_compare_exchange_strong(&g_inited, &expected, 1) && !rsc->init()) {
        atomic_store(&g_inited, 0);
        set_error(rsc, error, error_capacity, "SDL_ShaderCross_Init failed: ");
        free(rsc);
        return NULL;
    }
    if (counted) atomic_fetch_add(&g_loads, 1);
    return rsc;
}

int32_t mui_rsc_compile_hlsl(const MuiRSC *rsc, int32_t target, const char *source, const char *entry,
                             const char *include_dir, const char *const *define_names,
                             const char *const *define_values, uint32_t define_count,
                             uint8_t **out, size_t *out_size, char *error, size_t error_capacity) {
    *out = NULL; *out_size = 0;
    SCDefine *defines = NULL;
    if (define_count > 0) {
        /* The array ends with a fully NULL define (the pin's contract). */
        defines = (SCDefine *)calloc((size_t)define_count + 1, sizeof(SCDefine));
        if (defines == NULL) { write_text(error, error_capacity, "out of memory", ""); return 1; }
        for (uint32_t i = 0; i < define_count; i++) {
            defines[i].name = (char *)define_names[i];
            defines[i].value = define_values[i] ? (char *)define_values[i] : NULL;
        }
    }
    SCHLSLInfo info; memset(&info, 0, sizeof info);
    info.source = source; info.entrypoint = entry; info.include_dir = include_dir;
    info.defines = defines; info.shader_stage = MUI_RSC_STAGE_COMPUTE;
    size_t size = 0;
    rsc->clear_error();
    void *bytes = (target == 1 ? rsc->compile_dxil : rsc->compile_spirv)(&info, &size);
    if (bytes == NULL) set_error(rsc, error, error_capacity, "");   /* read before any other call (RC-D) */
    free(defines);
    if (bytes == NULL) return 1;
    *out = (uint8_t *)bytes; *out_size = size;
    return 0;
}

int32_t mui_rsc_msl(const MuiRSC *rsc, const uint8_t *spirv, size_t size, const char *entry,
                    uint8_t **out, size_t *out_size, char *error, size_t error_capacity) {
    *out = NULL; *out_size = 0;
    SCSPIRVInfo info; memset(&info, 0, sizeof info);
    info.bytecode = spirv; info.bytecode_size = size; info.entrypoint = entry; info.shader_stage = MUI_RSC_STAGE_COMPUTE;
    rsc->clear_error();
    void *text = rsc->transpile_msl(&info);
    if (text == NULL) { set_error(rsc, error, error_capacity, ""); return 1; }
    *out = (uint8_t *)text; *out_size = strlen((const char *)text);
    return 0;
}

int32_t mui_rsc_reflect(const MuiRSC *rsc, const uint8_t *spirv, size_t size, MuiRSCReflection *out,
                        char *error, size_t error_capacity) {
    rsc->clear_error();
    SCComputeMetadata *metadata = rsc->reflect(spirv, size, 0);
    if (metadata == NULL) { set_error(rsc, error, error_capacity, ""); return 1; }
    out->samplers = metadata->num_samplers;
    out->readonly_storage_textures = metadata->num_readonly_storage_textures;
    out->readonly_storage_buffers = metadata->num_readonly_storage_buffers;
    out->readwrite_storage_textures = metadata->num_readwrite_storage_textures;
    out->readwrite_storage_buffers = metadata->num_readwrite_storage_buffers;
    out->uniform_buffers = metadata->num_uniform_buffers;
    out->threadcount_x = metadata->threadcount_x;
    out->threadcount_y = metadata->threadcount_y;
    out->threadcount_z = metadata->threadcount_z;
    rsc->sdl_free(metadata);
    return 0;
}
